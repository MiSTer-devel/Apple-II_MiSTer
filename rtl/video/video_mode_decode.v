// video_mode_decode.v - 8-mode "Video Mode" option decode (OSD status[54:52]).
// Pure combinational decode of the existing signal space - all palettes and
// presets already exist in vga (palette_color) and video_pipeline.
//   0 NTSC //e TV    : CTV, palette 00 (NTSC),    preset 0 (Calibrated)
//   1 NTSC //e RGB   : RGB, palette 00 (NTSC)
//   2 AppleWin TV    : CTV, palette 10 (AppleWin), preset 2 (Punchy)
//   3 AppleWin RGB   : RGB, palette 10 (AppleWin)
//   4 IIgs RGB       : RGB, palette 01 (IIgs)
//   5 Faded Tube TV  : CTV, palette 00 (NTSC),    preset 1 (Eyeballed)
//   6 Sharp Muted TV : CTV, palette 00 (NTSC),    preset 3 (Muted)
//   7 Custom RGB     : RGB, palette 11 (loaded A2P table)
module video_mode_decode (
    input  [2:0] video_mode,
    output reg   display_type,   // 1 = Color TV (composite path)
    output reg [1:0] color_palette,  // 00=NTSC //e 01=IIgs 10=AppleWin 11=loaded table
    output reg [1:0] comp_preset    // 0=Calibrated 1=Eyeballed 2=Punchy 3=Muted
);
    always @* begin
        case (video_mode)
            3'd0: begin display_type = 1'b1; color_palette = 2'b00; comp_preset = 2'd0; end
            3'd1: begin display_type = 1'b0; color_palette = 2'b00; comp_preset = 2'd0; end
            3'd2: begin display_type = 1'b1; color_palette = 2'b10; comp_preset = 2'd2; end
            3'd3: begin display_type = 1'b0; color_palette = 2'b10; comp_preset = 2'd0; end
            3'd4: begin display_type = 1'b0; color_palette = 2'b01; comp_preset = 2'd0; end
            3'd5: begin display_type = 1'b1; color_palette = 2'b00; comp_preset = 2'd1; end
            3'd6: begin display_type = 1'b1; color_palette = 2'b00; comp_preset = 2'd3; end
            default: begin display_type = 1'b0; color_palette = 2'b11; comp_preset = 2'd0; end
        endcase
    end
endmodule
