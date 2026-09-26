// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Newsdee

// video_pipeline.sv
// =====================================================================
// Presentation-pipeline switch for the Apple-II FPGA core.
//
// Takes the raw 1-bit Apple VIDEO + 14 MHz blanking (HBL/VBL) and produces
// the final RGB + timing that feeds the video_mixer. Two paths, muxed on
// `use_composite`:
//
//   * Native RGB (use_composite = 0): vga_controller (the existing color
//     pipeline). Byte-identical to the pre-composite build.
//   * Composite (use_composite = 1): apple_composite encodes the 1-bit
//     video to an NTSC composite stream in THIS 14 MHz domain, and its
//     loopback decoder turns it back to RGB. The 4-preset `case`
//     (Calibrated / Eyeballed / Punchy / Muted) selects the decoder knobs.
//     No knobs are exposed outside this module.
//
// The composite path runs in the 14 MHz domain (one sample per clock), the
// level-2-validated domain, with 4x the timing slack of a 57 MHz mixer
// decode. Each path drives its own consistent RGB + timing set, so the
// stock video_mixer (fed by name: HSync/VSync/HBlank/VBlank/core_R/G/B)
// sees a valid picture in either mode.
// =====================================================================

`default_nettype none

module video_pipeline (
  input  wire        CLK_14M,
  // raw mono tap from the apple2 core
  input  wire        VIDEO,
  input  wire        HBL,
  input  wire        VBL,
  // vga_controller control (native RGB path)
  input  wire        COLOR_LINE,
  input  wire [1:0]  SCREEN_MODE,
  input  wire [1:0]  COLOR_PALETTE,
  input  wire        RUN_FILL_OK,
  input  wire        NTSC_VERTICAL_COMB,
  // custom palette loader (vga_controller ioctl)
  input  wire [24:0] ioctl_addr,
  input  wire [7:0]  ioctl_data,
  input  wire [7:0]  ioctl_index,
  input  wire        ioctl_download,
  input  wire        ioctl_wr,
  output wire        ioctl_wait,
  // Freeze the whole pipeline during a machine stall (save/load, OSD pause)
  input  wire        machine_ce,
  // composite switch
  input  wire        use_composite,  // "Color sharpness" RGB/Composite (status[4])
  input  wire [1:0]  comp_preset,    // 0=Calibrated 1=Eyeballed 2=Punchy 3=Muted
  input  wire        comp_hfix,      // A/B: composite right-edge fix (0=current hshift=9, 1=trimmed hshift=0)
  input  wire [4:0]  comp_hue_adj,   // debug: composite hue adjust 0-31 (added to base hue)
  // final outputs (same names/widths vga_controller gave apple2_top)
  output wire [7:0]  R,
  output wire [7:0]  G,
  output wire [7:0]  B,
  output wire        HS,
  output wire        VS,
  output wire        HBL_O,
  output wire        VBL_O
);

  // ------------------------------------------------------------------
  // Native RGB color path (vga_controller)
  // ------------------------------------------------------------------
  // Seam-fix knobs are fixed, we now have a preferred settings.
  localparam GRAY_SEAM_FIX = 1'b1;
  localparam SEAM_RUN_FILL = 1'b1;
  localparam SEAM_RUN_WIDE = 1'b0;
  wire [7:0] r_vga, g_vga, b_vga;
  wire       hs_vga, vs_vga, hbl_vga, vbl_vga;
  vga_controller tv (
    .CLK_14M(CLK_14M),
    .VIDEO(VIDEO),
    .COLOR_LINE(COLOR_LINE),
    .SCREEN_MODE(SCREEN_MODE),
    .COLOR_PALETTE(COLOR_PALETTE),
    .GRAY_SEAM_FIX(GRAY_SEAM_FIX),
    .SEAM_RUN_FILL(SEAM_RUN_FILL),
    .SEAM_RUN_WIDE(SEAM_RUN_WIDE),
    .RUN_FILL_OK(RUN_FILL_OK),
    .NTSC_VERTICAL_COMB(NTSC_VERTICAL_COMB),
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

  // ------------------------------------------------------------------
  // Sync derivation for the composite encoder (14 MHz domain).
  // hs: 68-cycle pulse 130 cycles into HBL; vs: 3 lines 33 lines into VBL.
  // Matches the vga_controller geometry (VGA_FRONT_PORCH=130, VGA_HSYNC=68,
  // VBL_TO_VSYNC=33, VGA_VSYNC_LINES=3) and the level-2 reference.
  // ------------------------------------------------------------------
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

  // ------------------------------------------------------------------
  // 4-preset knob selection (the ONLY place the presets live).
  // Common to all presets: i_mirror=1 (chirality fix), chroma_short=0, pixel_delay=0,
  // luma_gain=2857, setup=0, agc=1 (all fixed inside apple_composite).
  // ------------------------------------------------------------------
  reg  [7:0] p_sat, p_hue, p_bright, p_contrast;
  reg        p_i_mirror;
  reg        p_chroma_short;
  reg  [3:0] p_smear, p_luma_delay;
  reg        p_agc;
  always @* begin
    // defaults = neutral base (Punchy = base + hue); each preset overrides
    p_sat        = 8'd128;
    p_hue        = 8'd0;
    p_bright     = 8'd0;
    p_contrast   = 8'd128;
    p_i_mirror   = 1'b1;
    p_chroma_short = 1'b0;
    p_smear      = 4'd0;
    p_luma_delay = 4'd0;
    p_agc        = 1'b1;
    case (comp_preset)
      2'd0: begin p_sat=8'd80;  p_hue=8'd115; p_bright=8'hF2; p_contrast=8'd177; end   // Calibrated (hardware-tuned; hue=112 base +3)
      2'd1: begin p_sat=8'd51;  p_hue=8'd128;  p_bright=8'sd10; p_contrast=8'd170; end  // Eyeballed (hardware-tuned)
      2'd2: begin p_sat=8'd100; p_hue=8'd130; p_bright=8'sd9; p_contrast=8'd255; end   // Punchy (AppleWin-like)
      2'd3: begin p_sat=8'd80;  p_hue=8'd112;  p_bright=8'hFB; p_contrast=8'd190; end   // Muted (Eyeballed, sat=80)
      default:   begin end
    endcase
  end

  // ------------------------------------------------------------------
  // Composite path: encode 1-bit video -> NTSC composite -> decode RGB.
  // ------------------------------------------------------------------
  wire [7:0]  r_comp, g_comp, b_comp;
  wire        hs_c_out, vs_c_out, hb_c_out, vb_c_out;
  // ce_out and comp_sample are apple_composite testability ports, Left unconnected on purpose.
  /* verilator lint_off PINMISSING */
  apple_composite u_comp (
    .clk(CLK_14M),
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
    .comb_en(NTSC_VERTICAL_COMB),
    .r(r_comp),
    .g(g_comp),
    .b(b_comp),
    .hs_out(hs_c_out),
    .vs_out(vs_c_out),
    .hb_out(hb_c_out),
    .vb_out(vb_c_out)
  );
  /* verilator lint_on PINMISSING */

  // ------------------------------------------------------------------
  // Composite horizontal shift (composite path only, fine tuning of alignment).
  // ------------------------------------------------------------------
  localparam HSHIFT_BASE = 9;  // TB-measured composite alignment delay
  localparam HSHIFT_MAX  = HSHIFT_BASE + 3;  // pipe must reach 9 (13 stages, index 0..12)
  reg  [HSHIFT_MAX:0] hb_c_pipe, hs_c_pipe;  // 13 stages, index 0..12
  always @(posedge CLK_14M) begin
    if (machine_ce) begin
      hb_c_pipe <= {hb_c_pipe[HSHIFT_MAX-1:0], hb_c_out};
      hs_c_pipe <= {hs_c_pipe[HSHIFT_MAX-1:0], hs_c_out};
    end
  end
  wire [3:0] hshift_idx = comp_hfix ? 4'd0 : HSHIFT_BASE[3:0];  // 0 (fix) or 9 (current)
  wire       hb_c_s = hb_c_pipe[hshift_idx];
  wire       hs_c_s = hs_c_pipe[hshift_idx];

  // ------------------------------------------------------------------
  // Monochrome phosphor emulation (Display Mode B&W / Green / Amber).
  // ------------------------------------------------------------------
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

  // ------------------------------------------------------------------
  // Final mux. Each path drives its own consistent RGB + timing set.
  // ------------------------------------------------------------------
  assign R     = use_composite ? (SCREEN_MODE != 2'b00 ? r_mono : r_comp) : r_vga;
  assign G     = use_composite ? (SCREEN_MODE != 2'b00 ? g_mono : g_comp) : g_vga;
  assign B     = use_composite ? (SCREEN_MODE != 2'b00 ? b_mono : b_comp) : b_vga;
  assign HS    = use_composite ? hs_c_s     : hs_vga;
  assign VS    = use_composite ? vs_c_out   : vs_vga;
  assign HBL_O = use_composite ? hb_c_s     : hbl_vga;
  assign VBL_O = use_composite ? vb_c_out   : vbl_vga;

endmodule

`default_nettype wire
