//=============================================================================
// joy_to_key.v — map digital joystick bits to Apple II keystrokes.
//
// Optional, compiler-flag-gated feature (see JOY_TO_KEY_PLAN.md). It watches
// the digital joystick and, on each button down-edge, emits a one-shot key
// press (code + pulse) that keyboard.v injects INDEPENDENTLY of the on-screen
// keyboard's virtual path. So:
//   - the physical PS/2 keyboard keeps working (virtual_active untouched),
//   - the raw joystick keeps working as a joystick (this module only observes
//     it; it never gates or zeroes the joy path).
// The target use case is software that ignores the joystick and wants key
// input; software that uses the joystick sees both.
//
// The active mapping is a 16-byte .a2k table (small enough to synthesize as
// registers, not block RAM). Each byte holds the 7-bit Apple II code to send
// (0 = "no key"). The byte chosen depends on the bus bit AND on Select
// (shift): directions (bits 0-3) map to bytes 0-3 (no shift variant); the
// key buttons A,B,L,R,X,Y (bits 4,5,8,9,10,11) map to bytes 4-9 unshifted or
// 10-15 with Select held. Start (bit 6) and Select (bit 7) are reserved
// controls, not key mappings. It is initialized to the default table (D-pad ->
// IJKM, A/B -> UO, rest blank) and can be replaced from an external file over
// the MiSTer ioctl bus (same mechanism as the .a2p palette, a dedicated file
// slot), so per-game profiles can load.
//
// Clock: CLK_14M (same domain as keyboard). The joystick and ioctl are slow
// relative to CLK_14M, so direct sampling is safe (same as the existing joy
// and video-ROM ioctl usage in this domain).
//=============================================================================

