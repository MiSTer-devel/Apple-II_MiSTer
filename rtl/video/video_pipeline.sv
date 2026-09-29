// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Newsdee

// Selects native RGB or v5-decoded composite RGB and matching timing.
// All processing runs in the 14.318 MHz machine-video domain.

`default_nettype none

// The composite path uses the v5 decoder; the legacy decoder is not built.
module video_pipeline
(
  input  wire        CLK_14M,
  // Raw Apple II video and blanking.
  input  wire        VIDEO,
  input  wire        HBL,
  input  wire        VBL,
  // Native RGB controls.
  input  wire        COLOR_LINE,
  input  wire [1:0]  SCREEN_MODE,
  input  wire [1:0]  COLOR_PALETTE,
  input  wire        RUN_FILL_OK,
  input  wire        NTSC_VERTICAL_COMB,  // old-style 2-line comb gate: 1=On(two-line) 0=Off, common to RGB and Color TV
  // Custom palette loader.
  input  wire [24:0] ioctl_addr,
  input  wire [7:0]  ioctl_data,
  input  wire [7:0]  ioctl_index,
  input  wire        ioctl_download,
  input  wire        ioctl_wr,
  output wire        ioctl_wait,
  // Freeze composite state with the machine during save/load and pauses.
  input  wire        reset,        // machine reset -> composite decoder
  input  wire        machine_ce,
  // Composite display controls.
  input  wire        use_composite,  // "Display Type" != RGB Monitor (status[4:3] != 0)
  input  wire [1:0]  comp_preset,    // 0=Calibrated 1=Eyeballed 2=Punchy 3=Muted
  input  wire        comp_hfix,      // retained for config compatibility; correction is always active
  input  wire [4:0]  comp_hue_adj,   // debug: composite hue adjust 0-31 (added to base hue)
  // P6 state indices add fine offsets to the selected v5 preset.
  // Testbenches must drive these inputs explicitly.
  input  wire [3:0]  v5_hue_st,      // {0,-16,-12,-8,-4,+4,+8,+12,+16} (state 0 = no offset)
  input  wire [1:0]  v5_bright_st,   // {0,-16,+16,+32} (state 0 = no offset; grid = contrast's, 2026-09-27)
  input  wire [2:0]  v5_sat_st,      // {0,-16,-8,+8,+16,+32} (state 0 = no offset)
  input  wire [1:0]  v5_contrast_st, // {0,-16,+16,+32} (state 0 = no offset)
  // Selected RGB and timing.
  output wire [7:0]  R,
  output wire [7:0]  G,
  output wire [7:0]  B,
  output wire        HS,
  output wire        VS,
  output wire        HBL_O,
  output wire        VBL_O
);

  wire [7:0] r_vga, g_vga, b_vga;
  wire       hs_vga, vs_vga, hbl_vga, vbl_vga;
  vga_controller tv (
    .CLK_14M(CLK_14M),
    .VIDEO(VIDEO),
    .COLOR_LINE(COLOR_LINE),
    .SCREEN_MODE(SCREEN_MODE),
    .COLOR_PALETTE(COLOR_PALETTE),
    .RUN_FILL_OK(RUN_FILL_OK),
    .NTSC_VERTICAL_COMB(NTSC_VERTICAL_COMB),  // old-style gate: On->1 Off->0 (common to both modes)
    .HBL(HBL),
    .VBL(VBL),
    .VGA_HS(hs_vga),
    .VGA_VS(vs_vga),
    .VGA_HBL(hbl_vga),
    .VGA_VBL(vbl_vga),
    .VGA_R(r_vga),
    .VGA_G(g_vga),
    .VGA_B(b_vga),
    .ioctl_addr(ioctl_addr),
    .ioctl_data(ioctl_data),
    .ioctl_index(ioctl_index),
    .ioctl_download(ioctl_download),
    .ioctl_wr(ioctl_wr),
    .ioctl_wait(ioctl_wait)
  );

  // Derive composite sync from machine blanking using native geometry.
  localparam [9:0] HSYNC_FRONT_PORCH = 10'd130;
  localparam [9:0] HSYNC_WIDTH       = 10'd68;
  localparam [6:0] VSYNC_FRONT_PORCH = 7'd33;
  localparam [6:0] VSYNC_LINES       = 7'd3;

  reg [9:0] hblank_cnt;
  always @(posedge CLK_14M) begin
    if (machine_ce) begin
      if (HBL) hblank_cnt <= hblank_cnt + 10'd1;
      else     hblank_cnt <= 10'd0;
    end
  end

  reg         hbl_d;
  wire        hbl_rise   = HBL & ~hbl_d;
  always @(posedge CLK_14M) if (machine_ce) hbl_d <= HBL;

  reg [6:0]   vblank_lines;
  always @(posedge CLK_14M) begin
    if (machine_ce) begin
      if (VBL) begin
        if (hbl_rise) vblank_lines <= vblank_lines + 7'd1;
      end else begin
        vblank_lines <= 7'd0;
      end
    end
  end

  wire hs_c = HBL & (hblank_cnt >= HSYNC_FRONT_PORCH) &
              (hblank_cnt <  HSYNC_FRONT_PORCH + HSYNC_WIDTH);
  wire vs_c = VBL & (vblank_lines >= VSYNC_FRONT_PORCH) &
              (vblank_lines <  VSYNC_FRONT_PORCH + VSYNC_LINES);

  // Composite preset bases and P6 fine adjustments.
  reg  [7:0] p_sat, p_hue, p_bright, p_contrast;
  reg        p_i_mirror;
  reg        p_chroma_short;
  reg  [3:0] p_smear, p_sharpness, p_luma_delay;
  reg        p_agc;
  // Preset bases before P6 offsets.
  reg  [7:0] v5a_sat, v5a_hue, v5a_bright, v5a_contrast;
  // Clamp signed intermediate sums to decoder port ranges.
  function signed [7:0] clamp_s8(input signed [15:0] v);
    if      (v >  16'sd127)  clamp_s8 = 8'sh81;   // -127
    else if (v < -16'sd127)  clamp_s8 = 8'sh81;   // -127
    else                     clamp_s8 = v[7:0];
  endfunction
  function [7:0] clamp_u8(input signed [15:0] v);
    if      (v >  16'sd255)  clamp_u8 = 8'hFF;
    else if (v <  16'sd0)    clamp_u8 = 8'h00;
    else                     clamp_u8 = v[7:0];
  endfunction
  // P6 state 0 preserves the preset; other states apply fine offsets.
  logic signed [15:0] k_hue_c;
  always @(*) begin
    case (v5_hue_st)
      4'd0: k_hue_c = 16'sd0;
      4'd1: k_hue_c = -16'sd16;
      4'd2: k_hue_c = -16'sd12;
      4'd3: k_hue_c = -16'sd8;
      4'd4: k_hue_c = -16'sd4;
      4'd5: k_hue_c = 16'sd4;
      4'd6: k_hue_c = 16'sd8;
      4'd7: k_hue_c = 16'sd12;
      default: k_hue_c = 16'sd16;   // 4'd8..15 (OSD list ends at 8)
    endcase
  end
  logic signed [15:0] k_bright_c;
  always @(*) begin
    case (v5_bright_st)
      2'd0: k_bright_c = 16'sd0;
      2'd1: k_bright_c = -16'sd16;
      2'd2: k_bright_c = 16'sd16;
      default: k_bright_c = 16'sd32;   // 2'd3 (grid reduced to contrast's, 2026-09-27)
    endcase
  end
  logic signed [15:0] k_sat_off_c;
  always @(*) begin
    case (v5_sat_st)
      3'd0: k_sat_off_c = 16'sd0;
      3'd1: k_sat_off_c = -16'sd16;
      3'd2: k_sat_off_c = -16'sd8;
      3'd3: k_sat_off_c = 16'sd8;
      3'd4: k_sat_off_c = 16'sd16;
      default: k_sat_off_c = 16'sd32;   // states 5..7 (OSD list ends at 5): +32
    endcase
  end
  logic signed [15:0] k_contrast_off_c;
  always @(*) begin
    case (v5_contrast_st)
      2'd0: k_contrast_off_c = 16'sd0;
      2'd1: k_contrast_off_c = -16'sd16;
      2'd2: k_contrast_off_c = 16'sd16;
      default: k_contrast_off_c = 16'sd32;   // 2'd3
    endcase
  end
  always @* begin
    // Fixed decoder controls shared by all presets.
    p_i_mirror   = 1'b1;
    p_chroma_short = 1'b0;
    p_smear      = 4'd0;   // preset default: smoothing off (Eyeballed/Muted override)
    p_sharpness  = 4'd0;   // preset default: no aperture peaking (Muted overrides)
    p_luma_delay = 4'd0;
    p_agc        = 1'b1;
    case (comp_preset)
      2'd0: begin p_sat=8'd80;  p_hue=8'd115; p_bright=8'hF2; p_contrast=8'd177; end   // Calibrated (hardware-tuned; hue=112 base +3)
      2'd1: begin p_sat=8'd51;  p_hue=8'd128;  p_bright=8'sd10; p_contrast=8'd170; p_smear=4'd3; end  // Eyeballed (hardware-tuned; smoothing on)
      2'd2: begin p_sat=8'd100; p_hue=8'd130; p_bright=8'sd9; p_contrast=8'd255; end   // Punchy (AppleWin-like)
      2'd3: begin p_sat=8'd80;  p_hue=8'd112;  p_bright=8'hFB; p_contrast=8'd190; p_smear=4'd3; p_sharpness=4'd15; end   // Muted (Eyeballed, sat=80; smoothing+sharpness on)
      default:   begin end
    endcase
    // Hardware-tuned v5 preset bases.
    v5a_sat        = 8'd80;
    v5a_hue        = 8'shFC;   // 8-12 = -4
    v5a_bright     = 8'd16;    // 0+16
    v5a_contrast   = 8'd144;   // 128+16
    case (comp_preset)
      2'd1: begin v5a_sat=8'd115; v5a_hue=8'd13;  v5a_bright=8'shE0; v5a_contrast=8'd144; end  // Eyeballed (r1: H-8 B-16 S+32 C+32; r2: H0 B-16 S+32 C-16)
      2'd2: begin v5a_sat=8'd76;  v5a_hue=8'shF7;  v5a_bright=8'd0;   v5a_contrast=8'd144; end  // Punchy (r1: H-16 B+16 S-8 C+32; r2: H-16 B-16 S-16 C-16)
      2'd3: begin v5a_sat=8'd32;  v5a_hue=8'shF5; v5a_bright=8'd0;   v5a_contrast=8'd160; end  // Muted (H-16 B+0 S-16 C+32)
      default:   begin end
    endcase
    // Hue wraps; brightness, saturation, and contrast clamp to port ranges.
    p_hue      = v5a_hue + k_hue_c[7:0];
    p_bright   = clamp_s8($signed(v5a_bright) + k_bright_c);
    p_sat      = clamp_u8($signed({8'd0, v5a_sat}) + k_sat_off_c);   // zero-extend: values >= 128 sign-extend negative as 8-bit signed
    p_contrast = clamp_u8($signed({8'd0, v5a_contrast}) + k_contrast_off_c); // zero-extend: same trap (177 = -79 as 8-bit signed)
  end

  // Encode raw video to NTSC and decode it through v5.
  wire [7:0]  r_comp, g_comp, b_comp;
  wire        hs_c_out, vs_c_out, hb_c_out, vb_c_out;
  // Test-only sample outputs remain unconnected in the core.
  /* verilator lint_off PINMISSING */
  apple_composite #(.V5_AXIS(V5_AXIS), .V5_Q_NEG(V5_Q_NEG)) u_comp (
    .clk(CLK_14M),
    .reset(reset),
    .ce(machine_ce),
    .video(VIDEO),
    .pixel_delay(2'd0),
    .hs(hs_c),
    .vs(vs_c),
    .hb(HBL),
    .vb(VBL),
    .color_line(COLOR_LINE),
    .sat(p_sat),
    .hue(p_hue + comp_hue_adj),
    .bright(p_bright),
    .contrast(p_contrast),
    .i_mirror(p_i_mirror),
    .chroma_short(p_chroma_short),
    .smear(p_smear),
    .luma_delay(p_luma_delay),
    .agc_en(p_agc),
    .comb_mode(NTSC_VERTICAL_COMB ? 2'd1 : 2'd0),
    .black_stretch(2'd0),  // Black Stretch hardwired off
    .sharpness(p_sharpness),
    .r(r_comp),
    .g(g_comp),
    .b(b_comp),
    .hs_out(hs_c_out),
    .vs_out(vs_c_out),
    .hb_out(hb_c_out),
    .vb_out(vb_c_out)
  );
  /* verilator lint_on PINMISSING */

  // Delay composite timing, not RGB, to align the decoded active window:
  // raw encoder hs_c + (HSHIFT_V5 + 1) stages = 136 = native vga HS.
  parameter HSHIFT_V5     = 5;  // align the composite and native left edges
  // Hardware-tested v5 color orientation.
  parameter V5_AXIS  = 0;
  parameter V5_Q_NEG = 0;
  localparam HSHIFT_MAX  = HSHIFT_V5;
  // Shift the composite HS/HBL window by the same amount when smoothing is on so the picture stays centered.
  localparam [3:0] HSHIFT_SMOOTH = 4'd7;
  localparam HSHIFT_PIPE = HSHIFT_MAX + HSHIFT_SMOOTH + 3;  // pipe must reach the max index (+3 margin)
  // NOTE: HSHIFT_V5 + HSHIFT_SMOOTH must stay <= 15 (4-bit index space).
  reg  [HSHIFT_PIPE:0] hb_c_pipe, hs_c_pipe;  // stages 0..HSHIFT_PIPE
  always @(posedge CLK_14M) begin
    if (machine_ce) begin
      hb_c_pipe <= {hb_c_pipe[HSHIFT_PIPE-1:0], hb_c_out};
      hs_c_pipe <= {hs_c_pipe[HSHIFT_PIPE-1:0], hs_c};  // raw sync, not hs_c_out
    end
  end
  wire [3:0] hshift_idx = HSHIFT_V5[3:0]
                        + ((p_smear != 4'd0) ? HSHIFT_SMOOTH : 4'd0);
  wire       hb_c_s = hb_c_pipe[hshift_idx];
  wire       hs_c_s = hs_c_pipe[hshift_idx];

  // Map color-killed composite luma to the native monochrome phosphors.
  localparam [23:0] W_BW = 24'hFFFFFF, K_BW = 24'h000000;
  localparam [23:0] W_GR = 24'h00C001, K_GR = 24'h000F01;  // vga green
  localparam [23:0] W_AM = 24'hFF8001, K_AM = 24'h200801;  // vga amber
  logic [23:0] mono_w, mono_k;
  always @(*) begin
    case (SCREEN_MODE)
      2'b01: begin mono_k = K_BW; mono_w = W_BW; end
      2'b10: begin mono_k = K_GR; mono_w = W_GR; end
      2'b11: begin mono_k = K_AM; mono_w = W_AM; end
      default: begin mono_k = K_BW; mono_w = W_BW; end
    endcase
  end
  wire mono_on = g_comp >= 8'd128;  // decoded gray: black..white
  wire [7:0] r_mono = mono_on ? mono_w[23:16] : mono_k[23:16];
  wire [7:0] g_mono = mono_on ? mono_w[15:8]  : mono_k[15:8];
  wire [7:0] b_mono = mono_on ? mono_w[7:0]   : mono_k[7:0];

  // Select RGB and its matching timing as one path.
  assign R     = use_composite ? (SCREEN_MODE != 2'b00 ? r_mono : r_comp) : r_vga;
  assign G     = use_composite ? (SCREEN_MODE != 2'b00 ? g_mono : g_comp) : g_vga;
  assign B     = use_composite ? (SCREEN_MODE != 2'b00 ? b_mono : b_comp) : b_vga;
  assign HS    = use_composite ? hs_c_s     : hs_vga;
  assign VS    = use_composite ? vs_c_out   : vs_vga;
  assign HBL_O = use_composite ? hb_c_s     : hbl_vga;
  assign VBL_O = use_composite ? vb_c_out   : vbl_vga;

endmodule

`default_nettype wire
