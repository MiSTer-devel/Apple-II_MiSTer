//-----------------------------------------------------------------------------
//
// A VGA line-doubler for an Apple ][
//
// Original implementation by Stephen A. Edwards, sedwards@cs.columbia.edu
// Palette and color enhancements by Newsdee, newsdee@gmail.com
//
// This is a process-aligned Verilog port of the active VHDL controller in
// Apple-II_MiSTer_newsdee. Keep both versions structurally similar so fixes can
// be carried between the original core and the Verilator/SystemVerilog port.
//-----------------------------------------------------------------------------

module vga_controller(
    input             CLK_14M,
    input             VIDEO,
    input             COLOR_LINE,
    input      [1:0]  SCREEN_MODE,
    input      [1:0]  COLOR_PALETTE,
    input             GRAY_SEAM_FIX,
    input             NTSC_VERTICAL_COMB,
    input             HBL,
    input             VBL,
    output reg        VGA_HS,
    output reg        VGA_VS,
    output            VGA_HBL,
    output            VGA_VBL,
    output     [7:0]  VGA_R,
    output     [7:0]  VGA_G,
    output     [7:0]  VGA_B,
    input      [24:0] ioctl_addr,
    input      [7:0]  ioctl_data,
    input      [7:0]  ioctl_index,
    input             ioctl_download,
    input             ioctl_wr,
    output reg        ioctl_wait
);

localparam [7:0] WHITE = 8'hFF;
localparam [7:0] WHITE_NTSC = 8'hF1;
localparam integer VGA_HSYNC = 68;
localparam integer VGA_ACTIVE = 282 * 2;
localparam integer VGA_FRONT_PORCH = 130;
localparam integer VBL_TO_VSYNC = 33;
localparam integer VGA_VSYNC_LINES = 3;

reg [5:0] shift_reg = 0;
reg last_hbl = 0;
reg [10:0] hcount = 0;
reg [5:0] vcount = 0;
reg vbl_delayed = 0;

reg [23:0] previous_line_rgb [0:559];
reg previous_line_valid = 0;
reg seam_active_d = 0;
reg [10:0] comb_hcount = 0;
reg [10:0] line_wr_addr = 0;
reg [23:0] line_wr_data = 0;
reg line_wr_en = 0;
reg [23:0] raw_rgb = 0;
reg [23:0] seam_rgb = 0;
reg [23:0] previous_rgb_q = 0;
reg [23:0] current_rgb_q = 0;
reg [23:0] filtered_rgb = 0;
reg [10:0] raw_hcount = 0;
reg raw_active = 0;
reg raw_vbl = 0;
reg raw_color_mode = 0;
reg raw_color_line = 0;
reg seam_timing_active = 0;
reg seam_vbl = 0;
reg seam_color_mode = 0;
reg current_timing_active_q = 0;
reg filtered_timing_active = 0;
reg line_valid_q = 0;
reg color_mode_q = 0;
reg [13:0] timing_active_delay = 0;

reg [23:0] seam_rgb_window [0:4];
integer seam_luma_window [0:4];
integer seam_saturation_window [0:4];
reg [10:0] seam_hcount_window [0:4];
reg [4:0] seam_valid_window = 0;
reg [4:0] seam_vbl_window = 0;
reg [4:0] seam_color_mode_window = 0;
reg [4:0] seam_color_line_window = 0;

reg [1:0] color_addr = 0;
reg [3:0] palette_index = 0;
reg [23:0] palette_rgb_in = 0;

