// 5.25" bit cell in 14.318181 MHz clocks, shared by flux_drive (pulse timing)
// and disk_ii_woz (write timing) so the two can never disagree. Integer part
// plus a fractional step in thousandths, and the same for the half cell.
//
// A real 300 RPM drive delivers whatever is on a track in one 200 ms
// revolution, so for a bitstream track the cell is
//
//     cell = 2863636 / bit_count          (~51.0k-bit track -> 56.1 clocks)
//
// computed here with a sequential divider each time the track's bit count
// changes. That keeps every track's rotation exactly 200 ms (cross-track
// sync disks such as the Baudville titles time it) and, because the cell then
// depends on the track rather than on a fixed constant, a byte is not an
// exact number of CPU cycles: the IIgs core's calibrated timing*7/4 makes a
// byte exactly `timing` CPU cycles, which on a //e phase-locks the boot ROM's
// 28-cycle data loop to a timing-28 disk (Border Zone) and loses a byte per
// sector. Measured on the simulated //e: this rule boots the whole WOZ test
// set the calibrated cell boots, plus Border Zone; the true 125 ns cell
// (timing*1.7898) instead broke The Apple at Play, and calibrated + 0.5 clock
// broke the Baudville cross-track-sync disks.
//
// Fallback when the bit count is unknown or implausible (no track, FLUX
// tracks, which carry their own timing): the calibrated timing*7/4 plus half
// a clock, so that a byte is still never a whole number of CPU cycles.
module woz_cell525 (
    input  wire        clk,
    input  wire [7:0]  timing,
    input  wire [31:0] bit_count,   // bits in the current track (0 = unknown)
    output reg  [5:0]  cell_base,
    output reg  [9:0]  cell_step,
    output reg  [5:0]  half_base,
    output reg  [9:0]  half_step
);
    localparam [31:0] REV_X1000 = 32'd2863636000;   // 200 ms in clocks, x1000

    // ---- fallback table: timing*7/4 + 0.5 -----------------------------------
    reg [5:0] fb_cell_base; reg [9:0] fb_cell_step; reg [5:0] fb_half_base; reg [9:0] fb_half_step;
    always @(*) begin
        case (timing)
            8'd16: begin fb_cell_base = 6'd28; fb_cell_step = 10'd500; fb_half_base = 6'd14; fb_half_step = 10'd250; end
            8'd17: begin fb_cell_base = 6'd30; fb_cell_step = 10'd250; fb_half_base = 6'd15; fb_half_step = 10'd125; end
            8'd18: begin fb_cell_base = 6'd32; fb_cell_step = 10'd0;   fb_half_base = 6'd16; fb_half_step = 10'd0;   end
            8'd19: begin fb_cell_base = 6'd33; fb_cell_step = 10'd750; fb_half_base = 6'd16; fb_half_step = 10'd875; end
            8'd20: begin fb_cell_base = 6'd35; fb_cell_step = 10'd500; fb_half_base = 6'd17; fb_half_step = 10'd750; end
            8'd21: begin fb_cell_base = 6'd37; fb_cell_step = 10'd250; fb_half_base = 6'd18; fb_half_step = 10'd625; end
            8'd22: begin fb_cell_base = 6'd39; fb_cell_step = 10'd0;   fb_half_base = 6'd19; fb_half_step = 10'd500; end
            8'd23: begin fb_cell_base = 6'd40; fb_cell_step = 10'd750; fb_half_base = 6'd20; fb_half_step = 10'd375; end
            8'd24: begin fb_cell_base = 6'd42; fb_cell_step = 10'd500; fb_half_base = 6'd21; fb_half_step = 10'd250; end
            8'd25: begin fb_cell_base = 6'd44; fb_cell_step = 10'd250; fb_half_base = 6'd22; fb_half_step = 10'd125; end
            8'd26: begin fb_cell_base = 6'd46; fb_cell_step = 10'd0;   fb_half_base = 6'd23; fb_half_step = 10'd0;   end
            8'd27: begin fb_cell_base = 6'd47; fb_cell_step = 10'd750; fb_half_base = 6'd23; fb_half_step = 10'd875; end
            8'd28: begin fb_cell_base = 6'd49; fb_cell_step = 10'd500; fb_half_base = 6'd24; fb_half_step = 10'd750; end
            8'd29: begin fb_cell_base = 6'd51; fb_cell_step = 10'd250; fb_half_base = 6'd25; fb_half_step = 10'd625; end
            8'd30: begin fb_cell_base = 6'd53; fb_cell_step = 10'd0;   fb_half_base = 6'd26; fb_half_step = 10'd500; end
            8'd31: begin fb_cell_base = 6'd54; fb_cell_step = 10'd750; fb_half_base = 6'd27; fb_half_step = 10'd375; end
            8'd33: begin fb_cell_base = 6'd58; fb_cell_step = 10'd250; fb_half_base = 6'd29; fb_half_step = 10'd125; end
            8'd34: begin fb_cell_base = 6'd60; fb_cell_step = 10'd0;   fb_half_base = 6'd30; fb_half_step = 10'd0;   end
            8'd35: begin fb_cell_base = 6'd61; fb_cell_step = 10'd750; fb_half_base = 6'd30; fb_half_step = 10'd875; end
            default: begin fb_cell_base = 6'd56; fb_cell_step = 10'd500; fb_half_base = 6'd28; fb_half_step = 10'd250; end  // timing 32
        endcase
    end

    // ---- physical cell: sequential restoring division ----------------------
    // q = REV_X1000 / bit_count (cell x1000), then base = q / 1000,
    // step = q % 1000, and the same for q/2. About 100 clocks per update;
    // the outputs hold their previous value meanwhile.
    wire        bits_ok = (bit_count >= 32'd45000) && (bit_count <= 32'd71000);
    reg  [31:0] bits_seen;
    reg  [2:0]  st;          // 0 idle, 1 div q, 2 div base/step, 3 div half
    reg  [5:0]  cnt;
    reg  [31:0] num;         // dividend being shifted in
    reg  [31:0] quo;
    reg  [32:0] rem;
    reg  [31:0] dsr;
    reg  [31:0] q_cell;
    reg  [5:0]  ph_cell_base, ph_half_base;
    reg  [9:0]  ph_cell_step, ph_half_step;
    reg         ph_valid;

    initial begin
        bits_seen = 32'hFFFFFFFF; st = 3'd0; ph_valid = 1'b0;
        ph_cell_base = 6'd56; ph_cell_step = 10'd0; ph_half_base = 6'd28; ph_half_step = 10'd0;
        cnt = 6'd0; num = 32'd0; quo = 32'd0; rem = 33'd0; dsr = 32'd1; q_cell = 32'd0;
    end

    // one restoring-division step: shift the next dividend bit into the
    // remainder and subtract the divisor if it fits
    wire [32:0] rem_next = {rem[31:0], num[31]};
    wire        ge       = (rem_next >= {1'b0, dsr});
    wire [32:0] rem_sub  = ge ? (rem_next - {1'b0, dsr}) : rem_next;
    wire [31:0] quo_next = {quo[30:0], ge};

    always @(posedge clk) begin
        case (st)
            3'd0: begin
                if (bit_count != bits_seen) begin
                    bits_seen <= bit_count;
                    ph_valid  <= 1'b0;
                    if (bits_ok) begin
                        num <= REV_X1000; dsr <= bit_count; quo <= 32'd0; rem <= 33'd0; cnt <= 6'd0;
                        st  <= 3'd1;
                    end
                end
            end
            3'd1, 3'd2, 3'd3: begin
                rem <= rem_sub;
                quo <= quo_next;
                num <= {num[30:0], 1'b0};
                cnt <= cnt + 6'd1;
                if (cnt == 6'd31) begin
                    cnt <= 6'd0; rem <= 33'd0;
                    case (st)
                        3'd1: begin q_cell <= quo_next; st <= 3'd4; end                       // cell x1000
                        3'd2: begin ph_cell_base <= quo_next[5:0]; ph_cell_step <= rem_sub[9:0]; st <= 3'd5; end
                        3'd3: begin ph_half_base <= quo_next[5:0]; ph_half_step <= rem_sub[9:0]; ph_valid <= 1'b1; st <= 3'd0; end
                        default: st <= 3'd0;
                    endcase
                end
            end
            3'd4: begin   // base/step: q_cell / 1000
                num <= q_cell; dsr <= 32'd1000; quo <= 32'd0; rem <= 33'd0; cnt <= 6'd0;
                st <= 3'd2;
            end
            3'd5: begin   // half: (q_cell/2) / 1000
                num <= {1'b0, q_cell[31:1]}; dsr <= 32'd1000; quo <= 32'd0; rem <= 33'd0; cnt <= 6'd0;
                st <= 3'd3;
            end
            default: st <= 3'd0;
        endcase
    end

    always @(*) begin
        if (ph_valid && bits_ok && bit_count == bits_seen) begin
            cell_base = ph_cell_base; cell_step = ph_cell_step;
            half_base = ph_half_base; half_step = ph_half_step;
        end else begin
            cell_base = fb_cell_base; cell_step = fb_cell_step;
            half_base = fb_half_base; half_step = fb_half_step;
        end
    end
endmodule
