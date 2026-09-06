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
// The active mapping is a 16 x 8 table (small enough to synthesize as
// registers, not block RAM). Entry i holds the 7-bit Apple II code to send
// when joystick bit i goes down (0 = "no key"). It is initialized to the
// default table (D-pad -> IJKM, fire -> UO, space/enter blank) and can be
// replaced from an external file over the MiSTer ioctl bus (same mechanism as
// the .a2p palette, a dedicated file slot), so per-game profiles can load.
//
// Clock: CLK_14M (same domain as keyboard). The joystick and ioctl are slow
// relative to CLK_14M, so direct sampling is safe (same as the existing joy
// and video-ROM ioctl usage in this domain).
//=============================================================================

module joy_to_key (
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,       // feature on (tied / OSD)
    input  wire [7:0]  joy,          // bit0..7 = right,left,down,up,fire1,fire2,space,enter
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
    initial begin
        // Bit order matches joystick_input.sv (bit0..3 = right,left,down,up;
        // bit4,5 = fire1,fire2; bit6,7 = the extra space/enter buttons). Letter
        // codes equal their ASCII values (verified vs keyboard.mif). Explicit
        // assignments rather than a '{...} pattern: Quartus 17.0.2 does not
        // parse the SystemVerilog assignment pattern.
        joy_map[0] = 8'h4B; // right -> K
        joy_map[1] = 8'h4A; // left  -> J
        joy_map[2] = 8'h4D; // down  -> M
        joy_map[3] = 8'h49; // up    -> I
        joy_map[4] = 8'h55; // fire1 -> U
        joy_map[5] = 8'h4F; // fire2 -> O
        for (i = 6; i < 16; i = i + 1)
            joy_map[i] = 8'h00;   // space(6)/enter(7) blank; 8-15 unused
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

    // Down-edge detect (a key press is a one-shot on 0->1; release is a no-op
    // because keyboard.v clears key_pressed when the CPU reads the key).
    reg [7:0] joy_d;
    wire [7:0] down_edge = joy & ~joy_d;
    always @(posedge clk) begin
        if (reset) joy_d <= 8'b0;
        else       joy_d <= joy;
    end

    // Priority encoder: lowest down-edge bit that maps to a real key. Only one
    // edge is delivered per cycle, so a diagonal (two directions at once) sends
    // the lower bit; the other direction is not queued (known limitation).
    integer b;
    reg [3:0] press_bit;
    reg       press_valid;
    always @(*) begin
        press_bit   = 4'd0;
        press_valid = 1'b0;
        for (b = 7; b >= 0; b = b - 1)
            if (down_edge[b] && joy_map[b] != 8'h00) begin
                press_bit   = b[3:0];
                press_valid = 1'b1;
            end
    end

    wire emit = enable && press_valid;
    always @(posedge clk) begin
        if (reset) begin
            joy_key_press <= 1'b0;
            joy_key_code  <= 7'h00;
        end else begin
            joy_key_press <= emit;
            joy_key_code  <= emit ? joy_map[press_bit][6:0] : 7'h00;
        end
    end

endmodule