reg [23:0] BUFFER_COL0  = 24'h200820;
reg [23:0] BUFFER_COL1  = 24'h802222;
reg [23:0] BUFFER_COL2  = 24'h222280;
reg [23:0] BUFFER_COL3  = 24'h490080;
reg [23:0] BUFFER_COL4  = 24'h275412;
reg [23:0] BUFFER_COL5  = 24'h636363;
reg [23:0] BUFFER_COL6  = 24'h4063FF;
reg [23:0] BUFFER_COL7  = 24'h4ADBFF;
reg [23:0] BUFFER_COL8  = 24'h7B4513;
reg [23:0] BUFFER_COL9  = 24'hFF8C00;
reg [23:0] BUFFER_COL10 = 24'h818181;
reg [23:0] BUFFER_COL11 = 24'hF87EFC;
reg [23:0] BUFFER_COL12 = 24'h22FF22;
reg [23:0] BUFFER_COL13 = 24'hFFFF22;
reg [23:0] BUFFER_COL14 = 24'hADFFF1;
reg [23:0] BUFFER_COL15 = 24'hF0F0F0;

reg [23:0] CURRENT_COL0  = 24'h200820;
reg [23:0] CURRENT_COL1  = 24'h802222;
reg [23:0] CURRENT_COL2  = 24'h222280;
reg [23:0] CURRENT_COL3  = 24'h490080;
reg [23:0] CURRENT_COL4  = 24'h275412;
reg [23:0] CURRENT_COL5  = 24'h636363;
reg [23:0] CURRENT_COL6  = 24'h4063FF;
reg [23:0] CURRENT_COL7  = 24'h4ADBFF;
reg [23:0] CURRENT_COL8  = 24'h7B4513;
reg [23:0] CURRENT_COL9  = 24'hFF8C00;
reg [23:0] CURRENT_COL10 = 24'h818181;
reg [23:0] CURRENT_COL11 = 24'hF87EFC;
reg [23:0] CURRENT_COL12 = 24'h22FF22;
reg [23:0] CURRENT_COL13 = 24'hFFFF22;
reg [23:0] CURRENT_COL14 = 24'hADFFF1;
reg [23:0] CURRENT_COL15 = 24'hF0F0F0;

function [7:0] clamp_rgb;
    input integer value;
    begin
        if (value < 0) clamp_rgb = 8'h00;
        else if (value > 255) clamp_rgb = 8'hFF;
        else clamp_rgb = value[7:0];
    end
endfunction

function integer rgb_luma;
    input [23:0] rgb;
    begin
        rgb_luma = (306 * rgb[23:16] + 601 * rgb[15:8] +
                    117 * rgb[7:0] + 512) / 1024;
    end
endfunction

function integer rgb_saturation;
    input [23:0] rgb;
    integer red;
    integer green;
    integer blue;
    integer maximum;
    integer minimum;
    begin
        red = rgb[23:16];
        green = rgb[15:8];
        blue = rgb[7:0];
        maximum = red;
        minimum = red;
        if (green > maximum) maximum = green;
        if (blue > maximum) maximum = blue;
        if (green < minimum) minimum = green;
        if (blue < minimum) minimum = blue;
        rgb_saturation = maximum - minimum;
    end
endfunction

