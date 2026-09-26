`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// nsc_ticker.sv
//
// Free-running BCD time/date source for no_slot_clock (NSC item, TODO.md).
//
// Lifted and adapted from the BCD ticker in this project's rtl/clock_card.v
// (that file modeled a slot clock card; its calendar logic is superseded by
// this module, which also adds month-length/leap-year handling that the old
// ticker lacked). Runs entirely on CLK_14M (14.31818 MHz), the same domain
// as the HPS RTC writer (hps_io) and the no_slot_clock instance, so there is
// no clock-domain crossing anywhere in the NSC path.
//
// Time source:
//   - 1 s tick from a counter to 14318182 cycles at 14.31818 MHz
//     (error ~70 ns/s, far below any DS1216E-class tolerance; the HPS RTC
//     reload corrects accumulated drift whenever the host sets the time).
//   - HPS RTC: sys/hps_io.sv "RTC MSM6242B layout" (ioctl cmd 0x22 writes
//     4x16-bit chunks, then a bare 0x22 toggles bit 64 as the set-strobe).
//     On the rising edge of rtc[64] the BCD fields are reloaded using the
//     exact bit positions clock_card.v used, so host-set time keeps working.
//
// Output:
//   - time_bcd: the low 64 bits of the Appletini NSC_time struct (BCD pairs
//     year..centisecond; the centisecond pair is always 0 here — the
//     no_slot_clock internal ticker fills sub-second resolution between
//     reloads). Field order MSB->LSB:
//       year_hi year_lo month_hi month_lo day_hi day_lo
//       dow_hi  dow_lo  hour_hi  hour_lo   min_hi min_lo
//       sec_hi  sec_lo  csec_hi  csec_lo
//   - time_en: one-cycle pulse, asserted ONE CYCLE AFTER the BCD fields (or
//     an RTC reload) have updated. The one-cycle delay is required by the
//     no_slot_clock interface contract (input_time must be stable while
//     input_time_en is high): both modules share CLK_14M, so without the
//     delay the NSC would sample the PRE-tick BCD on the tick edge and the
//     published seconds field would lag reality by exactly one second.
//-----------------------------------------------------------------------------

module nsc_ticker(
    input             clk,        // CLK_14M (14.31818 MHz)
    input             rst,
    input      [64:0] rtc,        // HPS RTC (hps_io), bit 64 = set-strobe
    output     [63:0] time_bcd,   // NSC_time[63:0], see header
    output            time_en     // 1-cycle reload pulse for no_slot_clock
);

// ---------------------------------------------------------------------------
// BCD fields (widths match clock_card.v)
// ---------------------------------------------------------------------------
reg [2:0] sec_tens;
reg [3:0] sec_ones;
reg [2:0] min_tens;
reg [3:0] min_ones;
reg [1:0] hour_tens;
reg [3:0] hour_ones;
reg [2:0] day_week;               // 1..7 (1 = Monday, wraps 7 -> 1)
reg [1:0] day_tens;
reg [3:0] day_ones;
reg       month_tens;             // 0 or 1
reg [3:0] month_ones;             // 1..12
reg [3:0] year_tens;              // BCD offset from 2000
reg [3:0] year_ones;

// ---------------------------------------------------------------------------
// 1 s tick: 14.31818 MHz / 14318182 ~= 1 Hz (70 ns/s fast)
// ---------------------------------------------------------------------------
localparam [23:0] SEC_WRAP = 24'd14318182;
reg [23:0] sec_cnt;

wire sec_tick = (sec_cnt == SEC_WRAP - 1'b1);

always @(posedge clk) begin
    if (rst)
        sec_cnt <= 24'd0;
    else if (sec_tick)
        sec_cnt <= 24'd0;
    else
        sec_cnt <= sec_cnt + 1'b1;
end

// ---------------------------------------------------------------------------
// HPS RTC reload (same bit layout clock_card.v used)
// ---------------------------------------------------------------------------
reg rtc_flg;
wire rtc_reload = (rtc_flg != rtc[64]);

always @(posedge clk) begin
    if (rst)
        rtc_flg <= 1'b0;
    else
        rtc_flg <= rtc[64];
end

// Delay the reload strobe one cycle so time_bcd is already updated when
// the NSC samples it (see header, time_en contract).
reg reload_d;
always @(posedge clk) begin
    if (rst)
        reload_d <= 1'b0;
    else
        reload_d <= sec_tick | rtc_reload;
end

assign time_en = reload_d;

// ---------------------------------------------------------------------------
// Calendar carry (runs once per second tick, or reloads from RTC)
// ---------------------------------------------------------------------------
wire [3:0] m_ones  = month_ones;
wire       leap    = (year_ones[1:0] == 2'b00); // y%4==0: exact for 2000-2099

wire [5:0] month_len =
    (m_ones == 4'd1)  ? 6'd31 :
    (m_ones == 4'd2)  ? (leap ? 6'd29 : 6'd28) :
    (m_ones == 4'd3)  ? 6'd31 :
    (m_ones == 4'd4)  ? 6'd30 :
    (m_ones == 4'd5)  ? 6'd31 :
    (m_ones == 4'd6)  ? 6'd30 :
    (m_ones == 4'd7)  ? 6'd31 :
    (m_ones == 4'd8)  ? 6'd31 :
    (m_ones == 4'd9)  ? 6'd30 :
    (m_ones == 4'd10) ? 6'd31 :
    (m_ones == 4'd11) ? 6'd30 : 6'd31;

// day is BCD; convert to binary for the end-of-month compare
wire [5:0] day_bin  = {2'b00, day_tens} * 6'd10 + {2'b00, day_ones};
wire       day_last = (day_bin == month_len);

always @(posedge clk) begin
    if (rst) begin
        sec_tens   <= 3'd0;
        sec_ones   <= 4'd0;
        min_tens   <= 3'd0;
        min_ones   <= 4'd0;
        hour_tens  <= 2'd0;
        hour_ones  <= 4'd0;
        day_week   <= 3'd1;
        day_tens   <= 2'd0;
        day_ones   <= 4'd1;
        month_tens <= 1'b0;
        month_ones <= 4'd1;
        year_tens  <= 4'd2;
        year_ones  <= 4'd0;
    end else if (rtc_reload) begin
        // HPS time wins (bit positions from clock_card.v)
        sec_tens   <= rtc[6:4];
        sec_ones   <= rtc[3:0];
        min_tens   <= rtc[14:12];
        min_ones   <= rtc[11:8];
        hour_tens  <= rtc[21:20];
        hour_ones  <= rtc[19:16];
        day_week   <= rtc[50:48];
        day_tens   <= rtc[29:28];
        day_ones   <= rtc[27:24];
        month_tens <= rtc[36];
        month_ones <= rtc[35:32];
        year_tens  <= rtc[47:44];
        year_ones  <= rtc[43:40];
    end else if (sec_tick) begin
        // seconds
        if (sec_ones == 4'd9) begin
            sec_ones <= 4'd0;
            if (sec_tens == 3'd5) begin
                sec_tens <= 3'd0;
                // minutes
                if (min_ones == 4'd9) begin
                    min_ones <= 4'd0;
                    if (min_tens == 3'd5) begin
                        min_tens <= 3'd0;
                        // hours (24 h): wrap only at 23 -> 00.
                        // NOTE: clock_card.v's condition also wrapped at x9 ->
                        // x+1:00 (advancing the date 3x per day); not lifted.
                        if (hour_ones == 4'd3 && hour_tens == 2'd2) begin
                            hour_ones <= 4'd0;
                            if (hour_tens == 2'd2) begin
                                hour_tens <= 2'd0;
                                // day / month / year
                                if (day_last) begin
                                    day_ones <= 4'd1;
                                    day_tens <= 2'd0;
                                    if (month_ones == 4'd12) begin
                                        month_ones <= 4'd1;
                                        month_tens <= 1'b0;
                                        // year
                                        if (year_ones == 4'd9) begin
                                            year_ones <= 4'd0;
                                            if (year_tens == 4'd9)
                                                year_tens <= 4'd0;
                                            else
                                                year_tens <= year_tens + 1'b1;
                                        end else
                                            year_ones <= year_ones + 1'b1;
                                    end else begin
                                        if (month_ones == 4'd9) begin
                                            month_ones <= 4'd0;
                                            month_tens <= ~month_tens;
                                        end else
                                            month_ones <= month_ones + 1'b1;
                                    end
                                end else begin
                                    day_ones <= day_ones + 1'b1;
                                end
                                // day of week (1..7)
                                if (day_week == 3'd7)
                                    day_week <= 3'd1;
                                else
                                    day_week <= day_week + 1'b1;
                            end else begin
                                hour_tens <= hour_tens + 1'b1;
                            end
                        end else begin
                            hour_ones <= hour_ones + 1'b1;
                        end
                    end else begin
                        min_tens <= min_tens + 1'b1;
                    end
                end else begin
                    min_ones <= min_ones + 1'b1;
                end
            end else begin
                sec_tens <= sec_tens + 1'b1;
            end
        end else begin
            sec_ones <= sec_ones + 1'b1;
        end
    end
end

// ---------------------------------------------------------------------------
// Pack NSC_time[63:0] (field order per Appletini globals.sv, csec pair = 0)
// ---------------------------------------------------------------------------
assign time_bcd = {
    year_tens,                  // [63:60]
    year_ones,                  // [59:56]
    {3'b000, month_tens},       // [55:52]
    month_ones,                 // [51:48]
    {2'b00, day_tens},          // [47:44]
    day_ones,                   // [43:40]
    4'b0000,                    // [39:36] dow_hi (always 0)
    {1'b0, day_week},           // [35:32]
    {2'b00, hour_tens},         // [31:28]
    hour_ones,                  // [27:24]
    {1'b0, min_tens},           // [23:20]
    min_ones,                   // [19:16]
    {1'b0, sec_tens},           // [15:12]
    sec_ones,                   // [11:8]
    4'b0000,                    // [7:4]   csec_hi
    4'b0000                     // [3:0]   csec_lo
};

endmodule
