//-----------------------------------------------------------------------------
//
// PS/2 Keyboard interface for the Apple //e
//
// Based on
// PS/2 Keyboard interface for the Apple ][
//
// Stephen A. Edwards, sedwards@cs.columbia.edu
// After an original by Alex Freed
//
//-----------------------------------------------------------------------------

module keyboard(
    CLK_14M,
    PS2_Key,
    virtual_active,
    virtual_event,
    virtual_pressed,
    virtual_code,
    virtual_control,
    virtual_open_apple,
    virtual_closed_apple,
    reads,
    reset,
    akd,
    K,
    open_apple,
    closed_apple,
    soft_reset,
    video_toggle,
    palette_toggle
);
    
    input            CLK_14M;
    input [10:0]     PS2_Key;		// From PS/2 port
    input            virtual_active;
    input            virtual_event;
    input            virtual_pressed;
    input [6:0]      virtual_code;
    input            virtual_control;
    input            virtual_open_apple;
    input            virtual_closed_apple;
    input            reads;		// Read strobe
    input            reset;
    output reg       akd;		// Any key down
    output [7:0]     K;		// Latched, decoded keyboard data
    output reg       open_apple;
    output reg       closed_apple;
    output reg       soft_reset;
    output reg       video_toggle;   // signal to control change of video modes
    output reg       palette_toggle; // signal to control change of paleetes
    
    
    wire [10:0]      rom_addr;
    wire [7:0]       rom_out;
    wire [7:0]       junction_code;
    wire [7:0]       code;
    reg [7:0]        latched_code;
    wire             ext;
    reg              latched_ext;
    
    reg              key_pressed;		// Key pressed & not read
    reg              ctrl;
    reg              shift;
    reg              caplock;
    reg              old_stb;
    reg              old_virtual_event;
    reg              virtual_active_d;
    reg [6:0]        virtual_code_latched;
    reg              virtual_data;
    
    reg [22:0]       rep_timer;
    
    // Special PS/2 keyboard codes
    parameter [7:0]  LEFT_SHIFT = 8'h12;
    parameter [7:0]  RIGHT_SHIFT = 8'h59;
    parameter [7:0]  LEFT_CTRL = 8'h14;
    parameter [7:0]  CAPS_LOCK = 8'h58;
    parameter [7:0]  WINDOWS = 8'h1F;
    parameter [7:0]  ALT = 8'h11;
    parameter [7:0]  F2 = 8'h06;
    parameter [7:0]  F8 = 8'h0A;
    parameter [7:0]  F9 = 8'h01;
    
    parameter [3:0]  states_IDLE = 0,
                     states_HAVE_CODE = 1,
                     states_DECODE = 2,
                     states_GOT_KEY_UP_CODE = 3,
                     states_GOT_KEY_UP2 = 4,
                     states_KEY_UP = 5,
                     states_NORMAL_KEY = 6,
                     states_KEY_READY1 = 7,
                     states_KEY_READY = 8;
    
    reg [3:0]        state;
    reg [3:0]        next_state;
    
   
      rom #(8,11,"rtl/roms/keyboard.hex") keyboard_rom (
           .clock(CLK_14M),
           .ce(1'b1),
           .a(rom_addr),
           .data_out(rom_out)
   );
