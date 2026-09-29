// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Newsdee

// apple_composite.sv
// 1-bit Apple II video (14.318 MHz) -> NTSC composite sample stream
//
//   sync: hs drives comp to the NTSC tip (-40 IRE); vs is a flag only.
//   burst: +/-20 IRE square (SPC=4) at hcnt 8..71, re-anchored at hs fall.
//
// CROSS-FILE INVARIANT: the decoder's burst window must start on the same
// comp sample as this injection (the reference phase is start-phase only).

`default_nettype none

module apple_composite #(
  // Burst window in samples after the falling edge of horizontal sync.
  parameter BURST_START = 8,
  parameter BURST_LEN   = 64,
  // Colour-frame knobs: AXIS=0 matches the legacy decoder's frame; Q_NEG=0
  // keeps the natural Q sign (1 mirrors the frame across the I axis).
  parameter V5_AXIS  = 0,
  parameter V5_Q_NEG = 0
)(
  input  wire        clk,        // 14.318 MHz, one composite sample per edge
  input  wire        reset,      // decoder reset (machine reset, clk domain)
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
  // Decoder controls are hardwired by the FPGA wrapper and exposed to tests.
  input  wire        i_mirror,   // 1 = I-mirror chirality fix (negate I); 0 = normal (upstream)
  input  wire        chroma_short, // 0 = SPC boxcar; 1 = two-sample boxcar
  input  wire [3:0]  smear,      // chroma trail length, 0 = off
  input  wire [3:0]  luma_delay, // samples (set BELOW chroma path delay)
  input  wire        agc_en,     // track level off the burst
  input  wire [1:0]  comb_mode,  // vertical comb filter mode: 0=off(notch) 1=two-line 2=adaptive
  input  wire [1:0]  black_stretch, // 0=off 1=1/4 2=1/2 3=3/4 (darkness stretch)
  input  wire [3:0]  sharpness,     // aperture peaking 0=off..15 (max ~9 dB)
  output wire [7:0]  r, g, b,
  output wire        ce_out, hs_out, vs_out, hb_out, vb_out,
  // Q2.21 composite sample stream; one sample is produced per ce pulse.
  output wire signed [23:0] comp_sample
);

  // Encoder levels, Q2.21 (1.0 V = 2^21 = 20 IRE)
  localparam signed [23:0] V_SYNC  = -24'sd599186;  // -40 IRE (0.286 V)
  localparam signed [23:0] V_BLANK =  24'sd0;       // 0 IRE
  localparam signed [23:0] V_BLACK =  24'sd0;       // 0 IRE
  localparam signed [23:0] V_WHITE =  24'sd1497380; // +70 IRE (0.713 V)
  localparam signed [23:0] V_BURST =  24'sd299892;  // +/-20 IRE (0.286 V p-p)

  // Count samples from the falling edge of horizontal sync.
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

  // Generate an SPC=4 burst and re-anchor its phase after save-state loads.
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

  // Keep burst and black-clamp references active during vertical sync lines.
  logic signed [23:0] comp;
  // Front porch = the machine samples before the next HS rising edge
  // needs adjustment since composite adds more delay
  wire in_fporch = (hcnt >= 10'd714) && (hcnt < 10'd841);

  assign comp = hs
                     ? V_SYNC
                    : (hb && in_burst && color_line)
                     ? (burst_phase ? V_BURST : -V_BURST)
                    : (hb && !in_fporch)
                     ? V_BLANK
                    : (video_sample ? V_WHITE : V_BLACK);

  wire signed [15:0] v5_brightness = 16'(signed'(bright) * 32'sd32);
  wire [33:0] v5_contrast_prod = 34'(contrast) * 34'd2857;
  // *2857/128: contrast is a Q16 volts-to-white gain with 2857 = unity
  // (NTSC 0.714 V white), so the neutral knob 128 must land exactly on 2857.
  wire [15:0] v5_contrast      = v5_contrast_prod[24:7];   // *2857/128

  assign comp_sample = comp;

  // v5a decoder, SPC=4.
  wire [7:0] r_v5, g_v5, b_v5;
  wire       ce_v5, hs_v5, vs_v5, hb_v5, vb_v5;
  composite_decoder #(.SPC(4), .AXIS(V5_AXIS), .Q_NEG(V5_Q_NEG)) u_dec_v5a (
    .clk          (clk),
    .reset        (reset),
    .ce           (ce),
    .comp         (comp),
    .vs           (vs),
    .vb           (vb),
    .sat          (sat),
    .hue          (hue),
    .chroma_trail (smear),
    .sharpness    (sharpness),
    .black_stretch(black_stretch),
    .brightness   (v5_brightness),
    .contrast     (v5_contrast),
    .i_mirror     (i_mirror),
    .color_line   (color_line),
    .comb_mode    (comb_mode),
    .ce_out       (ce_v5),
    .pix_out      (),
    .hs_out       (hs_v5),
    .vs_out       (vs_v5),
    .hb_out       (hb_v5),
    .vb_out       (vb_v5),
    .r_out        (r_v5),
    .g_out        (g_v5),
    .b_out        (b_v5)
  );

  assign ce_out = ce_v5;
  assign hs_out = hs_v5;
  assign vs_out = vs_v5;
  assign hb_out = hb_v5;
  assign vb_out = vb_v5;
  assign r = r_v5;
  assign g = g_v5;
  assign b = b_v5;

endmodule

`default_nettype wire
