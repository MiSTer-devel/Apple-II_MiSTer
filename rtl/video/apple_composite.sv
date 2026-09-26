// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Newsdee

// apple_composite.sv
// =====================================================================
// Apple II VIDEO (1-bit, 14.318 MHz) -> NTSC composite -> RGB.
//
// Generic composite module for the Apple-II core. 
//
// Geometry measured on this core (tb_burst_probe, 2026-09-10):
//   line        912 cycles  (352 HBL + 560 active)
//   hs pulse    hblank_cnt 130..197 (68 cycles, hs fall at 198)
//   back porch  hblank_cnt 199..351 (VIDEO constant 0 here)
//   constraints for the decoder (SPC=4, BURST_ACC=16, CLAMP_ACC=16):
//     burst_start + 16 <= 153            (measurement fits in HBL)
//     burst_start + burst_len + 16 <= 153 (clamp fits in the back porch)
//   chosen: burst_start=8, burst_len=64  (generated burst at hblank_cnt
//   207..270, clamp at 271..286)
// =====================================================================

`default_nettype none

module apple_composite #(
  // Burst window, in hcnt units (samples after the hs fall). Must satisfy
  // the decoder constraints noted above; tunable if the decoder changes.
  parameter BURST_START = 8,
  parameter BURST_LEN   = 64
)(
  input  wire        clk,        // 14.318 MHz, one composite sample per edge
  input  wire        ce,         // sample valid (1 here; kept for reuse)
  input  wire        video,      // raw 1-bit Apple VIDEO
  input  wire [1:0]  pixel_delay,// source delay in composite samples (0..3)
  input  wire        hs, vs,     // positive sync pulses, sample domain
  input  wire        hb, vb,     // blanking, sample domain
  input  wire        color_line, // 1 = color on; 0 = color kill (suppress burst)
  input  wire [7:0]  sat,        // 128 = unity
  input  wire [7:0]  hue,        // 256 = one full cycle
  input  wire [7:0]  bright,     // signed luma offset, 0 = none
  input  wire [7:0]  contrast,   // mid-gray-centred gain, 128 = unity
  // Harness-only knob pass-throughs (hardwired in the FPGA copy).
  input  wire        i_mirror,   // 1 = I-mirror chirality fix (negate I); 0 = normal (upstream)
  input  wire        chroma_short, // 0 = SPC boxcar; 1 = two-sample boxcar
  input  wire [3:0]  smear,      // chroma trail length, 0 = off
  input  wire [3:0]  luma_delay, // samples (set BELOW chroma path delay)
  input  wire        agc_en,     // track level off the burst
  input  wire        comb_en,    // vertical comb filter enable (1-line chroma average)
  output wire [7:0]  r, g, b,
  output wire        ce_out, hs_out, vs_out, hb_out, vb_out,
  // Modulated sample stream (Q2.21 volts, 1 V = 2^21), one sample per ce
  // pulse.  Exposed for the FPGA path: video_mixer_plus' composite branch
  // decodes this stream.  The loopback r/g/b above stay for the TBs.
  output wire signed [23:0] comp_sample
);

  // ------------------------------------------------------------------
  // Encoder levels, Q2.21 (1.0 V = 2^21 = 20 IRE)
  // ------------------------------------------------------------------
  localparam signed [23:0] V_SYNC  = -24'sd599186;  // -40 IRE (0.286 V)
  localparam signed [23:0] V_BLANK =  24'sd0;       // 0 IRE
  localparam signed [23:0] V_BLACK =  24'sd0;       // 0 IRE
  localparam signed [23:0] V_WHITE =  24'sd1497380; // +70 IRE (0.713 V)
  localparam signed [23:0] V_BURST =  24'sd299892;  // +/-20 IRE (0.286 V p-p)

  // ------------------------------------------------------------------
  // Burst window counter - same semantics as composite_decoder's hcnt:
  // samples since the hs fall. (hb is not needed: the window fits the
  // back porch, which lies inside hb.)
  // ------------------------------------------------------------------
  localparam [9:0] BS = BURST_START[9:0];
  localparam [9:0] BL = BURST_LEN[9:0];

  reg        hs_d;
  reg [9:0]  hcnt;
  always @(posedge clk) begin
    if (ce) begin
      hs_d <= hs;
      if (hs_d && ~hs) hcnt <= 10'd0;
      else if (~&hcnt) hcnt <= hcnt + 10'd1;
    end
  end

  wire in_burst = (hcnt >= BS) && (hcnt < BS + BL);

  // ------------------------------------------------------------------
  // Generated burst: the subcarrier square wave. 
  // ------------------------------------------------------------------
  localparam [1:0] BURST_PHASE_HS_FALL = 2'b11;
  logic [1:0] burst_cnt;
  always @(posedge clk) begin
    if (ce) begin
      if (hs_d && ~hs) burst_cnt <= BURST_PHASE_HS_FALL;
      else             burst_cnt <= burst_cnt + 2'd1;
    end
  end

  wire burst_phase = burst_cnt[1];   // two samples high, two samples low

  logic [3:0] video_pipe;
  always @(posedge clk)
    if (ce) video_pipe <= {video_pipe[2:0], video};

  logic video_sample;
  always_comb begin
    case (pixel_delay)
      2'd1: video_sample = video_pipe[0];
      2'd2: video_sample = video_pipe[1];
      2'd3: video_sample = video_pipe[2];
      default: video_sample = video;
    endcase
  end

  // ------------------------------------------------------------------
  // Composite sample
  // ------------------------------------------------------------------
  logic signed [23:0] comp;
  assign comp = hs
                     ? V_SYNC
                    : (hb && in_burst && color_line)
                     ? (burst_phase ? V_BURST : -V_BURST)
                    : (hb)
                     ? V_BLANK
                    : (video_sample ? V_WHITE : V_BLACK);

  // ------------------------------------------------------------------
  // Decoder
  // ------------------------------------------------------------------
  assign comp_sample = comp;
  wire [7:0] r_i, g_i, b_i;
  composite_decoder #(.SPC(4)) u_dec (
    .clk         (clk),
    .ce          (ce),
    .comp        (comp),
    .hs_in       (hs),
    .vs_in       (vs),
    .hb_in       (hb),
    .vb_in       (vb),
    .burst_start (BS),
    .burst_len   (BL),
    .sat         (sat),
    .hue         (hue),
    .i_mirror    (i_mirror),
    .chroma_short(chroma_short),
    .bright      (bright),
    .contrast    (contrast),
    .smear       (smear),
    .luma_delay  (luma_delay),
    .setup       (16'sd0),
    .luma_gain   (16'sd2857),
    .agc_en      (agc_en),
    .comb_en     (comb_en),
    .color_line  (color_line),
    .ce_out      (ce_out),
    .hs_out      (hs_out),
    .vs_out      (vs_out),
    .hb_out      (hb_out),
    .vb_out      (vb_out),
    .r_out       (r_i),
    .g_out       (g_i),
    .b_out       (b_i)
  );

  assign r = r_i;
  assign g = g_i;
  assign b = b_i;

endmodule

`default_nettype wire