/*
    spram #(11, 8, "rtl/roms/keyboard.mif") keyboard_rom(
        .address(rom_addr),
        .clock(CLK_14M),
        .data(1'b0),
        .wren(1'b0),
        .q(rom_out)
    );
 */   
    assign K = virtual_data ? {key_pressed, virtual_code_latched} :
                              {key_pressed, rom_out[6:0]};
    
    
    always @(posedge CLK_14M or posedge reset)
    begin: caplock_ctrl
        if (reset == 1'b1)
            caplock <= 1'b0;
        else 
        begin
            if (state == states_KEY_UP & code == CAPS_LOCK)
                caplock <= (~caplock);
        end
    end
    
    
    always @(posedge CLK_14M or posedge reset)
    begin: shift_ctrl
        if (reset == 1'b1)
        begin
            shift <= 1'b0;
            ctrl <= 1'b0;
            open_apple <= 1'b0;
            closed_apple <= 1'b0;
            soft_reset <= 1'b0;
            video_toggle <= 1'b0;
            palette_toggle <= 1'b0;
        end
        else 
        begin
            if (virtual_active)
            begin
                shift <= 1'b0;
                ctrl <= virtual_control;
                open_apple <= virtual_open_apple;
                closed_apple <= virtual_closed_apple;
                soft_reset <= 1'b0;
                video_toggle <= 1'b0;
                palette_toggle <= 1'b0;
            end
            else if (virtual_active_d)
            begin
                shift <= 1'b0;
                ctrl <= 1'b0;
                open_apple <= 1'b0;
                closed_apple <= 1'b0;
            end
            else if (state == states_HAVE_CODE)
            begin
                if (code == LEFT_SHIFT | code == RIGHT_SHIFT)
                    shift <= 1'b1;
                else if (code == LEFT_CTRL)
                    ctrl <= 1'b1;
                else if (code == WINDOWS)
                    open_apple <= 1'b1;
                else if (code == ALT)
                    closed_apple <= 1'b1;
                else if (code == F2)
                    soft_reset <= 1'b1;
                else if (code == F8)
                    palette_toggle <= 1'b1;
                else if (code == F9)
                    video_toggle <= 1'b1;
            end
            else if (state == states_KEY_UP)
            begin
                if (code == LEFT_SHIFT | code == RIGHT_SHIFT)
                    shift <= 1'b0;
                else if (code == LEFT_CTRL)
                    ctrl <= 1'b0;
                else if (code == WINDOWS)
                    open_apple <= 1'b0;
                else if (code == ALT)
                    closed_apple <= 1'b0;
                else if (code == F2)
                    soft_reset <= 1'b0;
                else if (code == F8)
                    palette_toggle <= 1'b0;
                else if (code == F9)
                    video_toggle <= 1'b0;
            end
        end
    end
    
    assign code = (PS2_Key[7:0]);
    assign ext = PS2_Key[8];
    
    
    always @(posedge CLK_14M or posedge reset)
    begin: fsm
        if (reset == 1'b1)
        begin
            state <= states_IDLE;
            latched_code <= {8{1'b0}};
            latched_ext <= 1'b0;
            key_pressed <= 1'b0;
            akd <= 1'b0;
            old_stb <= 1'b0;
            old_virtual_event <= 1'b0;
            virtual_active_d <= 1'b0;
            virtual_code_latched <= 7'b0;
            virtual_data <= 1'b0;
            rep_timer <= 23'b0;
        end
        else 
        begin
            virtual_active_d <= virtual_active;
            if (reads == 1'b1) key_pressed <= 1'b0;
            if (virtual_active)
            begin
                state <= states_IDLE;
                old_stb <= PS2_Key[10];
                if (!virtual_active_d)
                begin
                    key_pressed <= 1'b0;
                    akd <= 1'b0;
                    virtual_data <= 1'b0;
                    old_virtual_event <= virtual_event;
                end
                else if (old_virtual_event != virtual_event)
                begin
                    old_virtual_event <= virtual_event;
                    if (virtual_pressed)
                    begin
                        virtual_code_latched <= virtual_code;
                        virtual_data <= 1'b1;
                        key_pressed <= 1'b1;
                        akd <= 1'b1;
                    end
                    else akd <= 1'b0;
                end
            end
            else if (virtual_active_d)
            begin
                state <= states_IDLE;
                key_pressed <= 1'b0;
                akd <= 1'b0;
                virtual_data <= 1'b0;
                old_stb <= PS2_Key[10];
            end
            else
            begin
                state <= next_state;
                virtual_data <= 1'b0;
                if (state == states_HAVE_CODE) old_stb <= PS2_Key[10];
                if (state == states_GOT_KEY_UP_CODE) akd <= 1'b0;
                if (state == states_NORMAL_KEY)
                begin
                    latched_code <= code;
                    latched_ext <= ext;
                end
                if (state == states_KEY_READY & junction_code != 8'hFF)
                begin
                    akd <= 1'b1;
                    key_pressed <= 1'b1;
                    rep_timer <= 7000000;		// 0.5s
                end
                if (akd == 1'b1)
                begin
                    rep_timer <= rep_timer - 1;
                    if (rep_timer == 0)
                    begin
                        rep_timer <= 933333;		// 1/15s
                        key_pressed <= 1'b1;
                    end
                end
            end
        end
    end
    
    
    always @(code or old_stb or PS2_Key or state)
    begin: fsm_next_state
        next_state = state;
        case (state)
            states_IDLE :
                if (old_stb != PS2_Key[10])
                    next_state = states_HAVE_CODE;
            
            states_HAVE_CODE :
                next_state = states_DECODE;
            
            states_DECODE :
                if (PS2_Key[9] == 1'b0)
                    next_state = states_GOT_KEY_UP_CODE;
                else if (code == LEFT_SHIFT | code == RIGHT_SHIFT | code == LEFT_CTRL | code == CAPS_LOCK)
                    next_state = states_IDLE;
                else
                    next_state = states_NORMAL_KEY;
            
            states_GOT_KEY_UP_CODE :
                next_state = states_GOT_KEY_UP2;
            
            states_GOT_KEY_UP2 :
                next_state = states_KEY_UP;
            
            states_KEY_UP :
                next_state = states_IDLE;
            
            states_NORMAL_KEY :
                next_state = states_KEY_READY1;
            
            states_KEY_READY1 :
                next_state = states_KEY_READY;
            
            states_KEY_READY :
                next_state = states_IDLE;
            default :
                ;
        endcase
    end
    
    // PS/2 scancode to Keyboard ROM address translation
    assign rom_addr = {1'b0, caplock, junction_code[6:0], (~ctrl), (~shift)};
    
    assign junction_code = ({latched_ext, latched_code} == {1'b0, 8'h76}) ? 8'h00 : 		// Escape ("esc" key)
                           ({latched_ext, latched_code} == {1'b0, 8'h16}) ? 8'h01 : 		// 1
                           ({latched_ext, latched_code} == {1'b0, 8'h1e}) ? 8'h02 : 		// 2
                           ({latched_ext, latched_code} == {1'b0, 8'h26}) ? 8'h03 : 		// 3
                           ({latched_ext, latched_code} == {1'b0, 8'h25}) ? 8'h04 : 		// 4
                           ({latched_ext, latched_code} == {1'b0, 8'h36}) ? 8'h05 : 		// 6
                           ({latched_ext, latched_code} == {1'b0, 8'h2e}) ? 8'h06 : 		// 5
                           ({latched_ext, latched_code} == {1'b0, 8'h3d}) ? 8'h07 : 		// 7
                           ({latched_ext, latched_code} == {1'b0, 8'h3e}) ? 8'h08 : 		// 8
                           ({latched_ext, latched_code} == {1'b0, 8'h46}) ? 8'h09 : 		// 9
    
                           ({latched_ext, latched_code} == {1'b0, 8'h0d}) ? 8'h0A : 		// Horizontal Tab
                           ({latched_ext, latched_code} == {1'b0, 8'h15}) ? 8'h0B : 		// Q
                           ({latched_ext, latched_code} == {1'b0, 8'h1d}) ? 8'h0C : 		// W
                           ({latched_ext, latched_code} == {1'b0, 8'h24}) ? 8'h0D : 		// E
                           ({latched_ext, latched_code} == {1'b0, 8'h2d}) ? 8'h0E : 		// R
                           ({latched_ext, latched_code} == {1'b0, 8'h35}) ? 8'h0F : 		// Y
                           ({latched_ext, latched_code} == {1'b0, 8'h2c}) ? 8'h10 : 		// T
                           ({latched_ext, latched_code} == {1'b0, 8'h3c}) ? 8'h11 : 		// U
                           ({latched_ext, latched_code} == {1'b0, 8'h43}) ? 8'h12 : 		// I
                           ({latched_ext, latched_code} == {1'b0, 8'h44}) ? 8'h13 : 		// O
    
                           ({latched_ext, latched_code} == {1'b0, 8'h1c}) ? 8'h14 : 		// A
                           ({latched_ext, latched_code} == {1'b0, 8'h23}) ? 8'h15 : 		// D
                           ({latched_ext, latched_code} == {1'b0, 8'h1b}) ? 8'h16 : 		// S
                           ({latched_ext, latched_code} == {1'b0, 8'h33}) ? 8'h17 : 		// H
                           ({latched_ext, latched_code} == {1'b0, 8'h2b}) ? 8'h18 : 		// F
                           ({latched_ext, latched_code} == {1'b0, 8'h34}) ? 8'h19 : 		// G
                           ({latched_ext, latched_code} == {1'b0, 8'h3b}) ? 8'h1A : 		// J
                           ({latched_ext, latched_code} == {1'b0, 8'h42}) ? 8'h1B : 		// K
                           ({latched_ext, latched_code} == {1'b0, 8'h4c}) ? 8'h1C : 		// ;
                           ({latched_ext, latched_code} == {1'b0, 8'h4b}) ? 8'h1D : 		// L
    
                           ({latched_ext, latched_code} == {1'b0, 8'h1a}) ? 8'h1E : 		// Z
                           ({latched_ext, latched_code} == {1'b0, 8'h22}) ? 8'h1F : 		// X
                           ({latched_ext, latched_code} == {1'b0, 8'h21}) ? 8'h20 : 		// C
                           ({latched_ext, latched_code} == {1'b0, 8'h2a}) ? 8'h21 : 		// V
                           ({latched_ext, latched_code} == {1'b0, 8'h32}) ? 8'h22 : 		// B
                           ({latched_ext, latched_code} == {1'b0, 8'h31}) ? 8'h23 : 		// N
                           ({latched_ext, latched_code} == {1'b0, 8'h3a}) ? 8'h24 : 		// M
                           ({latched_ext, latched_code} == {1'b0, 8'h41}) ? 8'h25 : 		// ,
                           ({latched_ext, latched_code} == {1'b0, 8'h49}) ? 8'h26 : 		// .
                           ({latched_ext, latched_code} == {1'b0, 8'h4a}) ? 8'h27 : 		// /
    
                           ({latched_ext, latched_code} == {1'b1, 8'h4a}) ? 8'h28 : 		// KP /
    //     X"29" when '1'&x"6b", -- KP Left
                           ({latched_ext, latched_code} == {1'b0, 8'h70}) ? 8'h2A : 		// KP 0
                           ({latched_ext, latched_code} == {1'b0, 8'h69}) ? 8'h2B : 		// KP 1
                           ({latched_ext, latched_code} == {1'b0, 8'h72}) ? 8'h2C : 		// KP 2
                           ({latched_ext, latched_code} == {1'b0, 8'h7a}) ? 8'h2D : 		// KP 3
                           ({latched_ext, latched_code} == {1'b0, 8'h5d}) ? 8'h2E : 		// \
                           ({latched_ext, latched_code} == {1'b0, 8'h55}) ? 8'h2F : 		// =
                           ({latched_ext, latched_code} == {1'b0, 8'h45}) ? 8'h30 : 		// 0
                           ({latched_ext, latched_code} == {1'b0, 8'h4e}) ? 8'h31 : 		// -
    
    //     x"32" when x"", -- KP )
    //     X"33" when X"76", -- KP Escape ("esc" key)
                           ({latched_ext, latched_code} == {1'b0, 8'h6B}) ? 8'h34 : 		// KP 4
                           ({latched_ext, latched_code} == {1'b0, 8'h73}) ? 8'h35 : 		// KP 5
                           ({latched_ext, latched_code} == {1'b0, 8'h74}) ? 8'h36 : 		// KP 6
                           ({latched_ext, latched_code} == {1'b0, 8'h6C}) ? 8'h37 : 		// KP 7
                           ({latched_ext, latched_code} == {1'b0, 8'h0e}) ? 8'h38 : 		// `
                           ({latched_ext, latched_code} == {1'b0, 8'h4d}) ? 8'h39 : 		// P
                           ({latched_ext, latched_code} == {1'b0, 8'h54}) ? 8'h3A : 		// [
                           ({latched_ext, latched_code} == {1'b0, 8'h5b}) ? 8'h3B : 		// ]
    
                           ({latched_ext, latched_code} == {1'b0, 8'h7c}) ? 8'h3C : 		// KP *
    //     X"3D" when '1'&X"74", -- KP Right
                           ({latched_ext, latched_code} == {1'b0, 8'h75}) ? 8'h3E : 		// KP 8
                           ({latched_ext, latched_code} == {1'b0, 8'h7D}) ? 8'h3F : 		// KP 9
                           ({latched_ext, latched_code} == {1'b0, 8'h71}) ? 8'h40 : 		// KP .
                           ({latched_ext, latched_code} == {1'b0, 8'h79}) ? 8'h41 : 		// KP +
                           ({latched_ext, latched_code} == {1'b0, 8'h5a}) ? 8'h42 : 		// Carriage return ("enter" key)
                           ({latched_ext, latched_code} == {1'b1, 8'h75}) ? 8'h43 : 		// (up arrow)
                           ({latched_ext, latched_code} == {1'b0, 8'h29}) ? 8'h44 : 		// Space
                           ({latched_ext, latched_code} == {1'b0, 8'h52}) ? 8'h45 : 		// '
    
    //     X"46" when X"4a", -- ?
    //     X"47" when X"29", -- KP Space
    //     X"48" when x"", -- KP (
                           ({latched_ext, latched_code} == {1'b0, 8'h7b}) ? 8'h49 : 		// KP -
                           ({latched_ext, latched_code} == {1'b1, 8'h5a}) ? 8'h4A : 		// KP return
    //     X"4B" when X"", -- KP ,
                           ({latched_ext, latched_code} == {1'b0, 8'h66}) ? 8'h4E : 		// KP del (backspace - mapped to left)
                           ({latched_ext, latched_code} == {1'b1, 8'h72}) ? 8'h4D : 		// down arrow
                           ({latched_ext, latched_code} == {1'b1, 8'h6b}) ? 8'h4E : 		// left arrow
                           ({latched_ext, latched_code} == {1'b1, 8'h74}) ? 8'h4F : 		// right arrow
    
                           8'hFF;
    
endmodule