function [23:0] palette_color;
    input [1:0] palette;
    input [3:0] color;
    begin
        case (palette)
            2'b00: begin
                case (color)
                    4'b0000: palette_color = 24'h000000;
                    4'b0010: palette_color = 24'h9F1B48;
                    4'b0100: palette_color = 24'h4832EB;
                    4'b0110: palette_color = 24'hD643EF;
                    4'b1000: palette_color = 24'h197544;
                    4'b0101: palette_color = 24'h818181;
                    4'b1100: palette_color = 24'h3692FF;
                    4'b1110: palette_color = 24'hD89EFF;
                    4'b0001: palette_color = 24'h496500;
                    4'b0011: palette_color = 24'hD87300;
                    4'b1010: palette_color = 24'h818181;
                    4'b0111: palette_color = 24'hFB8FBC;
                    4'b1001: palette_color = 24'h3CCC00;
                    4'b1011: palette_color = 24'hBCD600;
                    4'b1101: palette_color = 24'h6CE6B8;
                    default: palette_color = 24'hF1F1F1;
                endcase
            end
            2'b01: begin
                case (color)
                    4'b0000: palette_color = 24'h000000;
                    4'b0010: palette_color = 24'hDB1F42;
                    4'b0100: palette_color = 24'h0C11A4;
                    4'b0110: palette_color = 24'hDC43E1;
                    4'b1000: palette_color = 24'h1C8231;
                    4'b0101: palette_color = 24'hB3B3B3;
                    4'b1100: palette_color = 24'h393DFF;
                    4'b1110: palette_color = 24'h7AB3FF;
                    4'b0001: palette_color = 24'h916400;
                    4'b0011: palette_color = 24'hFA7700;
                    4'b1010: palette_color = 24'h636363;
                    4'b0111: palette_color = 24'hFBA593;
                    4'b1001: palette_color = 24'h40DE00;
                    4'b1011: palette_color = 24'hFEFE00;
                    4'b1101: palette_color = 24'h67FCA4;
                    default: palette_color = 24'hFFFFFF;
                endcase
            end
            2'b10: begin
                case (color)
                    4'b0000: palette_color = 24'h000000;
                    4'b0010: palette_color = 24'h930B7C;
                    4'b0100: palette_color = 24'h1F35D3;
                    4'b0110: palette_color = 24'hBB36FF;
                    4'b1000: palette_color = 24'h00760C;
                    4'b0101: palette_color = 24'h7E7E7E;
                    4'b1100: palette_color = 24'h07A8E0;
                    4'b1110: palette_color = 24'h9DACFF;
                    4'b0001: palette_color = 24'h624C00;
                    4'b0011: palette_color = 24'hF9561D;
                    4'b1010: palette_color = 24'h7E7E7E;
                    4'b0111: palette_color = 24'hFF81EC;
                    4'b1001: palette_color = 24'h43C800;
                    4'b1011: palette_color = 24'hDCCD16;
                    4'b1101: palette_color = 24'h5DF784;
                    default: palette_color = 24'hFFFFFF;
                endcase
            end
            default: palette_color = 24'h000000;
        endcase
    end
endfunction

