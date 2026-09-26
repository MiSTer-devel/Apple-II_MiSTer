// Disk II controller with WOZ flux-level drives.
//
// Replaces disk_ii.vhd + drive_ii.vhd + floppy_track.sv. The soft switches,
// 1 s motor-off holdover and slot ROM are the Disk II card's; the drives are
// the IIgs core's flux_drive + woz_floppy_controller, unchanged; the data
// register is the Disk II logic state sequencer (P6) as validated on the IIgs
// branch against AppleWin, GSSquared/OpenEmulator and Appletini:
//
//   READ  (Q6=0,Q7=0)  QA=0: shift the bit cell's pulse in from the right.
//                      QA=1: hold the byte; the first pulse arms a restart,
//                            the next cell reloads {6'b0, 1, bit}. Nothing is
//                            cleared by a CPU read.
//   SENSE (Q6=1,Q7=0)  register fills with the write-protect state, pulses are
//                      discarded (LDA $C08D,X re-framing, WP check on $C08E).
//   WRITE (Q7=1)       a data-register write ($C08D/$C08F) loads the register
//                      and restarts the cell timer half a cell out; every cell
//                      then emits bit 7 to the drive and shifts a 0 in.
//
// Every disk image reaches this module as WOZ: Main_MiSTer converts .dsk/.do/
// .po/.nib in memory (support/a2/iigs_disk.cpp) and passes native .woz through.
// One bit cell is 56 clocks at 14.318 MHz (3.911 us) scaled by the WOZ
// "optimal bit timing" byte exactly as flux_drive does; both MUST agree.