module joy_to_key (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,       // feature on (tied / OSD)
    input  wire [15:0] joy,          // bus bits 0..15 (0-3=dir, 4/5/8-11=keys, 6=Start, 7=Select)
    input  wire        shift,        // Select held (OSK off): select the shifted key bytes
    // MiSTer ioctl file bus (shared; this module only acts on JOYMAP_INDEX)
    input  wire        ioctl_download,
    input  wire        ioctl_wr,
    input  wire [24:0] ioctl_addr,
    input  wire [7:0]  ioctl_data,
    input  wire [7:0]  ioctl_index,
    // one-shot key press to keyboard.v
    output reg         joy_key_press,
    output reg  [6:0]  joy_key_code
);

    // MiSTer file slot for the joy-map profile (0=nib,1=video rom,2=a2p).
    localparam [7:0] JOYMAP_INDEX = 8'h03;
    localparam [6:0] NO_KEY       = 7'h00;

    // Active mapping table (16 x 8; synthesizes as registers).
    //
    // Power-up defaults via `initial` + NO reset on the table (exactly like the
    // .a2p palette's BUFFER_COL* in vga_controller.v): the table is set once at
    // power-on and never cleared by reset, so a loaded .a2k profile SURVIVES a
    // cold/warm reset. At power-on it holds the default map; a .a2k load
    // overwrites it and the new values stick across resets (only a full power
    // cycle restores the default).
    reg [7:0] joy_map [0:15];
    integer i;
    // Packed .a2k byte layout (16 bytes; see byte_index below):
    //   [0:3]   D-pad right/left/down/up           (bus bits 0-3, no shift variant)
    //   [4:9]   A,B,L,R,X,Y unshifted              (bus bits 4,5,8,9,10,11)
    //   [10:15] A,B,L,R,X,Y shifted (Select held)  (same bus bits)
    // Bus bit 6 (Start) and bit 7 (Select) have NO byte: reserved controls.
    initial begin
        // Default map. Letter codes equal their ASCII values (verified vs
        // keyboard.mif). Explicit assignments rather than a '{...} pattern:
        // Quartus 17.0.2 does not parse the SystemVerilog assignment pattern.
        joy_map[0] = 8'h4B; // right -> K
        joy_map[1] = 8'h4A; // left  -> J
        joy_map[2] = 8'h4D; // down  -> M
        joy_map[3] = 8'h49; // up    -> I
        joy_map[4] = 8'h55; // A (fire1) -> U
        joy_map[5] = 8'h4F; // B (fire2) -> O
        for (i = 6; i < 16; i = i + 1)
            joy_map[i] = 8'h00;   // L/R/X/Y + all shifted: blank by default
    end
    always @(posedge clk) begin
        if (ioctl_download && ioctl_index == JOYMAP_INDEX && ioctl_wr
             && ioctl_addr < 25'd16) begin
            // 16-byte table. The guard stops an oversized file wrapping onto
            // entries 0/1. Key codes are 7-bit, so a byte with bit 7 set is
            // invalid (corrupt/wrong file): store 0 (no key) instead of a
            // truncated value that would emit a random keystroke.
            joy_map[ioctl_addr[3:0]] <= (ioctl_data > 8'd127) ? 8'h00 : ioctl_data;
        end
    end

    // Map a mappable bus bit (+shift) to its .a2k byte index (0-15).
    function [3:0] byte_index;
        input [3:0] bus_bit;
        input       sh;
        begin
            case (bus_bit)
                4'd0:  byte_index = 4'd0;
                4'd1:  byte_index = 4'd1;
                4'd2:  byte_index = 4'd2;
                4'd3:  byte_index = 4'd3;
                4'd4:  byte_index = sh ? 4'd10 : 4'd4;
                4'd5:  byte_index = sh ? 4'd11 : 4'd5;
                4'd8:  byte_index = sh ? 4'd12 : 4'd6;
                4'd9:  byte_index = sh ? 4'd13 : 4'd7;
                4'd10: byte_index = sh ? 4'd14 : 4'd8;
                4'd11: byte_index = sh ? 4'd15 : 4'd9;
                default: byte_index = 4'd0;
            endcase
        end
    endfunction

    // Mappable bus bits: 0-5 and 8-11. Bit 6 (Start) and bit 7 (Select) are
    // reserved controls, not key mappings.
    localparam [15:0] MAPPABLE = 16'h0F3F;

    // Down-edge detect (a key press is a one-shot on 0->1; release is a no-op
    // because keyboard.v clears key_pressed when the CPU reads the key).
    reg  [15:0] joy_d;
    wire [15:0] down_edge = joy & ~joy_d;
    always @(posedge clk) begin
        if (reset) joy_d <= 16'b0;
        else       joy_d <= joy;
    end

    // Priority encoder: lowest mappable down-edge bit that maps to a real key.
    // Only one edge is delivered per cycle, so a simultaneous press sends the
    // lower bus bit; the other is not queued (known limitation).
    integer b;
    reg [3:0] bi;
    reg [3:0] press_byte;
    reg       press_valid;
    always @(*) begin
        bi          = 4'd0;
        press_byte  = 4'd0;
        press_valid = 1'b0;
        for (b = 11; b >= 0; b = b - 1) begin
            if (MAPPABLE[b[3:0]] && down_edge[b[3:0]]) begin
                bi = byte_index(b[3:0], shift);
                // If Shift is held but the shifted byte is blank, fall back to
                // the unshifted mapping so the button still does something.
                if (shift && joy_map[bi] == 8'h00)
                    bi = byte_index(b[3:0], 1'b0);
                if (joy_map[bi] != 8'h00) begin
                    press_byte  = bi;
                    press_valid = 1'b1;
                end
            end
        end
    end

    wire emit = enable && press_valid;
    always @(posedge clk) begin
        if (reset) begin
            joy_key_press <= 1'b0;
            joy_key_code  <= 7'h00;
        end else begin
            joy_key_press <= emit;
            joy_key_code  <= emit ? joy_map[press_byte][6:0] : 7'h00;
        end
    end

endmodule
