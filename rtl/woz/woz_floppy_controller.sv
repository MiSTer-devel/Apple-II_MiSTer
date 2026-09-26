//============================================================================
//  WOZ floppy controller -- track streaming and write-back
//
//  Copyright (c) 2026 Alan Steremberg
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program. If not, see <https://www.gnu.org/licenses/>.
//============================================================================


module woz_floppy_controller #(
    parameter IS_35_INCH = 0,
    parameter BRAM_ADDR_WIDTH = IS_35_INCH ? 16 : 15  // 64KB for 3.5", 32KB for 5.25" (supports FLUX tracks)
) (
    input             clk,
    input             reset,

    // SD Block Device Interface
    output reg [31:0] sd_lba,
    output reg        sd_rd,
    output reg        sd_wr,
    input             sd_ack,
    input      [8:0]  sd_buff_addr,
    input      [7:0]  sd_buff_dout,
    output     [7:0]  sd_buff_din,
    input             sd_buff_wr,

    // Disk Status
    input             img_mounted,
    input             img_readonly,
    input      [63:0] img_size,

    // Drive Interface
    input      [7:0]  track_id,      // TMAP Index: 3.5"={track[6:0],side}, 5.25"={2'b0,qtr_track}
    output reg        ready,         // High when valid WOZ loaded and track ready
    output wire       disk_mounted,  // High when valid WOZ is loaded (stays high, doesn't toggle during seeks)
    output reg        busy,          // High during load/save operations
    input             active,        // Motor active (used for save triggers)

    // Bitstream Interface (to IWM)
    output wire [31:0] bit_count,    // Number of bits in current track (combinational mux)
    input      [15:0] bit_addr,      // Read address (16-bit for FLUX tracks up to 64KB)
    input             stable_side,   // Stable side for data reads (captured when motor starts)
    output     [7:0]  bit_data,      // Read data
    input      [7:0]  bit_data_in,   // Write data
    input             bit_we,        // Write enable (sets dirty)
    input      [15:0] bit_wr_addr,   // Write address (latched, may differ from bit_addr)

    // Track load notification (for flux_drive to reset position)
    output reg        track_load_complete,  // Pulses high for 1 cycle when physical track finishes loading

    // FLUX track support (WOZ v3)
    output wire       is_flux_track,        // Current track uses flux timing data (not bitstream)
    output wire [31:0] flux_data_size,      // Size in bytes of flux timing data (when is_flux_track=1)
    output wire [31:0] flux_total_ticks,    // Sum of FLUX bytes for timing normalization

    // Track data validity (independent of controller state)
    // Unlike `ready` (which requires state == S_IDLE), this signal indicates that the BRAM
    // data for the currently selected side matches the requested track. It stays high even
    // while the controller is loading the OTHER side. This prevents flux playback from being
    // suppressed during dual-side track loads.
    output wire       track_data_valid,

    // Disk type mismatch detection
    output wire       disk_type_mismatch, // High when loaded WOZ disk_type doesn't match IS_35_INCH

    // Write-protect flag from WOZ INFO chunk (byte offset 2).
    // Some copy-protection (e.g. Wizardry) refuses to boot unless the disk reports WP=1.
    output wire       disk_write_protected,

    // Optimal bit timing from WOZ INFO chunk (byte offset 39), in 125ns units.
    // 32 = the 4us standard for 5.25"; a handful of titles master at 28/29/34.
    // 0 when absent (WOZ1 has no such field) -- consumers treat 0 as "standard".
    output wire [7:0] optimal_bit_timing,

    // DEBUG: running sum of all sd_buff bytes received during track loads
    // (S_READ_TRACK). Reset at each load start. Compared between sim (golden)
    // and FPGA overlay to detect HPS data-delivery corruption.
    output reg [15:0] dbg_load_sum,
    // DEBUG: byte count and ack-fall (block) count for the same load window.
    output reg [13:0] dbg_load_bytes,
    output reg [7:0]  dbg_load_blocks
);

    //=========================================================================
    // Internal State
    //=========================================================================
    
    // Meta RAM: 2KB (Stores Blocks 0-3 of WOZ file)
    // - Header: 0-11
    // - INFO: 20-79
    // - TMAP: 88-247
    // - TRKS: 256-1535 (160 entries * 8 bytes)
    reg  [10:0] meta_addr;
    wire [7:0]  meta_dout;
    reg         meta_we;
    reg  [7:0]  meta_din;
    
    woz_bram #(.width_a(8), .widthad_a(11)) meta_ram (
        .clock_a(clk),
        .address_a(meta_addr),
        .wren_a(meta_we),
        .data_a(meta_din),
        .q_a(meta_dout),
        .clock_b(clk),
        .address_b(meta_read_addr), // Port B used for lookups
        .wren_b(1'b0),
        .data_b(8'h00),
        .q_b(meta_read_data)
    );

    // Track RAM: 16KB per side (3.5") (Stores bitstream)
    //
    // IMPORTANT: On the IIgs, the Sony protocol uses HDSEL/SEL (bit7 of $C031) as both:
    // - the "SEL" bit in the 4-bit command/address nibble, and
    // - the physical head select.
    //
    // The ROM frequently toggles SEL as part of status reads (e.g. /READY is addr $0B),
    // which would cause a naïve SD-backed loader to thrash-reload side 0/1 repeatedly.
    // Real hardware switches heads instantly; emulate that by caching each side's track
    // bitstream independently and just muxing the output on SEL changes.
    reg  [15:0] track_load_addr;  // 16-bit to support tracks up to 128 blocks (64KB)
    reg         track_load_we;
    reg  [7:0]  track_load_data;
    wire [7:0]  track_ram_dout0;
    wire [7:0]  track_ram_dout1;
    wire [7:0]  bit_data0;
    wire [7:0]  bit_data1;
    reg         load_side;   // Which side is currently being DMA-loaded/saved (3.5" only)
    reg         track_load_side; // Side captured with track_load_* for synchronous BRAM write

    // During S_SAVE_TRACK, sd_buff_addr drives BRAM directly. Port A is synchronous, so
    // q_a updates on clk edges; register the save-side output before handing it to the
    // block device so the address/data pairing is stable at the simulator boundary.
    wire [BRAM_ADDR_WIDTH-1:0] save_bram_addr = {blocks_processed[BRAM_ADDR_WIDTH-10:0], sd_buff_addr};
    wire saving_active = (state == S_SAVE_TRACK);
    wire [BRAM_ADDR_WIDTH-1:0] bram_addr_a = saving_active ? save_bram_addr : track_load_addr[BRAM_ADDR_WIDTH-1:0];

    // sd_buff_din is always registered. In save mode this avoids exposing BRAM q_a as a raw
    // combinational path to the C++ block-device shim, which can otherwise sample stale data
    // around sd_buff_addr changes.
    reg  [7:0]  sd_buff_din_reg;
    wire [7:0]  save_din = (IS_35_INCH && save_side) ? track_ram_dout1 : track_ram_dout0;
    assign sd_buff_din = sd_buff_din_reg;

    // Per-side dirty flags (track which side was modified by IWM writes)
    reg         dirty_side0;
    reg         dirty_side1;
`ifdef DEBUG_VERBOSE
    reg [31:0]  bit_we_count;
`endif
    // Per-side track location metadata (for correct save-back to WOZ file)
    reg  [15:0] trk_start_block_side0;
    reg  [15:0] trk_start_block_side1;
    reg  [15:0] trk_block_count_side0;
    reg  [15:0] trk_block_count_side1;
    // Save state tracking
    reg         save_side;          // Which side is currently being saved
    reg         saving_second_side; // Need to save the other side after current save
    reg         save_is_flush;      // Save triggered by motor-off (return to IDLE, not SEEK)

    // BRAM port B address mux: use latched write address during writes, read address otherwise.
    // The read-modify-write in flux_drive latches BRAM_ADDR at read time (cycle N), but by
    // write time (cycle N+1) bit_position has advanced so bit_addr may point to a different byte.
    // Using the latched address ensures the modified byte is written back to the correct location.
    wire [15:0] bram_addr_b = bit_we ? bit_wr_addr : bit_addr;

    // Dual port RAM for Track Data (Side 0) — used by both 3.5" and 5.25"
    woz_bram #(.width_a(8), .widthad_a(BRAM_ADDR_WIDTH)) track_ram_side0 (
        .clock_a(clk),
        .address_a(bram_addr_a),
        .wren_a(track_load_we && (!IS_35_INCH || (track_load_side == 1'b0))),
        .data_a(track_load_data),
        .q_a(track_ram_dout0),

        .clock_b(clk),
        .address_b(bram_addr_b[BRAM_ADDR_WIDTH-1:0]),
        .wren_b(bit_we && (!IS_35_INCH || (track_id[0] == 1'b0))),
        .data_b(bit_data_in),
        .q_b(bit_data0)
    );

    // Dual port RAM for Track Data (Side 1) — 3.5" only (double-sided)
    generate
        if (IS_35_INCH) begin : gen_side1_ram
            woz_bram #(.width_a(8), .widthad_a(BRAM_ADDR_WIDTH)) track_ram_side1 (
                .clock_a(clk),
                .address_a(bram_addr_a),
                .wren_a(track_load_we && (track_load_side == 1'b1)),
                .data_a(track_load_data),
                .q_a(track_ram_dout1),

                .clock_b(clk),
                .address_b(bram_addr_b),
                .wren_b(bit_we && (track_id[0] == 1'b1)),
                .data_b(bit_data_in),
                .q_b(bit_data1)
            );
        end else begin : gen_no_side1
            assign track_ram_dout1 = 8'd0;
            assign bit_data1 = 8'd0;
        end
    endgenerate

    // Use stable_side for data reads - this prevents SEL toggling during status reads
    // from causing the mux to return data from the wrong side
    assign bit_data = (IS_35_INCH && stable_side) ? bit_data1 : bit_data0;

    // bit_count: Return the correct bit_count for the requested track.
    //
    // The single-track-per-side BRAM cache means only ONE track per side is stored.
    // When seeking to a new track, we need to return the CORRECT bit_count:
    //
    // 1. If requested track matches cached track → return cached bit_count (correct data in BRAM)
    // 2. If currently loading a track → return the pending track's bit_count (trk_bit_count)
    //    This gives flux_drive a reasonable bit_count during loading (data is garbage anyway)
    // 3. Otherwise → return cached side's bit_count (best effort for rapid SEL toggles)
    //
    // The key insight: returning bit_count=0 causes no flux transitions, which makes
    // the ROM timeout waiting for data. Returning a reasonable non-zero value lets
    // flux_drive generate flux (even from garbage data) which keeps the ROM responsive.
    //
    // After track load completes, current_track_id_sideX is updated and the correct
    // bit_count is returned for subsequent reads.
    wire track_side0_match = (current_track_id_side0 == track_id);
    wire track_side1_match = (current_track_id_side1 == track_id);
    // Use stable_side for all runtime selections to prevent toggling during status reads
    wire selected_track_match = (IS_35_INCH && stable_side) ? track_side1_match : track_side0_match;
    wire [31:0] selected_bit_count = (IS_35_INCH && stable_side) ? bit_count_side1 : bit_count_side0;
    wire is_loading = (state == S_SEEK_LOOKUP) || (state == S_READ_TRACK);

    // track_data_valid: BRAM data for the selected side matches the requested track.
    // Unlike `ready`, this does NOT require state == S_IDLE. It stays true when the
    // controller is busy loading the other side, allowing flux playback to continue.
    // Use track_id[0] (not stable_side) for side selection to avoid 1-cycle phase mismatch:
    // track_id already encodes the side, so this stays in sync regardless of stable_side timing.
    wire track_data_valid_match = (IS_35_INCH && track_id[0]) ? track_side1_match : track_side0_match;
    assign track_data_valid = woz_valid && track_data_valid_match;
    // During loading, use the pending track's bit_count IF we're loading the stable_side.
    // If we're loading the other side, keep using selected_bit_count to avoid glitches.
    wire loading_matches_stable = (!IS_35_INCH) || (load_side == stable_side);
    wire [31:0] loading_bit_count = (trk_bit_count > 0 && loading_matches_stable) ? trk_bit_count : selected_bit_count;
    assign bit_count = woz_valid ? (selected_track_match ? selected_bit_count :
                                    (is_loading ? loading_bit_count : selected_bit_count)) : 32'd0;

    // FLUX track format selection - use stable_side like bit_count
    wire selected_is_flux = (IS_35_INCH && stable_side) ? is_flux_side1 : is_flux_side0;
    wire [31:0] selected_flux_size = (IS_35_INCH && stable_side) ? flux_size_side1 : flux_size_side0;
    wire [31:0] selected_flux_total_ticks = (IS_35_INCH && stable_side) ?
                                            flux_total_ticks_side1 : flux_total_ticks_side0;
    assign is_flux_track = woz_valid ? (selected_track_match ? selected_is_flux :
                                        (is_loading ? pending_is_flux : selected_is_flux)) : 1'b0;
    assign flux_data_size = woz_valid ? (selected_track_match ? selected_flux_size :
                                         (is_loading && pending_is_flux ? trk_bit_count : selected_flux_size)) : 32'd0;
    assign flux_total_ticks = woz_valid ? (selected_track_match ? selected_flux_total_ticks :
                                           (is_loading && pending_is_flux ? pending_flux_total_ticks : selected_flux_total_ticks)) : 32'd0;

    // State Machine
    localparam S_INIT        = 0;
    localparam S_DETECT      = 1;
    localparam S_SCAN_WOZ    = 2; // Scan header + chunks to cache INFO/TMAP/TRKS
    localparam S_IDLE        = 3;
    localparam S_SEEK_LOOKUP = 4;
    localparam S_READ_TRACK  = 5;
    localparam S_SAVE_TRACK  = 6;

    reg [3:0] state = S_INIT;
    reg [7:0] current_track_id_side0;
    reg [7:0] current_track_id_side1;
    reg [7:0] pending_track_id;
    reg       woz_valid;
    reg       old_ack;

    // For 3.5" dual-side loading: load both sides when physical track changes
    reg       loading_second_side;    // Set after side 0 loaded, cleared after side 1
    reg [6:0] target_physical_track;  // Physical track being loaded (track_id[7:1])

    // Settling time: wait for PHYSICAL track to be stable before loading
    // During fast seeks (boot), the head steps rapidly through tracks.
    // Starting a load before settling causes thrashing restarts.
    // IMPORTANT: Use physical track (track_id[7:1]) NOT full track_id,
    // because SEL toggles (track_id[0]) shouldn't reset settling.
    reg [6:0]  last_physical_track;   // Previous physical track for change detection
    reg [19:0] settle_counter;        // Cycles since last physical track change
    localparam SETTLE_THRESHOLD = 20'd50000;   // 3.5": ~3.5ms head settle
    // 5.25": with the debounced (physical) head walk, seek code rests ~19ms per
    // quarter-track transit and the physical-track pair changes every 2 rests
    // (~38ms). Loading every transit position lets slow real-SD track loads lag
    // the head (boot read races -> intermittent boots on HW). 45ms only loads
    // truly settled positions. Half-track hops within the same physical pair
    // (copy-protection nudges) do NOT reset the counter and still load at once.
    localparam SETTLE_525 = 20'd50000;         // 3.5ms (same as 3.5"): with the
    // data-valid playback gate below, transit loads only cost time and never
    // feed stale data, so no long settle is needed (45ms made boots crawl)
    wire [19:0] settle_lim = IS_35_INCH ? SETTLE_THRESHOLD : SETTLE_525;

    // Dirty flush timer: flush dirty tracks to disk after writes stop
    // Handles the case where the ROM writes to a track and reads back without
    // changing tracks or stopping the motor.
    reg [23:0] dirty_flush_timer;
    localparam [23:0] DIRTY_FLUSH_DELAY = 24'd7000000; // ~500ms at 14MHz

    reg [31:0] bit_count_side0;
    reg [31:0] bit_count_side1;
    reg [31:0] flux_total_ticks_side0;
    reg [31:0] flux_total_ticks_side1;
    reg [31:0] pending_flux_total_ticks;

    // Motor-off save trigger: flush dirty tracks when motor spins down
    reg         prev_active;

    // Debug
    reg [7:0] last_debug_track_id;

    // disk_mounted is a stable "media present" signal and should go true as soon as the
    // image is mounted. The old C++ WOZ path reported media present immediately; delaying
    // until the metadata scan completes can cause ROM timeouts while it polls /DIP.
`ifdef WOZ_DISK_MOUNTED_AFTER_PARSE
    assign disk_mounted = img_mounted && woz_valid;
`else
    assign disk_mounted = img_mounted && !scan_failed;
`endif

    // Disk type mismatch: WOZ INFO disk_type 1=5.25", 2=3.5"
    assign disk_type_mismatch = woz_valid && ((IS_35_INCH && info_disk_type == 8'd1) || (!IS_35_INCH && info_disk_type == 8'd2));
    assign disk_write_protected = woz_valid && (info_wp != 8'd0);
    assign optimal_bit_timing   = woz_valid ? info_bit_timing : 8'd0;

    // WOZ Parsing
    reg [10:0] meta_read_addr;
    wire [7:0] meta_read_data;

    localparam [10:0] META_TMAP_BASE = 11'd0;
    localparam [10:0] META_TRKS_BASE = 11'd256;
    localparam [10:0] META_FLUX_BASE = 11'd1536;  // After TRKS (256 + 160*8 = 1536)

    // Streaming WOZ parser: caches INFO/TMAP/TRKS by scanning file chunks (WOZ1/WOZ2).
    reg        have_info;
    reg        have_tmap;
    reg        have_trks;
    reg [15:0] scan_blocks;

    // WOZ header is 12 bytes:
    // 4 bytes signature ("WOZ1"/"WOZ2"), 4 bytes 0xFF 0x0A 0x0D 0x0A, 4 bytes CRC32.
    reg  [3:0] hdr_pos;          // 0..11
    reg  [2:0] chunk_hdr_pos;    // 0..7  (chunk header is 8 bytes)
    reg [31:0] chunk_id;
    reg [31:0] chunk_size_acc;
    reg [31:0] chunk_left;
    reg [31:0] chunk_index;

    // INFO fields (mostly for debug)
    reg  [7:0] info_version;
    reg  [7:0] info_disk_type;
    reg  [7:0] info_wp;           // INFO byte 2: write-protected (1=WP, 0=writable)
    reg  [7:0] info_bit_timing;

    // WOZ v3 FLUX support
    reg [15:0] info_flux_block;      // Starting block for flux data in TRKS (INFO offset 46-47)
    reg        have_flux;            // FLUX chunk was parsed
    reg        pending_is_flux;      // Track being loaded is flux format
    reg        is_flux_side0;        // Side 0 has flux data (not bitstream)
    reg        is_flux_side1;        // Side 1 has flux data (not bitstream)
    reg [31:0] flux_size_side0;      // Flux data size in bytes for side 0
    reg [31:0] flux_size_side1;      // Flux data size in bytes for side 1

    // Parser is done when we have all required chunks.
    // For INFO v3 with flux_block set, we also need the FLUX chunk.
    wire need_flux = (info_version >= 8'd3) && (info_flux_block != 16'd0);
    wire parser_done = have_info && have_tmap && have_trks && (!need_flux || have_flux);
    localparam [15:0] SCAN_BLOCK_LIMIT = 16'd16000; // safety: stop scanning after ~8MB (FLUX chunk comes after large TRKS in v3 files)
    reg scan_failed;

    // TRKS skip optimization: after parsing TRKS metadata, skip remaining data blocks
    reg [15:0] scan_skip_target;   // Target block to skip to (0 = no skip pending)
    reg        scan_skip_active;   // Skip is in progress
    reg        scan_skip_discard;  // Discard remaining bytes in current block after skip

    // WOZ v1 support: v1 TRKS contains raw track data inline (35 × 6656 bytes),
    // not the v2 metadata table. We compute track locations directly.
    reg        is_woz_v1;              // WOZ v1 format flag
    reg [15:0] trks_base_block;        // File block number where TRKS data starts
    reg [8:0]  trks_byte_offset;       // Byte offset within that block
    reg [15:0] v1_bit_count;           // Captured bit count during v1 DMA (from track bytes 6648-6649)
    
    // Current Track Info
    reg [15:0] trk_start_block;
    reg [15:0] trk_block_count;
    reg [31:0] trk_bit_count;
    
    // SD Operation
    reg [15:0] blocks_processed;
    
    // Mount Edge Detection
    reg prev_mounted;

    // Track active transfers to filter spurious sd_ack falling edges
    // transfer_active is set when sd_ack rises after sd_rd/sd_wr was asserted
    // It's cleared when the transfer completes (sd_ack falls)
    reg transfer_active;

    // Track when we've issued a new request that the C++ hasn't processed yet
    // This prevents attributing an old transfer's sd_ack to our new request
    reg request_issued;

    always @(posedge clk) begin
        old_ack <= sd_ack;

        // Track when a real transfer is in progress
        // Rising edge of sd_ack after we issued a request means OUR transfer started
        // Only accept if request_issued is true (we sent a NEW request)
        if (!old_ack && sd_ack && request_issued) begin
            transfer_active <= 1'b1;
            request_issued <= 1'b0;  // Request has been acknowledged
        end
        // Falling edge of sd_ack means transfer complete - clear for next one
        if (old_ack && !sd_ack) begin
            transfer_active <= 1'b0;
        end

        // Set request_issued when we assert sd_rd/sd_wr while no transfer is active
        // This marks the start of OUR request
        if ((sd_rd || sd_wr) && !sd_ack && !transfer_active && !request_issued) begin
            request_issued <= 1'b1;
        end

	        if (reset) begin
	            state <= S_INIT;
	            ready <= 0;
	            busy <= 0;
	            woz_valid <= 0;
	            prev_mounted <= 0;
	            sd_rd <= 0;
	            sd_wr <= 0;
	            dirty_side0 <= 0;
	            dirty_side1 <= 0;
	            dirty_flush_timer <= 24'd0;
`ifdef DEBUG_VERBOSE
                bit_we_count <= 0;
`endif
            current_track_id_side0 <= 8'hFF;
            current_track_id_side1 <= 8'hFF;
	            pending_track_id <= 8'h00;
	            load_side <= 1'b0;
	            track_load_side <= 1'b0;
            save_side <= 1'b0;
            saving_second_side <= 1'b0;
            save_is_flush <= 1'b0;
            prev_active <= 1'b0;
            trk_start_block_side0 <= 16'd0;
            trk_start_block_side1 <= 16'd0;
            trk_block_count_side0 <= 16'd0;
            trk_block_count_side1 <= 16'd0;
            old_ack <= 1'b0;
            transfer_active <= 1'b0;
            request_issued <= 1'b0;
            loading_second_side <= 1'b0;
            target_physical_track <= 7'h7F;
            last_physical_track <= 7'h7F;
            settle_counter <= 20'd0;
            bit_count_side0 <= 32'd0;
            bit_count_side1 <= 32'd0;
            flux_total_ticks_side0 <= 32'd0;
            flux_total_ticks_side1 <= 32'd0;
            pending_flux_total_ticks <= 32'd0;
            track_load_complete <= 1'b0;
	            // bit_count is now a wire (combinational mux), no reset needed
	            sd_buff_din_reg <= 8'h00;
	            have_info <= 1'b0;
	            have_tmap <= 1'b0;
	            have_trks <= 1'b0;
	            scan_blocks <= 16'd0;
	            scan_skip_target <= 16'd0;
	            scan_skip_active <= 1'b0;
	            scan_skip_discard <= 1'b0;
	            hdr_pos <= 4'd0;
	            chunk_hdr_pos <= 3'd0;
	            chunk_id <= 32'd0;
	            chunk_size_acc <= 32'd0;
	            chunk_left <= 32'd0;
	            chunk_index <= 32'd0;
	            info_version <= 8'd0;
	            info_disk_type <= 8'd0;
	            info_wp <= 8'd0;
	            info_bit_timing <= 8'd0;
	            info_flux_block <= 16'd0;
	            have_flux <= 1'b0;
	            pending_is_flux <= 1'b0;
	            is_flux_side0 <= 1'b0;
	            is_flux_side1 <= 1'b0;
                flux_size_side0 <= 32'd0;
                flux_size_side1 <= 32'd0;
                scan_failed <= 1'b0;
                is_woz_v1 <= 1'b0;
                trks_base_block <= 16'd0;
                trks_byte_offset <= 9'd0;
                v1_bit_count <= 16'd0;
	        end else begin

            // Default signals
            meta_we <= 0;
            track_load_we <= 0;
            track_load_complete <= 1'b0;  // Default low, pulse high when track load finishes
            // SD requests are level-based in the MiSTer-style block device interface.
            // Assert a request only while we are waiting for `sd_ack` to go high, then
            // deassert during the transfer to avoid re-triggering when the transfer ends.
            sd_rd <= 1'b0;
            sd_wr <= 1'b0;
            if (saving_active) begin
                if (sd_ack) begin
                    sd_buff_din_reg <= save_din;
                end
            end else begin
                sd_buff_din_reg <= 8'h00;
            end

            // bit_count is now combinational (assigned above), no registered assignment needed

            // Debug: show bit_count selection when track_id changes
            if (IS_35_INCH && track_id != last_debug_track_id) begin
                $display("WOZ_BIT_COUNT: track_id=%0d track_id[0]=%0d -> selecting %s (side0=%0d side1=%0d)",
                         track_id, track_id[0],
                         track_id[0] ? "side1" : "side0",
                         bit_count_side0, bit_count_side1);
                last_debug_track_id <= track_id;
            end

            // Default: ready when the selected side is cached for the current track_id
            if (IS_35_INCH) begin
                ready <= woz_valid && (state == S_IDLE) &&
                         ((track_id[0] ? current_track_id_side1 : current_track_id_side0) == track_id);
            end else begin
                ready <= woz_valid && (state == S_IDLE) && (current_track_id_side0 == track_id);
            end
            
	            // Mount detection
	            if (img_mounted && !prev_mounted) begin
	                state <= S_DETECT;
	                ready <= 0;
	                busy <= 1;
	                woz_valid <= 0;
	                dirty_side0 <= 0;
	                dirty_side1 <= 0;
	                current_track_id_side0 <= 8'hFF;
	                current_track_id_side1 <= 8'hFF;
                bit_count_side0 <= 32'd0;
                bit_count_side1 <= 32'd0;
                flux_total_ticks_side0 <= 32'd0;
                flux_total_ticks_side1 <= 32'd0;
                pending_flux_total_ticks <= 32'd0;
	                // We will load the requested track after parsing metadata.
	                pending_track_id <= track_id;
	                load_side <= track_id[0];
	                loading_second_side <= 1'b0;
	                target_physical_track <= track_id[7:1];
	                track_load_side <= 1'b0;
	                have_info <= 1'b0;
	                have_tmap <= 1'b0;
	                have_trks <= 1'b0;
	                scan_blocks <= 16'd0;
	                scan_skip_target <= 16'd0;
	                scan_skip_active <= 1'b0;
	                hdr_pos <= 4'd0;
	                chunk_hdr_pos <= 3'd0;
	                chunk_id <= 32'd0;
	                chunk_size_acc <= 32'd0;
	                chunk_left <= 32'd0;
	                chunk_index <= 32'd0;
	                info_version <= 8'd0;
	                info_disk_type <= 8'd0;
	                info_wp <= 8'd0;
	                info_bit_timing <= 8'd0;
	                info_flux_block <= 16'd0;
	                have_flux <= 1'b0;
	                pending_is_flux <= 1'b0;
	                is_flux_side0 <= 1'b0;
	                is_flux_side1 <= 1'b0;
	                flux_size_side0 <= 32'd0;
	                flux_size_side1 <= 32'd0;
	                scan_failed <= 1'b0;
	                is_woz_v1 <= 1'b0;
	                trks_base_block <= 16'd0;
	                trks_byte_offset <= 9'd0;
	                v1_bit_count <= 16'd0;
	            end
	            // Unmount: drop validity immediately.
	            if (!img_mounted && prev_mounted) begin
	                woz_valid <= 1'b0;
	                ready <= 1'b0;
	                busy <= 1'b0;
	                dirty_side0 <= 1'b0;
	                dirty_side1 <= 1'b0;
	                current_track_id_side0 <= 8'hFF;
	                current_track_id_side1 <= 8'hFF;
                bit_count_side0 <= 32'd0;
                bit_count_side1 <= 32'd0;
                flux_total_ticks_side0 <= 32'd0;
                flux_total_ticks_side1 <= 32'd0;
                pending_flux_total_ticks <= 32'd0;
                track_load_side <= 1'b0;
	                have_info <= 1'b0;
	                have_tmap <= 1'b0;
	                have_trks <= 1'b0;
	                have_flux <= 1'b0;
	                is_flux_side0 <= 1'b0;
	                is_flux_side1 <= 1'b0;
	                flux_size_side0 <= 32'd0;
	                flux_size_side1 <= 32'd0;
	                state <= S_INIT;
	                scan_failed <= 1'b0;
	            end
	            prev_mounted <= img_mounted;
            
            // Set per-side dirty flag on bit writes.
            // Only if that side actually has mapped blocks: an unmapped (TMAP==FF)
            // track has nowhere to be written back to, and marking it dirty would
            // flush the BRAM over whichever track's blocks were last loaded.
            if (bit_we) begin
                if (IS_35_INCH && track_id[0]) begin
                    if (trk_block_count_side1 != 16'd0)
                        dirty_side1 <= 1;
                end else begin
                    if (trk_block_count_side0 != 16'd0)
                        dirty_side0 <= 1;
                end
`ifdef DEBUG_VERBOSE
                // Log dirty transitions (always) and first/periodic writes
                if (!dirty_side0 && !(IS_35_INCH && track_id[0]))
                    $display("WOZ_DIRTY_SET[%0d]: side0 now dirty, bit_we_count=%0d track_id=%0d state=%0d bram_b=%04X",
                             IS_35_INCH, bit_we_count, track_id, state, bram_addr_b);
                if (!dirty_side1 && IS_35_INCH && track_id[0])
                    $display("WOZ_DIRTY_SET[%0d]: side1 now dirty, bit_we_count=%0d track_id=%0d state=%0d bram_b=%04X",
                             IS_35_INCH, bit_we_count, track_id, state, bram_addr_b);
                if (bit_we_count < 32'd200 || (bit_we_count & 32'hFFFF) == 0)
                    $display("WOZ_WRITE[%0d]: bit_we #%0d rd_addr=%0d wr_addr=%0d bram_b=%04X data_in=%02X track_id=%0d side=%0d state=%0d dirty_s0=%0d dirty_s1=%0d",
                             IS_35_INCH, bit_we_count, bit_addr, bit_wr_addr, bram_addr_b, bit_data_in, track_id, track_id[0], state, dirty_side0, dirty_side1);
                bit_we_count <= bit_we_count + 1'd1;
`endif
            end
            
            // State Machine
            case (state)
	                S_INIT: begin
	                    busy <= 0;
	                    ready <= 0;
	                    if (img_mounted && !scan_failed) begin
	                        state <= S_DETECT;
	                        $display("WOZ_CTRL: Mount detected, starting WOZ scan");
	                    end
	                end
	                
	                S_DETECT: begin
	                    // Prepare to scan WOZ header/chunks from start of file.
	                    state <= S_SCAN_WOZ;
	                    sd_lba <= 32'd0;
	                    scan_blocks <= 16'd0;
	                    scan_skip_target <= 16'd0;
	                    scan_skip_active <= 1'b0;
	                    scan_skip_discard <= 1'b0;
	                    if (!sd_ack) sd_rd <= 1'b1;
	                end

	                S_SCAN_WOZ: begin
	                    // Assert sd_rd while waiting for ack, but NOT when completing a transfer
	                    // (completing happens when sd_ack just fell, sd_ack is 0 but we shouldn't
	                    // trigger another read immediately)
	                    if (!sd_ack && !(old_ack && transfer_active)) begin
	                        sd_rd <= 1'b1;
	                    end

	                    // SKIP HANDLING: When scan_skip_active, jump directly to target block
	                    // This avoids reading 2000+ unnecessary blocks.
	                    // Set sd_lba one less than target since block completion will increment it.
	                    if (scan_skip_active) begin
	                        // Seek directly to target block (subtract 1 because block completion will +1)
	                        sd_lba <= {16'b0, scan_skip_target} - 32'd1;
	                        scan_blocks <= scan_skip_target - 16'd1;
	                        scan_skip_active <= 1'b0;
	                        scan_skip_discard <= 1'b1;  // Discard remaining bytes in current block
	                        // Reset chunk state to parse new chunk header at target position
	                        chunk_id <= 32'd0;
	                        chunk_hdr_pos <= 3'd0;
	                        chunk_size_acc <= 32'd0;
	                        chunk_left <= 32'd0;
	                        chunk_index <= 32'd0;
	                        $display("WOZ_SCAN: Skip - setting sd_lba to %0d (target %0d), discarding rest of current block",
	                                 scan_skip_target - 16'd1, scan_skip_target);
	                    end
	                    // Only count block completion if we had an active transfer (normal parsing)
	                    else if (!scan_skip_active && old_ack && !sd_ack && transfer_active) begin
	                        scan_blocks <= scan_blocks + 1'd1;
	                        scan_skip_discard <= 1'b0;  // Clear discard flag - new block starts fresh
	                        if (parser_done) begin
	                            woz_valid <= 1'b1;
	                            busy <= 0;
	                            state <= S_IDLE;
	                            $display("WOZ_CTRL: Parsed INFO/TMAP/TRKS%s (ver=%0d type=%0d timing=%0d flux_block=%0d), entering IDLE",
	                                     have_flux ? "/FLUX" : "     ", info_version, info_disk_type, info_bit_timing, info_flux_block);
	                            if ((IS_35_INCH && info_disk_type == 8'd1) || (!IS_35_INCH && info_disk_type == 8'd2))
	                                $display("WOZ_CTRL: WARNING: disk type mismatch! IS_35_INCH=%0d but WOZ disk_type=%0d (1=5.25\", 2=3.5\")",
	                                         IS_35_INCH, info_disk_type);
	                            pending_track_id <= track_id;
	                            load_side <= track_id[0];
	                        end else if (scan_blocks >= SCAN_BLOCK_LIMIT) begin
	                            woz_valid <= 1'b0;
	                            busy <= 0;
	                            state <= S_INIT;
	                            scan_failed <= 1'b1;
	                            $display("WOZ_CTRL: ERROR: WOZ scan limit reached without required chunks (INFO=%0d TMAP=%0d TRKS=%0d FLUX=%0d need_flux=%0d)",
	                                     have_info, have_tmap, have_trks, have_flux, need_flux);
	                        end else begin
	                            sd_lba <= sd_lba + 1'd1;
	                        end
	                    end
	                end
                
                S_IDLE: begin
                    busy <= 0;

                    // Dirty flush timer: after IWM writes stop for ~500ms, flush to disk.
                    // This handles the case where the ROM writes volume structures to track 0
                    // then reads them back without changing tracks or stopping the motor.
                    // Without this, the dirty BRAM data is never saved to the WOZ file.
                    if (bit_we)
                        dirty_flush_timer <= DIRTY_FLUSH_DELAY;
                    else if (dirty_flush_timer > 0)
                        dirty_flush_timer <= dirty_flush_timer - 1'd1;

                    // Dirty flush trigger: timer expired with dirty data
                    if (dirty_flush_timer == 1 && (dirty_side0 || dirty_side1) && woz_valid) begin
                        state <= S_SAVE_TRACK;
                        busy <= 1;
                        blocks_processed <= 0;
                        old_ack <= sd_ack;
                        transfer_active <= 1'b0;
                        request_issued <= 1'b0;
                        if (dirty_side0) begin
                            save_side <= 1'b0;
                            saving_second_side <= (IS_35_INCH != 0) & dirty_side1;
                            sd_lba <= {16'b0, trk_start_block_side0};
                            trk_block_count <= trk_block_count_side0;
                        end else begin
                            save_side <= 1'b1;
                            saving_second_side <= 1'b0;
                            sd_lba <= {16'b0, trk_start_block_side1};
                            trk_block_count <= trk_block_count_side1;
                        end
                        sd_wr <= 1;
                        save_is_flush <= 1'b1;
`ifdef DEBUG_VERBOSE
                        $display("WOZ_CTRL: Dirty timer flush (s0=%0d s1=%0d) start_blk=%0d",
                                 dirty_side0, dirty_side1,
                                 dirty_side0 ? trk_start_block_side0 : trk_start_block_side1);
`endif
                    end

                    // Motor-off save trigger: flush dirty tracks when motor spins down
                    prev_active <= active;
                    if (prev_active && !active && (dirty_side0 || dirty_side1) && woz_valid) begin
                        state <= S_SAVE_TRACK;
                        busy <= 1;
                        blocks_processed <= 0;
                        old_ack <= sd_ack;
                        transfer_active <= 1'b0;
                        request_issued <= 1'b0;
                        if (dirty_side0) begin
                            save_side <= 1'b0;
                            saving_second_side <= (IS_35_INCH != 0) & dirty_side1;
                            sd_lba <= {16'b0, trk_start_block_side0};
                            trk_block_count <= trk_block_count_side0;
                        end else begin
                            save_side <= 1'b1;
                            saving_second_side <= 1'b0;
                            sd_lba <= {16'b0, trk_start_block_side1};
                            trk_block_count <= trk_block_count_side1;
                        end
                        sd_wr <= 1;
                        save_is_flush <= 1'b1;
                        $display("WOZ_CTRL: Motor off, flushing dirty tracks (s0=%0d s1=%0d)",
                                 dirty_side0, dirty_side1);
                    end

                    // Settling time: track how long PHYSICAL track has been stable
                    // Use track_id[7:1] for 3.5" (physical track without side bit)
                    // SEL toggles (side bit) should NOT reset settling
                    if (track_id[7:1] != last_physical_track) begin
                        // Physical track changed - reset settle counter
                        last_physical_track <= track_id[7:1];
                        settle_counter <= 20'd0;
                        // Debug: show track change detected
                        if (settle_counter > 20'd100) begin
                            $display("WOZ_SETTLE: Physical track changed %0d -> %0d, resetting settle counter",
                                     last_physical_track, track_id[7:1]);
                        end
                    end else if (settle_counter < settle_lim) begin
                        // Physical track stable but not yet settled
                        settle_counter <= settle_counter + 1'd1;
                    end

                    // Check for Track Change - only proceed if settled
                    if (IS_35_INCH) begin
                        // 3.5" DUAL-SIDE LOADING:
                        // When physical track changes (track_id[7:1]), load BOTH sides.
                        // When only side bit changes (SEL toggle), use cached data - no load.
                        // This prevents thrashing when ROM polls status via SEL toggles.

                        reg [6:0] requested_physical;
                        reg [6:0] cached_physical_s0;
                        reg [6:0] cached_physical_s1;
                        reg       side0_cached;
                        reg       side1_cached;
                        reg       both_sides_cached;

                        requested_physical = track_id[7:1];
                        cached_physical_s0 = current_track_id_side0[7:1];
                        cached_physical_s1 = current_track_id_side1[7:1];

                        // Track-side cache validity
                        side0_cached = (current_track_id_side0 == {requested_physical, 1'b0});
                        side1_cached = (current_track_id_side1 == {requested_physical, 1'b1});
                        both_sides_cached = side0_cached && side1_cached;

                        // Only start loading if track is not cached AND head has settled
                        // This prevents thrashing during fast seeks (boot)
                        if (!both_sides_cached && (settle_counter >= SETTLE_THRESHOLD)) begin
                            $display("WOZ_SETTLE: Settled after %0d cycles, starting load for physical track %0d",
                                     settle_counter, requested_physical);
                            // Physical track change - need to load both sides
                            target_physical_track <= requested_physical;
                            loading_second_side <= 1'b0;
                            // If the requested side is already cached, load the other side first.
                            // This avoids overwriting the active side while the ROM is reading it.
                            if (side0_cached && !side1_cached) begin
                                pending_track_id <= {requested_physical, 1'b1};
                                load_side <= 1'b1;
                            end else if (side1_cached && !side0_cached) begin
                                pending_track_id <= {requested_physical, 1'b0};
                                load_side <= 1'b0;
                            end else begin
                                // Neither side cached: start with the requested side
                                pending_track_id <= track_id;
                                load_side <= track_id[0];
                            end
                            $display("WOZ_CTRL: Physical track change: %0d -> %0d (loading both sides)",
                                     cached_physical_s0, requested_physical);

                            // If any side is dirty, save before seeking
                            if ((dirty_side0 || dirty_side1) && woz_valid) begin
                                state <= S_SAVE_TRACK;
                                busy <= 1;
                                blocks_processed <= 0;
                                old_ack <= sd_ack;  // Prevent spurious falling edge detection
                                // Save side 0 first if dirty, else side 1
                                if (dirty_side0) begin
                                    save_side <= 1'b0;
                                    saving_second_side <= dirty_side1;  // Also save side 1 after
                                    sd_lba <= {16'b0, trk_start_block_side0};
                                    trk_block_count <= trk_block_count_side0;
                                end else begin
                                    save_side <= 1'b1;
                                    saving_second_side <= 1'b0;
                                    sd_lba <= {16'b0, trk_start_block_side1};
                                    trk_block_count <= trk_block_count_side1;
                                end
                                sd_wr <= 1;
                                save_is_flush <= 1'b0;
                                $display("WOZ_CTRL: Track dirty (s0=%0d s1=%0d), saving before seek start_blk=%0d blk_cnt=%0d",
                                         dirty_side0, dirty_side1,
                                         dirty_side0 ? trk_start_block_side0 : trk_start_block_side1,
                                         dirty_side0 ? trk_block_count_side0 : trk_block_count_side1);
                            end else begin
                                state <= S_SEEK_LOOKUP;
                                busy <= 1;
                                blocks_processed <= 0;
                            end
                        end
                        // else: both sides cached, SEL toggle just uses mux - no action needed
                    end else begin
                        // 5.25" SINGLE-SIDED:
                        // Only one side, simpler logic. Also use settling time.
                        if ((track_id != current_track_id_side0) && (settle_counter >= settle_lim)) begin
                            $display("WOZ_SETTLE: 5.25\" settled after %0d cycles, starting load for track %0d",
                                     settle_counter, track_id);
                            pending_track_id <= track_id;
                            load_side <= 1'b0;
                            loading_second_side <= 1'b0;  // Not used for 5.25" but keep clean
                            $display("WOZ_CTRL: Seek request: %0d -> %0d", current_track_id_side0, track_id);

                            // If dirty, save first (5.25" is single-sided, only side 0)
                            if (dirty_side0 && woz_valid) begin
                                state <= S_SAVE_TRACK;
                                busy <= 1;
                                save_side <= 1'b0;
                                saving_second_side <= 1'b0;
                                sd_lba <= {16'b0, trk_start_block_side0};
                                trk_block_count <= trk_block_count_side0;
                                blocks_processed <= 0;
                                old_ack <= sd_ack;  // Prevent spurious falling edge detection
                                sd_wr <= 1;
                                save_is_flush <= 1'b0;
                                $display("WOZ_CTRL: Track %0d is dirty, saving before seek", current_track_id_side0);
                            end else begin
                                state <= S_SEEK_LOOKUP;
                                busy <= 1;
                                blocks_processed <= 0;
                            end
                        end
                    end
                end
                
                // Lookup FLUX (if available) then TMAP, then TRKS
	                S_SEEK_LOOKUP: begin
	                    case (blocks_processed)
	                        // Step 0: Start lookup - check FLUX first if available
	                        0: begin
	                             pending_is_flux <= 1'b0;  // Default to bitstream
	                             if (have_flux && info_version >= 8'd3) begin
	                                 // WOZ v3 with FLUX chunk - check FLUX map first
	                                 meta_read_addr <= META_FLUX_BASE + {3'b0, pending_track_id};
	                                 blocks_processed <= 1;
	                                 $display("WOZ_CTRL: Checking FLUX[%0d] (have_flux=%0d ver=%0d)",
	                                          pending_track_id, have_flux, info_version);
	                             end else begin
	                                 // No FLUX support - go directly to TMAP
	                                 meta_read_addr <= META_TMAP_BASE + {3'b0, pending_track_id};
	                                 blocks_processed <= 21;  // Skip to TMAP check
	                             end
	                        end
	                        // Step 1: Wait for FLUX RAM read
                        1: begin
                             blocks_processed <= 2;
                        end
                        // Step 2: Check FLUX result
                        2: begin
                             reg [7:0] flux_index;
                             flux_index = meta_read_data;

                             if (flux_index != 8'hFF) begin
                                 // FLUX data available for this track!
                                 pending_is_flux <= 1'b1;
                                 $display("WOZ_CTRL: Track %0d has FLUX data at TRKS entry %0d", pending_track_id, flux_index);
                                 // Read TRKS entry for flux data (same structure as bitstream)
                                 meta_read_addr <= META_TRKS_BASE + {flux_index, 3'b000};
                                 blocks_processed <= 3;  // Continue to TRKS lookup
                             end else begin
                                 // No FLUX data - fall back to TMAP
                                 $display("WOZ_CTRL: No FLUX for track %0d (0xFF), checking TMAP", pending_track_id);
                                 meta_read_addr <= META_TMAP_BASE + {3'b0, pending_track_id};
                                 blocks_processed <= 21;  // Go to TMAP check
                             end
                        end
                        // Steps 21-22: TMAP check (fallback from FLUX or direct for non-v3)
                        21: begin // Wait for TMAP RAM read
                             blocks_processed <= 22;
                        end
                        22: begin
                             // meta_read_data is TMAP[id]
                             reg [7:0] trks_index;
                             trks_index = meta_read_data;
                             pending_is_flux <= 1'b0;  // TMAP = bitstream

                             if (trks_index == 8'hFF) begin
                                 $display("WOZ_CTRL: Track %0d is empty (FF in TMAP)", pending_track_id);
                                 trk_block_count <= 0;
                                 trk_bit_count <= 0;
                                 // Store empty track info to appropriate side
                                 // Also invalidate this side's block pointers. They are
                                 // only assigned on the successful-load path, so leaving
                                 // them alone here keeps them aimed at the PREVIOUS track:
                                 // a later write to this unmapped track would set dirty and
                                 // flush BRAM over that track's blocks, corrupting the image.
                                 if (IS_35_INCH && pending_track_id[0]) begin
                                     current_track_id_side1 <= pending_track_id;
                                     bit_count_side1 <= 32'd0;
                                     is_flux_side1 <= 1'b0;
                                     flux_size_side1 <= 32'd0;
                                     flux_total_ticks_side1 <= 32'd0;
                                     trk_start_block_side1 <= 16'd0;
                                     trk_block_count_side1 <= 16'd0;
                                 end else begin
                                     current_track_id_side0 <= pending_track_id;
                                     bit_count_side0 <= 32'd0;
                                     is_flux_side0 <= 1'b0;
                                     flux_size_side0 <= 32'd0;
                                     flux_total_ticks_side0 <= 32'd0;
                                     trk_start_block_side0 <= 16'd0;
                                     trk_block_count_side0 <= 16'd0;
                                 end
                                 // Clear dirty for the side being loaded (empty track replaces it)
                                 if (IS_35_INCH && pending_track_id[0])
                                     dirty_side1 <= 0;
                                 else
                                     dirty_side0 <= 0;

                                 // 3.5" DUAL-SIDE: Even for empty tracks, need to check/load side 1
                                 if (IS_35_INCH && !loading_second_side) begin
                                     // First check if physical track changed
                                     if (track_id[7:1] != target_physical_track) begin
                                         // Physical track changed - go to IDLE for settling
                                         state <= S_IDLE;
                                         busy <= 0;
                                         settle_counter <= 20'd0;
                                         $display("WOZ_CTRL: Physical track moved during empty track: %0d -> %0d, waiting for settle",
                                                  target_physical_track, track_id[7:1]);
                                     end else begin
                                         loading_second_side <= 1'b1;
                                         pending_track_id <= {target_physical_track, 1'b1};
                                         load_side <= 1'b1;
                                         blocks_processed <= 0;
                                         $display("WOZ_CTRL: Side 0 empty, checking side 1 for physical track %0d",
                                                  target_physical_track);
                                     end
                                     // Stay in S_SEEK_LOOKUP, will restart from step 0
                                 end else begin
                                     state <= S_IDLE;
                                     busy <= 0;
                                     loading_second_side <= 1'b0;
                                 end
	                             end else if (is_woz_v1) begin
	                                 // WOZ v1: compute track parameters directly from file position.
	                                 // Each v1 TRKS entry is 6656 bytes = 13 × 512 blocks.
	                                 // Entry N starts at: trks_base_block + N * 13 (+ trks_byte_offset within block)
	                                 $display("WOZ_CTRL: V1 Track %0d maps to TRKS entry %0d", pending_track_id, trks_index);
	                                 trk_start_block <= trks_base_block
	                                     + ({8'd0, trks_index} << 3)
	                                     + ({8'd0, trks_index} << 2)
	                                     + {8'd0, trks_index};  // trks_index * 13
	                                 trk_block_count <= (trks_byte_offset != 9'd0) ? 16'd14 : 16'd13;
	                                 trk_bit_count <= 32'd51200;  // Placeholder; real value captured during DMA
	                                 v1_bit_count <= 16'd0;
	                                 blocks_processed <= 19;  // Skip to "done reading" step
	                             end else begin
	                                 $display("WOZ_CTRL: Track %0d maps to TRKS entry %0d (bitstream)", pending_track_id, trks_index);
	                                 // Start reading TRK entry (StartBlock, BlockCount, BitCount)
	                                 meta_read_addr <= META_TRKS_BASE + {trks_index, 3'b000}; // Byte 0
	                                 blocks_processed <= 3;
	                             end
	                        end
                        3: begin // Wait for TRK entry read (StartBlock LSB)
                             blocks_processed <= 4;
                        end
                        4: begin
                             trk_start_block[7:0] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1'd1; // -> Byte 1
                             blocks_processed <= 5;
                        end
                        5: begin // Wait for Byte 1
                             blocks_processed <= 6;
                        end
                        6: begin
                             trk_start_block[15:8] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1'd1; // -> Byte 2
                             blocks_processed <= 7;
                        end
                        7: begin // Wait for Byte 2
                             blocks_processed <= 8;
                        end
                        8: begin
                             trk_block_count[7:0] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1'd1; // -> Byte 3
                             blocks_processed <= 9;
                        end
                        9: begin // Wait for Byte 3
                             blocks_processed <= 10;
                        end
                        10: begin
                             trk_block_count[15:8] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1'd1; // -> Byte 4
                             blocks_processed <= 11;
                        end
                        11: begin // Wait for Byte 4
                             blocks_processed <= 12;
                        end
                        12: begin
                             trk_bit_count[7:0] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1'd1; // -> Byte 5
                             blocks_processed <= 13;
                        end
                        13: begin // Wait for Byte 5
                             blocks_processed <= 14;
                        end
                        14: begin
                             trk_bit_count[15:8] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1'd1; // -> Byte 6
                             blocks_processed <= 15;
                        end
                        15: begin // Wait for Byte 6
                             blocks_processed <= 16;
                        end
                        16: begin
                             trk_bit_count[23:16] <= meta_read_data;
                             meta_read_addr <= meta_read_addr + 1'd1; // -> Byte 7
                             blocks_processed <= 17;
                        end
                        17: begin // Wait for Byte 7
                             blocks_processed <= 18;
                        end
                        18: begin
                             trk_bit_count[31:24] <= meta_read_data;
                             
                             // Done reading
                             blocks_processed <= 19;
                        end
                        19: begin
                             // Set flux track info based on pending_is_flux
                             // For flux tracks: trk_bit_count contains flux data size in BYTES
                             // For flux tracks: trk_bit_count contains flux data size in BYTES
                             // For bitstream tracks: trk_bit_count contains bit count
                             // pending_is_flux is already set; per-side flags will be set on load completion
                             if (pending_is_flux) begin
                                 $display("WOZ_CTRL: FLUX Track Info: StartBlock=%0d BlockCount=%0d FluxBytes=%0d",
                                          trk_start_block, trk_block_count, trk_bit_count);
                             end else begin
                                 $display("WOZ_CTRL: Track Info: StartBlock=%0d BlockCount=%0d BitCount=%0d",
                                          trk_start_block, trk_block_count, trk_bit_count);
                             end
                             // Start Loading Track
                             state <= S_READ_TRACK;
                             sd_lba <= {16'b0, trk_start_block};
                             blocks_processed <= 0; // Reset for block counting
                             old_ack <= sd_ack;  // Prevent spurious falling edge detection on state entry
                             transfer_active <= 1'b0;  // Clear stale transfer_active from previous track load
                             track_load_side <= load_side; // Latch side before DMA begins
                             pending_flux_total_ticks <= 32'd0;
                             $display("WOZ_TRACK_ENTER: track=%0d sd_ack=%0d sd_rd will be %0d old_ack will be %0d lba=%0d",
                                      pending_track_id, sd_ack, !sd_ack, sd_ack, trk_start_block);
                             if (!sd_ack) sd_rd <= 1'b1;
                        end
                    endcase
                end
                
                S_READ_TRACK: begin
                    // IMPORTANT: Do NOT abort track loads when physical track changes!
                    // During fast seeks (boot-time seeking from track 0 to ~45), the ROM
                    // steps rapidly through intermediate tracks. If we abort and restart
                    // on each step, we never complete any load and the boot hangs.
                    //
                    // Instead, continue loading the current track. When the load completes
                    // (in S_IDLE), we'll see the new track_id and start loading it.
                    // The ROM doesn't expect valid data while stepping anyway - it only
                    // reads after settle time. bit_count returning 0 for non-cached tracks
                    // is fine during the seek phase.
                    //
                    // Detect physical track changes during load and abort to settling
                    // This prevents wasting time loading the wrong track during fast seeks
                    if (IS_35_INCH && (track_id[7:1] != target_physical_track)) begin
                        $display("WOZ_CTRL: Physical track change during load (%0d -> %0d), aborting to settle",
                                 target_physical_track, track_id[7:1]);
                        state <= S_IDLE;
                        busy <= 0;
                        settle_counter <= 20'd0;
                        sd_rd <= 1'b0;
                        transfer_active <= 1'b0;
                        request_issued <= 1'b0;
                    end
                    // If only the side bit changes while loading the same physical track:
                    // ONLY restart if the requested side is NOT already cached.
                    // The ROM frequently toggles SEL to read status; if the requested side
                    // is already cached, just continue loading the other side.
                    // This prevents thrashing where side changes cause endless restarts.
                    if (IS_35_INCH && (track_id[7:1] == target_physical_track) && (track_id != pending_track_id)) begin
                        // Check if the requested side is already cached
                        reg requested_side_cached;
                        requested_side_cached = (track_id[0] == 1'b0) ? (current_track_id_side0 == track_id)
                                                                      : (current_track_id_side1 == track_id);
                        if (!requested_side_cached) begin
                            $display("WOZ_CTRL: Side change during load (pending=%0d -> req=%0d), restarting load",
                                     pending_track_id, track_id);
                            pending_track_id <= track_id;
                            load_side <= track_id[0];
                            loading_second_side <= 1'b0;
                            state <= S_SEEK_LOOKUP;
                            busy <= 1'b1;
                            sd_rd <= 1'b0;
                            blocks_processed <= 0;
                            old_ack <= sd_ack;
                            transfer_active <= 1'b0;
                            request_issued <= 1'b0;
                        end
                        // else: requested side is cached, continue loading the other side
                    end

                    // Assert sd_rd while waiting for ack, but NOT when completing a transfer
                    if (!sd_ack && !(old_ack && transfer_active)) begin
                        sd_rd <= 1'b1;
                    end
                    // Only count block completion if we had an active transfer
                    // This prevents spurious falling edge detection on state entry
                    if (old_ack && !sd_ack && transfer_active) begin
                        // Block complete
                        // $display("WOZ_DMA: Block %0d complete for track %0d (lba=%0d)",
                        //          blocks_processed, pending_track_id, sd_lba);
                        blocks_processed <= blocks_processed + 1'd1;
                        if (blocks_processed + 1 >= trk_block_count) begin
                            // Track load complete - store to appropriate RAM
                            $display("WOZ_CTRL: Track %0d load complete (%0d blocks)", pending_track_id, blocks_processed + 1);

                            if (IS_35_INCH && pending_track_id[0]) begin
                                current_track_id_side1 <= pending_track_id;
                                bit_count_side1 <= is_woz_v1 ? {16'd0, v1_bit_count} : trk_bit_count;
                                is_flux_side1 <= pending_is_flux;
                                flux_size_side1 <= pending_is_flux ? trk_bit_count : 32'd0;
                                flux_total_ticks_side1 <= pending_is_flux ? pending_flux_total_ticks : 32'd0;
                                // Store per-side track location for save-back
                                trk_start_block_side1 <= trk_start_block;
                                trk_block_count_side1 <= trk_block_count;
                                $display("WOZ_CTRL: Stored track %0d to side1 RAM, %s=%0d is_flux=%0d",
                                         pending_track_id, pending_is_flux ? "flux_bytes" : "bit_count",
                                         is_woz_v1 ? {16'd0, v1_bit_count} : trk_bit_count, pending_is_flux);
                            end else begin
                                current_track_id_side0 <= pending_track_id;
                                bit_count_side0 <= is_woz_v1 ? {16'd0, v1_bit_count} : trk_bit_count;
                                is_flux_side0 <= pending_is_flux;
                                flux_size_side0 <= pending_is_flux ? trk_bit_count : 32'd0;
                                flux_total_ticks_side0 <= pending_is_flux ? pending_flux_total_ticks : 32'd0;
                                // Store per-side track location for save-back
                                trk_start_block_side0 <= trk_start_block;
                                trk_block_count_side0 <= trk_block_count;
                                $display("WOZ_CTRL: Stored track %0d to side0 RAM, %s=%0d is_flux=%0d%s",
                                         pending_track_id, pending_is_flux ? "flux_bytes" : "bit_count",
                                         is_woz_v1 ? {16'd0, v1_bit_count} : trk_bit_count, pending_is_flux,
                                         is_woz_v1 ? " (v1)" : "     ");
                            end
                            if (pending_is_flux) begin
                                $display("WOZ_CTRL: Flux ticks sum=%0d", pending_flux_total_ticks);
                            end

                            // 3.5" DUAL-SIDE: After first side, check if track changed, then load other side
                            if (IS_35_INCH && !loading_second_side) begin
                                // First check if physical track changed during first side load
                                if (track_id[7:1] != target_physical_track) begin
                                    // Physical track changed - go to IDLE to let settling logic decide
                                    // This prevents thrashing during fast seeks
                                    state <= S_IDLE;
                                    busy <= 0;
                                    settle_counter <= 20'd0;  // Reset settle counter for new track
                                    $display("WOZ_CTRL: Physical track moved during first side: %0d -> %0d, waiting for settle",
                                             target_physical_track, track_id[7:1]);
                                end else begin
                                    // First side done for correct track, now load the opposite side
                                    loading_second_side <= 1'b1;
                                    pending_track_id <= {target_physical_track, ~pending_track_id[0]};
                                    load_side <= ~pending_track_id[0];
                                    state <= S_SEEK_LOOKUP;
                                    blocks_processed <= 0;
                                    $display("WOZ_CTRL: First side complete, starting other side load for physical track %0d",
                                             target_physical_track);
                                end
                            end else begin
                                // 5.25" single-sided OR 3.5" side 1 complete
                                loading_second_side <= 1'b0;
                                track_load_complete <= 1'b1;  // Pulse to signal flux_drive to reset position
                                $display("WOZ_CTRL: LOAD_SUM track %0d sum=%04x bytes=%0d blocks=%0d",
                                         pending_track_id, dbg_load_sum, dbg_load_bytes, dbg_load_blocks);

                                // Check if physical track changed during load
                                // This can happen if the drive head stepped while we were loading
                                if (IS_35_INCH && (track_id[7:1] != target_physical_track)) begin
                                    // Physical track changed during load - go to IDLE for settling
                                    // This prevents thrashing during fast seeks
                                    state <= S_IDLE;
                                    busy <= 0;
                                    settle_counter <= 20'd0;  // Reset settle counter for new track
                                    $display("WOZ_CTRL: Physical track moved during load: %0d -> %0d, waiting for settle",
                                             target_physical_track, track_id[7:1]);
                                end else begin
                                    // No change, normal completion
                                    state <= S_IDLE;
                                    busy <= 0;
                                    if (IS_35_INCH) begin
                                        $display("WOZ_CTRL: Both sides loaded for physical track %0d", target_physical_track);
                                    end else begin
                                        $display("WOZ_CTRL: Track %0d loaded (5.25\")", pending_track_id);
                                    end
                                end
                            end
                            // Clear dirty for the side just loaded (fresh data from disk)
                            if (IS_35_INCH && pending_track_id[0])
                                dirty_side1 <= 0;
                            else
                                dirty_side0 <= 0;
                        end else begin
                            // Next block
                            sd_lba <= sd_lba + 1'd1;
                        end
                    end
                end

                S_SAVE_TRACK: begin
`ifdef DEBUG_VERBOSE
                    // Debug: log first few bytes of each save block
                    if (sd_ack && sd_buff_addr < 9'd8 && IS_35_INCH) begin
                        $display("WOZ_SAVE_DBG[%0d]: blk=%0d addr=%0d bram_a=%04X dout0=%02X dout1=%02X save_side=%0d save_din=%02X sd_buff_din=%02X",
                                 IS_35_INCH, blocks_processed, sd_buff_addr,
                                 bram_addr_a, track_ram_dout0, track_ram_dout1,
                                 save_side, save_din, sd_buff_din);
                    end
`endif
                    // Assert sd_wr while waiting for ack, but NOT when completing a transfer
                    if (!sd_ack && !(old_ack && transfer_active)) begin
                        sd_wr <= 1'b1;
                    end
                    // Only count block completion if we had an active transfer
                    if (old_ack && !sd_ack && transfer_active) begin
                        // Block saved
                        blocks_processed <= blocks_processed + 1'd1;
                        if (blocks_processed + 1 >= trk_block_count) begin
                            // Done saving this side
                            if (save_side)
                                dirty_side1 <= 0;
                            else
                                dirty_side0 <= 0;

                            // Check if other side also needs saving
                            if (saving_second_side) begin
                                saving_second_side <= 1'b0;
                                save_side <= 1'b1;  // Second save is always side 1
                                sd_lba <= {16'b0, trk_start_block_side1};
                                trk_block_count <= trk_block_count_side1;
                                blocks_processed <= 0;
                                old_ack <= sd_ack;
                                transfer_active <= 1'b0;
                                request_issued <= 1'b0;
                                sd_wr <= 1;
                                $display("WOZ_CTRL: Side 0 saved, now saving side 1");
                            end else begin
                                // All dirty sides saved
                                if (save_is_flush) begin
                                    // Motor-off flush: return to idle (no pending seek)
                                    state <= S_IDLE;
                                    busy <= 0;
                                    save_is_flush <= 1'b0;
                                    $display("WOZ_CTRL: Motor-off flush complete");
                                end else begin
                                    // Save before seek: proceed to load new track
                                    state <= S_SEEK_LOOKUP;
                                    blocks_processed <= 0;
                                end
                            end
                        end else begin
                            // Next block
                            sd_lba <= sd_lba + 1'd1;
                        end
                    end
                end
                
            endcase
            
            // Data Loading/Saving DMA
            // This runs in parallel with state machine waiting for sd_ack
	            if (state == S_SEEK_LOOKUP) begin
	                dbg_load_sum    <= 16'd0;   // new track load starting
	                dbg_load_bytes  <= 14'd0;
	                dbg_load_blocks <= 8'd0;
	            end
	            if (sd_ack && sd_buff_wr && state == S_READ_TRACK &&
	                (transfer_active || (!old_ack && sd_ack))) begin
	                dbg_load_sum   <= dbg_load_sum + {8'd0, sd_buff_dout};
	                dbg_load_bytes <= dbg_load_bytes + 14'd1;
	            end
	            if (old_ack && !sd_ack && state == S_READ_TRACK) begin
	                dbg_load_blocks <= dbg_load_blocks + 8'd1;
	            end
	            if (sd_ack) begin
	                if (sd_buff_wr) begin // Reading from SD -> RAM
	                     // Gate on transfer_active (like the S_READ_TRACK BRAM path):
	                     // the real HPS sometimes re-serves the same LBA unsolicited
	                     // (measured on HW: dup ack with unchanged sd_lba). Without
	                     // this gate the streaming parser consumes those bytes twice
	                     // and mis-parses the WOZ chunks.
	                     if (state == S_SCAN_WOZ && !scan_skip_discard &&
	                         (transfer_active || (!old_ack && sd_ack))) begin
	                         // Streaming parser: process file bytes sequentially.
	                         // Skip processing if scan_skip_discard is set (discarding current block)
	                         reg [7:0] b;
	                         b = sd_buff_dout;

	                         if (hdr_pos < 4'd12) begin
	                             // Header format:
	                             // 0..3  = "WOZ1"/"WOZ2"
	                             // 4..7  = 0xFF 0x0A 0x0D 0x0A
	                             // 8..11 = CRC32 (ignored)
	                             // 12..15 = reserved (ignored)
	                             hdr_pos <= hdr_pos + 1'd1;
	                         end else begin
	                             // Parse chunks: [id:4][size:4][data:size]
	                             if (chunk_left == 32'd0) begin
	                                 // Chunk header
	                                 if (chunk_hdr_pos < 3'd4) begin
	                                     chunk_id <= {chunk_id[23:0], b};
	                                     chunk_hdr_pos <= chunk_hdr_pos + 1'd1;
	                                 end else begin
	                                     // size is little-endian
	                                     chunk_size_acc <= chunk_size_acc | ({{24{1'b0}}, b} << ((chunk_hdr_pos - 3'd4) * 8));
	                                     chunk_hdr_pos <= chunk_hdr_pos + 1'd1;
	                                     if (chunk_hdr_pos == 3'd7) begin
	                                         chunk_left <= chunk_size_acc | ({{24{1'b0}}, b} << 24);
	                                         chunk_index <= 32'd0;
	                                         chunk_hdr_pos <= 3'd0;
	                                         chunk_size_acc <= 32'd0;
	                                         // Debug: show chunk being parsed
	                                         $display("WOZ_CHUNK: Parsing '%c%c%c%c' size=%0d",
	                                                  chunk_id[31:24], chunk_id[23:16], chunk_id[15:8], chunk_id[7:0],
	                                                  chunk_size_acc | ({{24{1'b0}}, b} << 24));
	                                     end
	                                 end
	                             end else begin
	                                 // Chunk data
	                                 if (chunk_id == "INFO") begin
	                                     if (chunk_index == 32'd0) begin
	                                         info_version <= b;
	                                         have_info <= 1'b1;
	                                         is_woz_v1 <= (b == 8'd1);
	                                     end
	                                     if (chunk_index == 32'd1) info_disk_type <= b;
	                                     // WOZ2: bit_timing byte is at offset 39 within INFO chunk:
	                                     // ver(0), disk_type(1), wp(2), sync(3), cleaned(4), creator(5..36),
	                                     // sides(37), boot_type(38), bit_timing(39)
	                                     if (chunk_index == 32'd2)  info_wp <= b;
	                                     if (chunk_index == 32'd39) info_bit_timing <= b;
	                                     // WOZ3: flux_block at offset 46-47 (little-endian uint16)
	                                     // Starting block number for flux data in TRKS chunk
	                                     if (chunk_index == 32'd46) info_flux_block[7:0] <= b;
	                                     if (chunk_index == 32'd47) begin
	                                         info_flux_block[15:8] <= b;
	                                         $display("WOZ_SCAN: INFO v%0d flux_block=%0d", info_version, {b, info_flux_block[7:0]});
	                                     end
	                                 end else if (chunk_id == "FLUX") begin
	                                     // FLUX chunk: 160-byte map (same as TMAP)
	                                     // Maps track_id to flux TRKS entry index, 0xFF = no flux data
	                                     if (chunk_index < 32'd160) begin
	                                         meta_addr <= META_FLUX_BASE + chunk_index[10:0];
	                                         meta_din <= b;
	                                         meta_we <= 1'b1;
	                                         if (chunk_index < 5 || chunk_index == 80) begin
	                                             $display("FLUX_SCAN: FLUX[%0d] = %0d (0x%02X)", chunk_index, b, b);
	                                         end
	                                         if (chunk_index == 32'd159) begin
	                                             have_flux <= 1'b1;
	                                             $display("WOZ_SCAN: FLUX chunk parsed (160 bytes)");
	                                         end
	                                     end
	                                 end else if (chunk_id == "TMAP") begin
	                                     if (chunk_index < 32'd160) begin
	                                         meta_addr <= META_TMAP_BASE + chunk_index[10:0];
	                                         meta_din <= b;
	                                         meta_we <= 1'b1;
	                                         // Debug: show first few TMAP entries and entry 80
	                                         if (chunk_index < 5 || chunk_index == 80) begin
	                                             $display("TMAP_SCAN: TMAP[%0d] = %0d (0x%02X)", chunk_index, b, b);
	                                         end
	                                         if (chunk_index == 32'd159) have_tmap <= 1'b1;
	                                     end
	                                 end else if (chunk_id == "TRKS") begin
	                                     if (is_woz_v1) begin
	                                         // WOZ v1: TRKS contains raw track data inline (35 × 6656 bytes).
	                                         // Record the file position and mark done immediately.
	                                         // We compute track locations arithmetically in S_SEEK_LOOKUP.
	                                         if (chunk_index == 32'd0) begin
	                                             trks_base_block <= scan_blocks;
	                                             trks_byte_offset <= sd_buff_addr[8:0];
	                                             have_trks <= 1'b1;
	                                             $display("WOZ_CTRL: V1 TRKS data at file block %0d offset %0d (size=%0d)",
	                                                      scan_blocks, sd_buff_addr, chunk_left);
	                                         end
	                                         // Don't store v1 track data as metadata
	                                     end else begin
	                                         // WOZ v2+: First 1280 bytes are 160 × 8-byte metadata entries
	                                         if (chunk_index < 32'd1280) begin
	                                             meta_addr <= META_TRKS_BASE + chunk_index[10:0];
	                                             meta_din <= b;
	                                             meta_we <= 1'b1;
	                                             if (chunk_index == 32'd1279) have_trks <= 1'b1;
	                                         end
	                                     end
	                                 end

	                                 chunk_index <= chunk_index + 1'd1;
	                                 chunk_left <= chunk_left - 1'd1;

	                                 // TRKS SKIP OPTIMIZATION: After parsing first 1280 bytes of TRKS metadata,
	                                 // skip the rest of the chunk (track data) if we need FLUX.
	                                 // WOZ file layout: Header(12) + INFO(68) + TMAP(168) + TRKS(8+data) + FLUX
	                                 // FLUX position = 256 + TRKS_data_size
	                                 // We're at chunk_index=1280, chunk_left = TRKS_size - 1280
	                                 // FLUX block = (256 + chunk_left + 1280) / 512 = (1536 + chunk_left) / 512
	                                 //            ≈ 3 + chunk_left/512 (since 1536/512 = 3)
	                                 if (chunk_id == "TRKS" && chunk_index == 32'd1280 && chunk_left > 32'd512 && need_flux && !scan_skip_active) begin
	                                     scan_skip_target <= 16'd3 + chunk_left[24:9];
	                                     scan_skip_active <= 1'b1;
	                                     $display("WOZ_SCAN: TRKS skip - seeking to FLUX at block %0d (chunk_left=%0d)",
	                                              16'd3 + chunk_left[24:9], chunk_left);
	                                 end

	                                 if (chunk_left == 32'd1) begin
	                                     // End of chunk; next bytes start a new header.
	                                     chunk_id <= 32'd0;
	                                     chunk_hdr_pos <= 3'd0;
	                                     chunk_size_acc <= 32'd0;
	                                 end
	                             end
	                         end
                     end else if (state == S_READ_TRACK && (transfer_active || (!old_ack && sd_ack))) begin
                         if (is_woz_v1) begin
                             // WOZ v1: Track data starts at trks_byte_offset within the first block.
                             // Adjust BRAM write address so track data starts at BRAM[0].
                             // Also capture bit_count from track entry bytes 6648-6649.
                             reg [15:0] v1_raw_addr;
                             reg [15:0] v1_track_byte;
                             v1_raw_addr = {blocks_processed[6:0], sd_buff_addr};
                             v1_track_byte = v1_raw_addr - {7'd0, trks_byte_offset};

                             // Only write bytes that are part of the track entry (0..6655)
                             if (v1_raw_addr >= {7'd0, trks_byte_offset} &&
                                 v1_track_byte < 16'd6656) begin
                                 track_load_addr <= v1_track_byte;
                                 track_load_data <= sd_buff_dout;
                                 track_load_we <= 1;
                             end

                             // Capture bit count from v1 track entry (16-bit LE at bytes 6648-6649)
                             if (v1_raw_addr == ({7'd0, trks_byte_offset} + 16'd6648))
                                 v1_bit_count[7:0] <= sd_buff_dout;
                             if (v1_raw_addr == ({7'd0, trks_byte_offset} + 16'd6649))
                                 v1_bit_count[15:8] <= sd_buff_dout;
                         end else begin
                             // WOZ v2+: Direct BRAM mapping
                             track_load_addr <= {blocks_processed[6:0], sd_buff_addr};
                             track_load_data <= sd_buff_dout;
                             track_load_we <= 1;
                             if (pending_is_flux) begin
                                 pending_flux_total_ticks <= pending_flux_total_ticks + {24'd0, sd_buff_dout};
                             end
                         end
	                     end
	                end
	                // Writing RAM -> SD: handled combinationally via bram_addr_a and save_din
            end
        end
    end

endmodule