module disk_ii_woz (
    input  wire        CLK_14M,
    input  wire        RESET,          // Apple RESET: switches + sequencer only
    input  wire        DD_RESET,       // cold / OSD reset: drives and track engines
    input  wire        PHASE_ZERO,     // PHI0 level, 1 MHz
    input  wire        IO_SELECT,      // $C600-$C6FF
    input  wire        DEVICE_SELECT,  // $C0E0-$C0EF
    input  wire        WE,             // CPU write cycle
    input  wire [15:0] A,
    input  wire [7:0]  D_IN,
    output wire [7:0]  D_OUT,

    output wire        D1_ACTIVE,      // motor on (incl. 1 s holdover), drive 1 selected
    output wire        D2_ACTIVE,
    input  wire        D1_WP,          // OSD "write protect" override
    input  wire        D2_WP,

    // SD block interface, one slot per drive (Apple-II.sv: slots 0 and 2)
    output wire [31:0] SD_LBA0,
    output wire        SD_RD0,
    output wire        SD_WR0,
    input  wire        SD_ACK0,
    output wire [7:0]  SD_BUFF_DIN0,
    output wire [31:0] SD_LBA1,
    output wire        SD_RD1,
    output wire        SD_WR1,
    input  wire        SD_ACK1,
    output wire [7:0]  SD_BUFF_DIN1,
    input  wire [8:0]  SD_BUFF_ADDR,
    input  wire [7:0]  SD_BUFF_DOUT,
    input  wire        SD_BUFF_WR,
    input  wire        IMG_MOUNTED0,
    input  wire        IMG_MOUNTED1,
    input  wire        IMG_READONLY,
    input  wire [63:0] IMG_SIZE
);

    //=========================================================================
    // Soft switches ($C0E0-$C0EF): any access, read or write, updates them.
    //=========================================================================
    reg [3:0] motor_phase;
    reg       drive_on;
    reg       drive2_select;
    reg       q6, q7;

    always @(posedge CLK_14M) begin
        if (RESET) begin
            motor_phase   <= 4'b0000;
            drive_on      <= 1'b0;
            drive2_select <= 1'b0;
            q6            <= 1'b0;
            q7            <= 1'b0;
        end else if (DEVICE_SELECT) begin
            if (!A[3])
                motor_phase[A[2:1]] <= A[0];        // $C0E0-$C0E7
            else case (A[2:1])
                2'b00: drive_on      <= A[0];        // $C0E8/9
                2'b01: drive2_select <= A[0];        // $C0EA/B
                2'b10: q6            <= A[0];        // $C0EC/D
                2'b11: q7            <= A[0];        // $C0EE/F
            endcase
        end
    end

    // One-shot at the end of a CPU cycle that writes the data register
    // ($C08D/$C08F with Q7 set): the 6502's write data is valid then.
    reg  phase_zero_d;
    wire cycle_end = phase_zero_d && !PHASE_ZERO;
    wire data_write_sel = DEVICE_SELECT && WE && (A[3:2] == 2'b11) && A[0];
    wire q7_now = (DEVICE_SELECT && A[3:1] == 3'b111) ? A[0] : q7;
    wire data_load = cycle_end && data_write_sel && q7_now;
    always @(posedge CLK_14M) phase_zero_d <= PHASE_ZERO;

    //=========================================================================
    // Motor: immediate on; off is held ~1 s by the controller's timer.
    // The spinning state feeds the drives (which need it to step) and the
    // dirty-track flush in the WOZ controllers.
    //=========================================================================
    localparam [23:0] SPINUP_TIME   = 24'd1000;      // ~71 us, glitch filter
    localparam [23:0] SPINDOWN_TIME = 24'd14000000;  // ~1 s at 14 MHz
    reg        motor_spinning;
    reg        motor_spinup_done;
    reg [23:0] motor_counter;

    always @(posedge CLK_14M) begin
        if (DD_RESET) begin
            motor_spinning    <= 1'b0;
            motor_spinup_done <= 1'b0;
            motor_counter     <= 24'd0;
        end else if (drive_on) begin
            if (!motor_spinup_done) begin
                if (motor_counter >= SPINUP_TIME) begin
                    motor_spinning    <= 1'b1;
                    motor_spinup_done <= 1'b1;
                    motor_counter     <= SPINDOWN_TIME;
                end else
                    motor_counter <= motor_counter + 24'd1;
            end else begin
                motor_spinning <= 1'b1;
                motor_counter  <= SPINDOWN_TIME;
            end
        end else begin
            motor_spinup_done <= 1'b0;
            if (motor_counter != 24'd0)
                motor_counter <= motor_counter - 24'd1;
            else
                motor_spinning <= 1'b0;
        end
    end

    wire drive_real_on = drive_on || motor_spinning;
    assign D1_ACTIVE = drive_real_on && !drive2_select;
    assign D2_ACTIVE = drive_real_on &&  drive2_select;

    //=========================================================================
    // Drives and track engines
    //=========================================================================
    // Per-drive signals live inside the generate scope and are referenced
    // hierarchically (drive_g[n].x). Unpacked wire arrays assigned element by
    // element are evaluated as one multi-driven variable by Verilator, which
    // made the controllers see sd_ack a cycle late and drop byte 0 of every
    // block.
    wire [1:0]  drv_sel_onehot = {drive2_select, !drive2_select};
    wire [1:0]  osd_wp = {D2_WP, D1_WP};

    // Write path from the sequencer (below) to the selected drive.
    reg  write_bit;
    reg  write_strobe;

    genvar d;
    generate for (d = 0; d < 2; d = d + 1) begin : drive_g
        wire        sel        = drv_sel_onehot[d];
        wire        sd_ack     = (d == 0) ? SD_ACK0 : SD_ACK1;
        wire        mounted_in = (d == 0) ? IMG_MOUNTED0 : IMG_MOUNTED1;

        wire        flux;
        wire        wp;
        wire [8:0]  qtrack;
        wire [5:0]  bit_timer;
        wire [15:0] bram_addr;
        wire [7:0]  write_byte;
        wire        write_we;
        wire [15:0] write_addr;
        wire        mounted;
        wire [31:0] bit_count;
        wire [7:0]  bit_data;
        wire        load_done;
        wire        is_flux;
        wire [31:0] flux_size;
        wire [31:0] flux_ticks;
        wire        ctrl_wp;
        wire [7:0]  timing;
        wire [31:0] sd_lba;
        wire        sd_rd;
        wire        sd_wr;
        wire [7:0]  sd_din;

        // Mount pulse. A mount while already mounted must unmount first so the
        // WOZ controller re-parses the header (same dance as the IIgs top).
        //
        // DD_RESET is the machine reset (F2, the OSD reset, the reset button),
        // not an eject: the HPS still holds the image open. The controller's own
        // reset wipes its parsed WOZ state, so drop img_mounted while reset is
        // held and re-pulse it on the way out, which makes the controller
        // re-parse the header it just lost. media_present deliberately survives
        // DD_RESET; without the re-pulse a reset leaves the drive permanently
        // empty until the user re-mounts from the OSD.
        reg  mounted_d = 1'b0;
        reg  mount = 1'b0;
        reg  remount_pending = 1'b0;
        reg  dd_reset_d = 1'b0;
        reg  media_present = 1'b0;
        always @(posedge CLK_14M) begin
            mounted_d  <= mounted_in;
            dd_reset_d <= DD_RESET;

            // Latch media presence on every HPS mount edge, reset or not: a
            // mount that lands while reset is held still counts as a disk.
            if (!mounted_d && mounted_in)
                media_present <= (IMG_SIZE != 64'd0);

            if (DD_RESET) begin
                mount           <= 1'b0;
                remount_pending <= 1'b0;
            end else if (dd_reset_d) begin
                remount_pending <= media_present;
            end else if (!mounted_d && mounted_in) begin
                if (mount) begin
                    mount           <= 1'b0;
                    remount_pending <= (IMG_SIZE != 64'd0);
                end else
                    mount <= (IMG_SIZE != 64'd0);
            end else if (remount_pending) begin
                mount           <= 1'b1;
                remount_pending <= 1'b0;
            end
        end

        // The head model rests +2 quarter-tracks above the WOZ TMAP convention
        // (see Apple-IIgs.sv, woz_track1_id); subtracting 2 lands half-track
        // rests on the right TMAP entry and leaves whole-track rests unchanged.
        wire [7:0] track_id = (qtrack >= 9'd2) ? (qtrack[7:0] - 8'd2) : 8'd0;
        wire       motor_here = motor_spinning && mounted && sel;

        flux_drive drive (
            .IS_35_INCH(1'b0),
            .DRIVE_ID(d[1:0]),
            .CLK_14M(CLK_14M),
            .RESET(DD_RESET),
            .PHASES(sel ? motor_phase : 4'b0000),
            .IMMEDIATE_PHASES(sel ? motor_phase : 4'b0000),
            .LATCHED_SENSE_REG(3'b000),
            .IWM_MODE(5'b00000),
            .MOTOR_ON(motor_here),
            .SW_MOTOR_ON(drive_on && sel),
            .DISKREG_SEL(1'b0),
            .SEL35(1'b0),
            .DRIVE_SELECT(drive2_select),
            .DRIVE_SLOT(1'b0),
            .DISK_MOUNTED(mounted),
            .DISK_WP(ctrl_wp || osd_wp[d] || !mounted),
            .DOUBLE_SIDED(1'b0),
            .FLUX_TRANSITION(flux),
            .WRITE_PROTECT(wp),
            .SENSE(),
            .DISK_SWITCHED_OUT(),
            .STEP_BUSY_OUT(),
            .STEP_DIR_OUT(),
            .MOTOR_ON_SENSE_OUT(),
            .AT_TRACK0_OUT(),
            .MOTOR_SPINNING(),
            .DRIVE_READY(),
            .TRACK(),
            .HEAD_QTRACK(qtrack),
            .EJECT_REQ(),
            .BIT_POSITION(),
            .BIT_TIMER_OUT(bit_timer),
            .TRACK_BIT_COUNT(bit_count),
            .TRACK_LOADED(mounted),
            .TRACK_LOAD_COMPLETE(load_done),
            .BRAM_ADDR(bram_addr),
            .BRAM_DATA(bit_data),
            .OPTIMAL_BIT_TIMING(timing),
            .IS_FLUX_TRACK(is_flux),
            .FLUX_DATA_SIZE(flux_size),
            .FLUX_TOTAL_TICKS(flux_ticks),
            .WRITE_BIT(write_bit),
            .WRITE_STROBE(write_strobe && sel),
            .WRITE_MODE(q7 && sel),
            .WRITE_BYTE_OUT(write_byte),
            .WRITE_WE_OUT(write_we),
            .WRITE_ADDR_OUT(write_addr),
            .SD_TRACK_REQ(),
            .SD_TRACK_STROBE(),
            .SD_TRACK_ACK(1'b0),
            .CHUNK_RELOAD_REQ(),
            .CHUNK_NEEDED(),
            .CHUNK_LOADED(2'b00),
            .CHUNK_LOADING(1'b0)
        );

        woz_floppy_controller #(.IS_35_INCH(0)) ctrl (
            .clk(CLK_14M),
            .reset(DD_RESET),
            .sd_lba(sd_lba),
            .sd_rd(sd_rd),
            .sd_wr(sd_wr),
            .sd_ack(sd_ack),
            .sd_buff_addr(SD_BUFF_ADDR),
            .sd_buff_dout(SD_BUFF_DOUT),
            .sd_buff_din(sd_din),
            .sd_buff_wr(SD_BUFF_WR),
            .img_mounted(mount),
            .img_readonly(IMG_READONLY),
            .img_size(IMG_SIZE),
            .track_id(track_id),
            .ready(),
            .disk_mounted(mounted),
            .busy(),
            .active(motor_spinning && sel),
            .bit_count(bit_count),
            .bit_addr(bram_addr),
            .stable_side(1'b0),
            .bit_data(bit_data),
            .bit_data_in(write_byte),
            .bit_we(write_we),
            .bit_wr_addr(write_addr),
            .track_load_complete(load_done),
            .is_flux_track(is_flux),
            .flux_data_size(flux_size),
            .flux_total_ticks(flux_ticks),
            .track_data_valid(),
            .disk_type_mismatch(),
            .disk_write_protected(ctrl_wp),
            .optimal_bit_timing(timing),
            .dbg_load_sum(),
            .dbg_load_bytes(),
            .dbg_load_blocks()
        );
    end endgenerate

    assign SD_LBA0 = drive_g[0].sd_lba; assign SD_RD0 = drive_g[0].sd_rd; assign SD_WR0 = drive_g[0].sd_wr; assign SD_BUFF_DIN0 = drive_g[0].sd_din;
    assign SD_LBA1 = drive_g[1].sd_lba; assign SD_RD1 = drive_g[1].sd_rd; assign SD_WR1 = drive_g[1].sd_wr; assign SD_BUFF_DIN1 = drive_g[1].sd_din;

    // Selected drive's view
    wire       sel_flux   = drive2_select ? drive_g[1].flux   : drive_g[0].flux;
    wire       sel_wp     = drive2_select ? drive_g[1].wp     : drive_g[0].wp;
    wire [7:0] sel_timing = drive2_select ? drive_g[1].timing : drive_g[0].timing;
    wire [5:0] sel_bit_timer = drive2_select ? drive_g[1].bit_timer : drive_g[0].bit_timer;
    // Read-mode bit cell boundary, taken from the selected drive's own cell
    // timer: it emits the flux pulse at mid-cell and advances at 1, so every
    // pulse lands in the cell that ends here. The sequencer therefore has no
    // cell accumulator of its own to drift against the drive's (at cells with
    // a fractional part two free-running accumulators walk apart and the
    // window slides off the pulses within a track). The local cell_timer below
    // is used for write mode only, where the drive follows WRITE_STROBE.
    wire       drv_cell_end = (sel_bit_timer == 6'd1);

    //=========================================================================
    // Bit cell timer from the same lookup flux_drive uses (56.5 clocks at
    // timing 32). See woz_cell525.sv.
    //=========================================================================
    wire [5:0]  BIT_CELL;
    wire [9:0]  BIT_CELL_STEP;
    wire [31:0] sel_bits = drive2_select ? drive_g[1].bit_count : drive_g[0].bit_count;
    woz_cell525 cell_lut (.clk(CLK_14M), .timing(sel_timing), .bit_count(sel_bits), .cell_base(BIT_CELL), .cell_step(BIT_CELL_STEP), .half_base(), .half_step());

    reg [5:0] cell_timer;
    reg [9:0] cell_frac;

    //=========================================================================
    // Logic state sequencer
    //=========================================================================
    reg [7:0] sr;            // the data register
    reg       seq_armed;     // QA hold: a pulse has been seen
    // Bus-visible stall after the restart. The IWM spec puts the sync-mode
    // hold at "2 bit times plus four CLK periods"; the two bit times are the
    // hold/arm cells above, the four 7 MHz CLKs (8 clocks here) keep the old
    // byte on the bus a little past the restart. Without them a timing-28
    // disk (49-clock cells) holds a byte for exactly 98 clocks, the length of
    // the ROM's LDA/BPL poll loop, and a phase-locked drive can miss every
    // byte (Border Zone).
    reg [7:0] sr_stall;      // byte shown while stall_cnt != 0
    reg [3:0] stall_cnt;
    reg       flux_seen;
    reg       prev_flux;
    wire      flux_edge = sel_flux && !prev_flux;
    wire      read_mode = !q7 && !q6;
    wire      sense_mode = !q7 && q6;

    reg [9:0] frac_tmp;
    always @(posedge CLK_14M) begin
        prev_flux    <= sel_flux;
        write_strobe <= 1'b0;

        if (stall_cnt != 4'd0) stall_cnt <= stall_cnt - 4'd1;

        if (RESET) begin
            sr         <= 8'h00;
            seq_armed  <= 1'b0;
            stall_cnt  <= 4'd0;
            flux_seen  <= 1'b0;
            cell_timer <= 6'd56;
            cell_frac  <= 10'd0;
            write_bit  <= 1'b0;
        end else begin
            if (flux_edge) flux_seen <= 1'b1;

            if (data_load) begin
                // Load and restart the cell clock half a cell out so bit 7
                // goes to the disk 2 us after the store.
                sr         <= D_IN;
                cell_timer <= {1'b0, BIT_CELL[5:1]};
                cell_frac  <= 10'd0;
                seq_armed  <= 1'b0;
            end else if (sense_mode) begin
                // Write-protect sense shifts in from the left every LSS cycle;
                // within a bit cell the register is all-WP. Pulses discarded.
                sr        <= {8{sel_wp}};
                seq_armed <= 1'b0;
                if (drv_cell_end) flux_seen <= 1'b0;
            end else if (q7 ? (cell_timer == 6'd1) : drv_cell_end) begin
                // Bit cell boundary (write: local timer; read: the drive's).
                // A pulse landing on this very clock counts (flux_seen is
                // cleared textually after the set above).
                flux_seen <= 1'b0;
                if (q7) begin
                    frac_tmp = cell_frac + BIT_CELL_STEP;
                    if (frac_tmp >= 10'd1000) begin cell_timer <= BIT_CELL + 6'd1; cell_frac <= frac_tmp - 10'd1000; end
                    else                      begin cell_timer <= BIT_CELL;         cell_frac <= frac_tmp; end
                end

                if (q7) begin
                    // Write: emit QA, shift a zero in.
                    write_bit    <= sr[7];
                    write_strobe <= 1'b1;
                    sr           <= {sr[6:0], 1'b0};
                    seq_armed    <= 1'b0;
                end else if (sr[7]) begin
                    // QA hold until a pulse arrives, then restart one cell
                    // later with that pulse as the leading 1.
                    if (!seq_armed)
                        seq_armed <= (flux_seen || flux_edge);
                    else begin
                        seq_armed <= 1'b0;
                        sr <= {6'b000000, 1'b1, (flux_seen || flux_edge)};
                        sr_stall  <= sr;
                        stall_cnt <= 4'd8;
                    end
                end else begin
                    sr        <= {sr[6:0], (flux_seen || flux_edge)};
                    seq_armed <= 1'b0;
                end
            end else if (q7)
                cell_timer <= cell_timer - 6'd1;
        end
    end



    //=========================================================================
    // Slot ROM and data bus
    //=========================================================================
    wire [7:0] rom_dout;
    disk_ii_rom u_rom (.clk(CLK_14M), .addr(A[7:0]), .dout(rom_dout));

    // The register is visible in every mode: in read mode it is the byte being
    // assembled or held; after a sense access bit 7 carries write protect; in
    // write mode it is the byte being shifted out.
    wire [7:0] data_reg_vis = (stall_cnt != 4'd0) ? sr_stall : sr;
    assign D_OUT = IO_SELECT ? rom_dout : data_reg_vis;

endmodule