// Palette processing. ioctl_index 2 is the MiSTer custom A2P palette slot.
always @(posedge CLK_14M) begin
    ioctl_wait <= 1'b0;
    if (ioctl_download && ioctl_index == 8'h02) begin
        if (ioctl_wr) begin
            case (color_addr)
                2'b00: palette_rgb_in <= {ioctl_data, palette_rgb_in[15:0]};
                2'b01: palette_rgb_in <= {palette_rgb_in[23:16], ioctl_data, palette_rgb_in[7:0]};
                default: palette_rgb_in <= {palette_rgb_in[23:8], ioctl_data};
            endcase
            // Golden writes the buffer from the pre-cycle palette_rgb_in on every
            // beat; on beat 4 (color_addr=3) that value is {d0,d1,d2}.
            case (palette_index)
                4'h0: BUFFER_COL0 <= palette_rgb_in;
                4'h1: BUFFER_COL1 <= palette_rgb_in;
                4'h2: BUFFER_COL2 <= palette_rgb_in;
                4'h3: BUFFER_COL3 <= palette_rgb_in;
                4'h4: BUFFER_COL4 <= palette_rgb_in;
                4'h5: BUFFER_COL5 <= palette_rgb_in;
                4'h6: BUFFER_COL6 <= palette_rgb_in;
                4'h7: BUFFER_COL7 <= palette_rgb_in;
                4'h8: BUFFER_COL8 <= palette_rgb_in;
                4'h9: BUFFER_COL9 <= palette_rgb_in;
                4'hA: BUFFER_COL10 <= palette_rgb_in;
                4'hB: BUFFER_COL11 <= palette_rgb_in;
                4'hC: BUFFER_COL12 <= palette_rgb_in;
                4'hD: BUFFER_COL13 <= palette_rgb_in;
                4'hE: BUFFER_COL14 <= palette_rgb_in;
                default: BUFFER_COL15 <= palette_rgb_in;
            endcase
            if (color_addr < 2'b11)
                color_addr <= color_addr + 1'b1;
            else begin
                color_addr <= 0;
                palette_index <= palette_index + 1'b1;
            end
        end
    end else begin
        palette_index <= 0;
        color_addr <= 0;
        palette_rgb_in <= 0;
        CURRENT_COL0 <= BUFFER_COL0;
        CURRENT_COL1 <= BUFFER_COL1;
        CURRENT_COL2 <= BUFFER_COL2;
        CURRENT_COL3 <= BUFFER_COL3;
        CURRENT_COL4 <= BUFFER_COL4;
        CURRENT_COL5 <= BUFFER_COL5;
        CURRENT_COL6 <= BUFFER_COL6;
        CURRENT_COL7 <= BUFFER_COL7;
        CURRENT_COL8 <= BUFFER_COL8;
        CURRENT_COL9 <= BUFFER_COL9;
        CURRENT_COL10 <= BUFFER_COL10;
        CURRENT_COL11 <= BUFFER_COL11;
        CURRENT_COL12 <= BUFFER_COL12;
        CURRENT_COL13 <= BUFFER_COL13;
        CURRENT_COL14 <= BUFFER_COL14;
        CURRENT_COL15 <= BUFFER_COL15;
    end
end

always @(posedge CLK_14M) begin
    if (last_hbl && !HBL) begin
        hcount <= 0;
        vbl_delayed <= VBL;
        if (VBL) vcount <= vcount + 1'b1;
        else vcount <= 0;
    end else hcount <= hcount + 1'b1;
    last_hbl <= HBL;
end

always @(posedge CLK_14M) begin
    if (hcount == VGA_ACTIVE + VGA_FRONT_PORCH) begin
        VGA_HS <= 1'b1;
        if (vcount == VBL_TO_VSYNC) VGA_VS <= 1'b1;
        else if (vcount == VBL_TO_VSYNC + VGA_VSYNC_LINES) VGA_VS <= 1'b0;
    end else if (hcount == VGA_ACTIVE + VGA_FRONT_PORCH + VGA_HSYNC)
        VGA_HS <= 1'b0;
end

// Artifact-color pixel generator.
always @(posedge CLK_14M) begin: pixel_generator
    reg [7:0] r;
    reg [7:0] g;
    reg [7:0] b;
    reg [3:0] shift_color;
    reg [23:0] selected_color;
    begin
        shift_reg <= {VIDEO, shift_reg[5:1]};
        r = 0;
        g = 0;
        b = 0;
        case (SCREEN_MODE)
            2'b00: if (COLOR_PALETTE == 2'b11)
                begin r = CURRENT_COL0[23:16]; g = CURRENT_COL0[15:8]; b = CURRENT_COL0[7:0]; end
            2'b10: begin r = 8'h00; g = 8'h0F; b = 8'h01; end
            2'b11: begin r = 8'h20; g = 8'h08; b = 8'h01; end
            default: begin r = 0; g = 0; b = 0; end
        endcase

        if (!COLOR_LINE) begin
            if (shift_reg[2]) begin
                case (SCREEN_MODE)
                    2'b00: begin
                        if (COLOR_PALETTE == 2'b00)
                            begin r = WHITE_NTSC; g = WHITE_NTSC; b = WHITE_NTSC; end
                        else if (COLOR_PALETTE == 2'b11)
                            begin r = CURRENT_COL15[23:16]; g = CURRENT_COL15[15:8]; b = CURRENT_COL15[7:0]; end
                        else begin r = WHITE; g = WHITE; b = WHITE; end
                    end
                    2'b01: begin r = WHITE; g = WHITE; b = WHITE; end
                    2'b10: begin r = 8'h00; g = 8'hC0; b = 8'h01; end
                    default: begin r = 8'hFF; g = 8'h80; b = 8'h01; end
                endcase
            end
        end else if ((shift_reg[0] == shift_reg[4] && shift_reg[5] == shift_reg[1]) ||
            (GRAY_SEAM_FIX && (shift_reg[3:2] == 2'b01 || shift_reg[3:2] == 2'b10) &&
            !((shift_reg[1:0] == 2'b11 && shift_reg[5:4] == 2'b00) ||
              (shift_reg[1:0] == 2'b00 && shift_reg[5:4] == 2'b11)))) begin
            shift_color = (shift_reg[4:1] << hcount[1:0]) |
                          (shift_reg[4:1] >> (4 - hcount[1:0]));
            if (COLOR_PALETTE == 2'b11) begin
                case (shift_color)
                    4'b0000: selected_color = CURRENT_COL0;
                    4'b0010: selected_color = CURRENT_COL1;
                    4'b0100: selected_color = CURRENT_COL2;
                    4'b0110: selected_color = CURRENT_COL3;
                    4'b1000: selected_color = CURRENT_COL4;
                    4'b1010: selected_color = CURRENT_COL5;
                    4'b1100: selected_color = CURRENT_COL6;
                    4'b1110: selected_color = CURRENT_COL7;
                    4'b0001: selected_color = CURRENT_COL8;
                    4'b0011: selected_color = CURRENT_COL9;
                    4'b0101: selected_color = CURRENT_COL10;
                    4'b0111: selected_color = CURRENT_COL11;
                    4'b1001: selected_color = CURRENT_COL12;
                    4'b1011: selected_color = CURRENT_COL13;
                    4'b1101: selected_color = CURRENT_COL14;
                    default: selected_color = CURRENT_COL15;
                endcase
            end else begin
                selected_color = palette_color(COLOR_PALETTE, shift_color);
            end
            r = selected_color[23:16];
            g = selected_color[15:8];
            b = selected_color[7:0];
        end else begin
            case (shift_reg[3:2])
                2'b11: begin
                    if (COLOR_PALETTE == 2'b00)
                        begin r = WHITE_NTSC; g = WHITE_NTSC; b = WHITE_NTSC; end
                    else if (COLOR_PALETTE == 2'b11)
                        begin r = CURRENT_COL15[23:16]; g = CURRENT_COL15[15:8]; b = CURRENT_COL15[7:0]; end
                    else begin r = WHITE; g = WHITE; b = WHITE; end
                end
                2'b01, 2'b10: begin
                    if (GRAY_SEAM_FIX) begin
                        if (shift_reg[1]) begin
                            if (COLOR_PALETTE == 2'b00)
                                begin r = WHITE_NTSC; g = WHITE_NTSC; b = WHITE_NTSC; end
                            else if (COLOR_PALETTE == 2'b11)
                                begin r = CURRENT_COL15[23:16]; g = CURRENT_COL15[15:8]; b = CURRENT_COL15[7:0]; end
                            else begin r = WHITE; g = WHITE; b = WHITE; end
                        end
                    end else if (COLOR_PALETTE == 2'b11)
                        begin r = CURRENT_COL5[23:16]; g = CURRENT_COL5[15:8]; b = CURRENT_COL5[7:0]; end
                    else begin r = 8'h63; g = 8'h63; b = 8'h63; end
                end
                default: begin r = 0; g = 0; b = 0; end
            endcase
        end

        raw_rgb <= {r, g, b};
        raw_hcount <= hcount;
        raw_vbl <= VBL;
        raw_color_line <= COLOR_LINE;
        raw_active <= !HBL && hcount < 560;
        raw_color_mode <= SCREEN_MODE == 2'b00;
    end
end

// Preserve the VHDL seam-cleanup pipeline layout and active-window delay.
integer seam_index;
always @(posedge CLK_14M) begin: seam_cleanup
    for (seam_index = 0; seam_index < 4; seam_index = seam_index + 1) begin
        seam_rgb_window[seam_index] <= seam_rgb_window[seam_index + 1];
        seam_luma_window[seam_index] <= seam_luma_window[seam_index + 1];
        seam_saturation_window[seam_index] <= seam_saturation_window[seam_index + 1];
        seam_hcount_window[seam_index] <= seam_hcount_window[seam_index + 1];
        seam_valid_window[seam_index] <= seam_valid_window[seam_index + 1];
        seam_vbl_window[seam_index] <= seam_vbl_window[seam_index + 1];
        seam_color_mode_window[seam_index] <= seam_color_mode_window[seam_index + 1];
        seam_color_line_window[seam_index] <= seam_color_line_window[seam_index + 1];
    end
    seam_rgb_window[4] <= raw_rgb;
    seam_luma_window[4] <= rgb_luma(raw_rgb);
    seam_saturation_window[4] <= rgb_saturation(raw_rgb);
    seam_hcount_window[4] <= raw_hcount;
    seam_valid_window[4] <= raw_active;
    seam_vbl_window[4] <= raw_vbl;
    seam_color_mode_window[4] <= raw_color_mode;
    seam_color_line_window[4] <= raw_color_line;

    seam_rgb <= raw_rgb;
    timing_active_delay <= {timing_active_delay[12:0], seam_valid_window[3]};
    seam_timing_active <= timing_active_delay[13];
    seam_vbl <= raw_vbl;
    seam_color_mode <= raw_color_mode;
end

// One-line RGB buffer. Delayed write guarantees read-before-write behavior.
always @(posedge CLK_14M) begin: vertical_line_buffer
    current_rgb_q <= seam_rgb;
    current_timing_active_q <= seam_timing_active;
    line_valid_q <= previous_line_valid;
    color_mode_q <= seam_color_mode;
    line_wr_en <= 1'b0;
    seam_active_d <= seam_timing_active;
    if (seam_vbl) begin
        previous_line_valid <= 1'b0;
        line_valid_q <= 1'b0;
        comb_hcount <= 0;
    end else if (seam_timing_active) begin
        previous_rgb_q <= previous_line_rgb[comb_hcount];
        line_wr_addr <= comb_hcount;
        line_wr_data <= seam_rgb;
        line_wr_en <= 1'b1;
        comb_hcount <= comb_hcount + 1'b1;
    end else if (seam_active_d) begin
        previous_line_valid <= 1'b1;
        comb_hcount <= 0;
    end
    if (line_wr_en) previous_line_rgb[line_wr_addr] <= line_wr_data;
end

// JS-style vertical comb: preserve current-line luma and average chroma.
always @(posedge CLK_14M) begin: vertical_comb_filter
    integer current_luma;
    integer previous_luma;
    integer current_red;
    integer current_green;
    integer current_blue;
    integer previous_red;
    integer previous_green;
    integer previous_blue;
    integer red_chroma;
    integer green_chroma;
    integer blue_chroma;
    reg [23:0] output_rgb;
    begin
        output_rgb = current_rgb_q;
        filtered_timing_active <= current_timing_active_q;
        if (NTSC_VERTICAL_COMB && current_timing_active_q && line_valid_q && color_mode_q) begin
            current_red = current_rgb_q[23:16];
            current_green = current_rgb_q[15:8];
            current_blue = current_rgb_q[7:0];
            previous_red = previous_rgb_q[23:16];
            previous_green = previous_rgb_q[15:8];
            previous_blue = previous_rgb_q[7:0];
            current_luma = (306 * current_red + 601 * current_green +
                            117 * current_blue + 512) / 1024;
            previous_luma = (306 * previous_red + 601 * previous_green +
                             117 * previous_blue + 512) / 1024;
            red_chroma = (current_red - current_luma +
                          previous_red - previous_luma) / 2;
            green_chroma = (current_green - current_luma +
                            previous_green - previous_luma) / 2;
            blue_chroma = (current_blue - current_luma +
                           previous_blue - previous_luma) / 2;
            output_rgb = {clamp_rgb(current_luma + red_chroma),
                          clamp_rgb(current_luma + green_chroma),
                          clamp_rgb(current_luma + blue_chroma)};
        end
        filtered_rgb <= output_rgb;
    end
end

assign VGA_R = filtered_rgb[23:16];
assign VGA_G = filtered_rgb[15:8];
assign VGA_B = filtered_rgb[7:0];
assign VGA_VBL = vbl_delayed;
assign VGA_HBL = ~filtered_timing_active;

endmodule