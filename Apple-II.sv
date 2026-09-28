//============================================================================
//  Apple II+
//
//  Port to MiSTer
//  Copyright (C) 2017-2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

assign USER_OUT = '1;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
 
assign LED_USER  = led;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;
assign VGA_F1    = 0;
assign HDMI_FREEZE = ss_busy;
assign HDMI_BLACKOUT = 0;

wire [1:0] ar = status[13:12];
video_freak video_freak
(
	.*,
	.VGA_DE_IN(VGA_DE),
	.VGA_DE(),
	.ARX((!ar) ? 12'd4 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE(0),
	.CROP_OFF(0),
	.SCALE(status[15:14])
);

// Status Bit Map:
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// X   XXXXXXXXXXXXXXXXXXXXXXXX 

`include "build_id.v" 
parameter CONF_STR = {
	"Apple-II;SS3E000000:200000,UART19200:9600:4800:2400:1200:300;",
	"-;",
	"S0,NIBDSKDO PO WOZ,Drive 1;",
	"S2,NIBDSKDO PO WOZ,Drive 2;",
	"OQR,Write Protect,None,Drive 1,Drive 2,Drive 1 & 2;",
	"-;",
	"S1,HDV;",
	"-;",
	"P0O4,Display Type,RGB Monitor,Color TV;",
	"D0P0OOP,RGB palette,NTSC //e,IIgs,AppleWin,Custom;",
	"d0P0O12,Color TV Preset,Calibrated,Eyeballed,Punchy,Muted;",
	"-;",
	"P1,System & BIOS;",
	"P1-;",
	"P1O5,CPU,65C02,6502;",
	"P1OM,PAL Mode,NTSC,PAL;",
	"P1oC,Pause when OSD is open,Off,On;",
	"P1-;",
	"P1ON,Video Rom,US,LOCAL;",
	"P1F1,BIN,Load 8k Video ROM;", 
	"P1-;",
	"P2,Audio & Video;",
	"P2-;",
	"P2O78,Stereo mix,none,25%,50%,100%;",
	"P2-;",
	"P2OJK,Display Mode,Color,B&W,Green,Amber;",
	"P2FC2,A2P,Custom RGB Palette;",
	"P2-;",
	"P2OG,Pixel Clock,Double,Normal;",
	"P2OL,Lo-Res Text,Clean,Composite;",
	"P2oPT,Comp Hue Adj,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15;",
	"P2oU,Comp right-edge fix,Off,On;",
	"P2o0,NTSC Vert. Comb Filter,On,Off;",
	"P2-;",
	"P2O9B,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;", 
	"P2OCD,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P2OEF,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P2-;",
	"P3,Hardware;",
	"P3-;",	
	"P3OST,Slot 4,Mocking board,Mouse,Z80 Softcard,Empty;",
	"P3OUV,Slot 5,Mouse,Mocking board,256K Saturn,Empty;",
	"P3-;",
	"P3O6,Analog X/Y,Normal,Swapped;",
	"P3OHI,Paddle as analog,No,X,Y;",
	"P3o46,Analog X center,0,-16,-32,-48,-64,-72,+32,+48;",
	"P3o7,Joystick mode,Absolute,Relative;",
	"P3-;",	
	"P3o3,Disk LED overlay,Yes,No;",
	// Disk drive sound: disabled in the WOZ variant (the flux drives expose
	// no motor/step signals; the floppy_sound instance is tied off below).
	"P3-;",
	"P4,Virtual keyboard;",
	"P4-;",
	"P4oA,Virtual keyboard,Off,On;",
	"P4o89,Keypad visibility,100%,75%,50%,25%;",
	"P4-;",
	"P4oB,Joystick to keys,Off,On;",
	"P4F3,A2K,Load Joy Map;",
	"P4-;",
	"P5,Save States;",
	"P5-;",
	"d8P5oD,Savestates to SDCard,Off,On;",
	"P5oEF,Savestate Slot,1,2,3,4;",
	"P5rG,Save state (F6);",
	"P5rH,Restore state (F5);",
	"P5-;",
	"-;",
	"R0,Cold Reset;",
	// Gamepad layout (ABXYLR + Start/Select), one slot per hps_io bus bit.
	// jn names map to bus bits 4-11 (D-pad is auto on bits 0-3): verify the
	// exact bit positions on hardware (see WOZ_MERGE.md / joy-to-key notes).
	"JA,Btn1|A,Btn2|B,Start,Select,L,R,X,Y;",
	"jn,Btn1|A,Btn2|B,Start,Select,L,R,X,Y;",
	"jp,Y|P,B;",
	// Save-state info strings (index 0 is the "I" marker): 1-4 active slot,
	// 5-12 "State N saved/loaded" (5 + 2*slot + load), 13 Saturn, 14 invalid,
	// 15 incompatible. Driven on hps_io.info by rtl/savestates/savestate_ui.sv.
	"I,",
	"Active slot 1,",
	"Active slot 2,",
	"Active slot 3,",
	"Active slot 4,",
	"State 1 saved,",
	"State 1 loaded,",
	"State 2 saved,",
	"State 2 loaded,",
	"State 3 saved,",
	"State 3 loaded,",
	"State 4 saved,",
	"State 4 loaded,",
	"Save states unavailable (Saturn),",
	"Invalid or empty state,",
	"Incompatible state format or CPU;",
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

wire clk_sys;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_VIDEO),
	.outclk_1(clk_sys)
);

/////////////////  HPS  ///////////////////////////

wire [63:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [21:0] gamma_bus;

wire [15:0] joystick_0;
wire [15:0] joystick_a0;
wire  [7:0] paddle_0;

wire [10:0] ps2_key;
wire [24:0] ps2_mouse;


// The ps2_mouse changes on transition, but gyruco's mouse 
// implementation is based on the mist mouse_strobe logic
wire mouse_strobe = (old_stb != ps2_mouse[24]);
reg  old_stb = 0;
always @(posedge clk_sys) old_stb <= ps2_mouse[24];

wire mouse_4_inslot = status[29:28] == 2'b01;
wire mouse_5_inslot = status[31:30] == 2'b00;
wire mb_4_inslot = status[29:28] == 2'b00;
wire mb_5_inslot = status[31:30] == 2'b01;
wire saturn_5_inslot = status[31:30] == 2'b10;
wire softcard_4_inslot = status[29:28] == 2'b10;	


wire [31:0] sd_lba[3];
reg   [2:0] sd_rd;
reg   [2:0] sd_wr;
wire  [2:0] sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[3];
wire        sd_buff_wr;
wire  [2:0] img_mounted;
wire        img_readonly;

wire [63:0] img_size;
wire [64:0] RTC;

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;


wire soft_reset;

wire [10:0] filtered_ps2_key;
wire [10:0] core_ps2_key;
wire        save_request;
wire        load_request;
wire virtual_keyboard_active;
wire virtual_keyboard_commands;
wire [2:0] virtual_keyboard_row;
wire [3:0] virtual_keyboard_col;
wire virtual_keyboard_shift;
wire virtual_keyboard_control;
wire virtual_keyboard_caps;
wire virtual_keyboard_shift_active;
wire virtual_keyboard_control_active;
wire virtual_keyboard_enabled_toggle;
wire virtual_open_apple;
wire virtual_closed_apple;
wire virtual_keyboard_transparency_cycle;
wire virtual_keyboard_top;
wire virtual_keyboard_event;
wire virtual_keyboard_pressed;
wire [6:0] virtual_keyboard_code;
wire virtual_keyboard_reset;

virtual_keyboard_controller virtual_keyboard_controller
(
	.clk(clk_sys),
	.reset(RESET | status[0]),
	.ps2_key(ps2_key),
	.joystick(joystick_0[10:0]),
	.joystick_analog(joystick_a0_norm),
	.enabled(virtual_keyboard_enabled),
	.filtered_ps2_key(filtered_ps2_key),
	.active(virtual_keyboard_active),
	.commands_page(virtual_keyboard_commands),
	.selected_row(virtual_keyboard_row),
	.selected_col(virtual_keyboard_col),
	.shift_latched(virtual_keyboard_shift),
	.control_latched(virtual_keyboard_control),
	.caps_latched(virtual_keyboard_caps),
	.shift_active(virtual_keyboard_shift_active),
	.control_active(virtual_keyboard_control_active),
	.enabled_toggle(virtual_keyboard_enabled_toggle),
	.open_apple(virtual_open_apple),
	.closed_apple(virtual_closed_apple),
	.transparency_cycle(virtual_keyboard_transparency_cycle),
	.overlay_top(virtual_keyboard_top),
	.virtual_event(virtual_keyboard_event),
	.virtual_pressed(virtual_keyboard_pressed),
	.virtual_code(virtual_keyboard_code),
	.command_reset(virtual_keyboard_reset)
);

savestate_hotkeys savestate_hotkeys (
	.clk(clk_sys),
	.reset(RESET | status[0]),
	.filtered_ps2_key(filtered_ps2_key),
	.core_ps2_key(core_ps2_key),
	.save_request(save_request),
	.load_request(load_request)
);

hps_io #(.CONF_STR(CONF_STR), .VDNUM(3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status),
	// Bit 45 ("Savestates to SDCard") is forced low: the option is a disabled
	// preview and the persistence path is not implemented.
	.status_in({status[63:46],1'b0,status[44:43],virtual_keyboard_enabled_toggle?~status[42]:status[42],virtual_keyboard_transparency_cycle?virtual_keyboard_transparency_req:status[41:40],status[39:26],palette_toggle?palette_req:status[25:24],status[23:21],video_toggle?screen_mode_req:status[20:19],status[18:0]}),
	.status_set(video_toggle || palette_toggle || virtual_keyboard_transparency_cycle || virtual_keyboard_enabled_toggle || ss_boot_clear),
	.status_menumask({ss_menumask[15:1], status[4]}),
	.info_req(ss_info_req),
	.info(ss_info),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),

	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.ioctl_wait(0),
	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	.ioctl_index(ioctl_index),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),

	.joystick_0(joystick_0),
	.joystick_l_analog_0(joystick_a0),
	.paddle_0(paddle_0),



	
	.RTC(RTC)

);

///////////////////////////////////////////////////

// The HPS gamepad reports +Y = stick down (screen coordinates), but the
// core PDL path (joy_an) and the OSK cursor both assume +Y = stick up.
// Negate the analog Y byte once here so both consumers see the same
// normalized axis. The X byte, all digital D-pad/button bits, and the
// separate paddle input are untouched.
wire [15:0] joystick_a0_norm = {-joystick_a0[15:8], joystick_a0[7:0]};

wire [15:0] joya;
wire  [7:0] joyd;
wire [15:0] core_joya = virtual_keyboard_active ? 16'h0000 : joya;
// 16-bit digital bus for joy-to-key: low 8 = joyd (axis-masked, unchanged),
// high 8 = raw hps_io bits 8-15 (the A/B/X/Y/L/R key buttons). Zeroed while
// the OSK is up so its button presses don't double-trigger joy-to-key.
wire [15:0] core_joyd = virtual_keyboard_active ? 16'h0000 : {joystick_0[15:8], joyd};

joystick_input joystick_input
(
	.clk(clk_sys),
	.reset(RESET | status[0] | buttons[1] | virtual_keyboard_reset | soft_reset),
	.joystick_digital(joystick_0),
	.joystick_analog(joystick_a0_norm),
	.paddle(paddle_0),
	.swap_axes(status[6]),
	.paddle_as_x(status[17]),
	.paddle_as_y(status[18]),
	.x_center(status[38:36]),
	.relative_mode(status[39]),
	.joy_an(joya),
	.joy(joyd)
);

wire [9:0] core_audio_l, core_audio_r;
wire [9:0] floppy_audio;
wire [10:0] audio_l_sum = {1'b0, core_audio_l} + {1'b0, floppy_audio};
wire [10:0] audio_r_sum = {1'b0, core_audio_r} + {1'b0, floppy_audio};
wire [9:0] audio_l = audio_l_sum[10] ? 10'h3FF : audio_l_sum[9:0];
wire [9:0] audio_r = audio_r_sum[10] ? 10'h3FF : audio_r_sum[9:0];

assign AUDIO_L = {1'b0, audio_l, 5'd0};
assign AUDIO_R = {1'b0, audio_r, 5'd0};
assign AUDIO_S = 0;
assign AUDIO_MIX = status[8:7];

reg ce_pix;
always @(posedge CLK_VIDEO) begin
	reg [2:0] div = 0;
	
	div <= div + 1'd1;
	ce_pix <= status[16] ? &div : &div[1:0];
end

wire led;
wire hbl,vbl;

reg       text_color = 0;
reg       video_toggle = 0;
reg       palette_toggle = 0;
wire [1:0] screen_mode;
wire [1:0] palette_mode;
wire osd_pause = status[44] && OSD_STATUS;
// Start (gamepad bus bit 6) shows/hides the virtual keyboard. This is handled
// by the VK controller's own visibility function: bit 6 down-edge drives
// enabled_toggle, which toggles status[42] via the hps_io status_set path
// (see status_in above). No separate latch here -- a second toggle on the
// same bit would cancel the controller's and leave the keyboard stuck.
wire virtual_keyboard_enabled = status[42];
wire [1:0] virtual_keyboard_visibility = status[41:40];
wire current_cpu = ~status[5];
wire active_cpu = ss_busy ? ss_locked_cpu : current_cpu;

wire [9:0]  ss_addr;
wire [63:0] ss_wdata;
wire [63:0] ss_rdata;
wire [63:0] top_ss_rdata;
wire        ss_wren;
wire        machine_ce;
wire        cpu_frozen;
wire        ss_busy;
wire        ss_done;
wire        ss_error;
wire        ss_locked_cpu;

wire        ram_ss_bank;
wire [15:0] ram_ss_addr;
wire        ram_ss_rd;
wire        ram_ss_wr;
wire [7:0]  ram_ss_wdata;
wire [7:0]  ram_ss_rdata;

wire [14:0] slot_addr;
wire        slot_rd;
wire        slot_wr;
wire [63:0] slot_wdata;
wire [63:0] slot_rdata;
wire        slot_ready;

// Save-state UI (OSD page, hotkeys, feedback) - see rtl/savestates/savestate_ui.sv.
wire [1:0]  ss_error_code;
wire        ui_save_req;
wire        ui_load_req;
wire [1:0]  ui_ss_slot;
wire [15:0] ss_menumask;
wire        ss_info_req;
wire [7:0]  ss_info;

// One-shot startup clear: force the (unimplemented) "Savestates to SDCard"
// bit 45 low in case an old configuration left it set. The counter
// saturates at 16 so the clear pulse fires exactly once after reset.
reg  [4:0] ss_boot_cnt;
reg        ss_boot_clear;
always @(posedge clk_sys) begin
	if (RESET) begin
		ss_boot_cnt <= 5'd0;
		ss_boot_clear <= 1'b0;
	end else begin
		if (ss_boot_cnt < 5'd16) ss_boot_cnt <= ss_boot_cnt + 5'd1;
		ss_boot_clear <= (ss_boot_cnt == 5'd15);
	end
end
wire [1:0] virtual_keyboard_transparency_req = virtual_keyboard_visibility + 1'd1;
reg [1:0] screen_mode_req;
reg [1:0] palette_req;

assign screen_mode = status[20:19];
assign palette_mode = status[25:24];

always @(posedge clk_sys) begin
	reg old_toggle = 0;
	reg old_pal_toggle = 0;

	old_toggle <= video_toggle;
	old_pal_toggle <= palette_toggle;

	// display change request from keyboard
	if (video_toggle != old_toggle) begin
		screen_mode_req = screen_mode + 1'b1;
	end 
	
	// palette change request from keyboard
	if (palette_toggle != old_pal_toggle) begin
		palette_req = palette_mode + 1'b1;
		screen_mode_req = 2'b00; //force color when switching palettes
	end;
	
end

always @(posedge clk_sys) begin	
	// flag to enable Lo-Res text artifacting, only applicable in screen mode 2'b00
	text_color <= (~status[20] & ~status[19] & status[21]);
end  


apple2_top apple2_top
(
	.CLK_14M(clk_sys),
	.CLK_50M(CLK_50M),

	.CPU_WAIT(cpu_wait_hdd /*| cpu_wait_fdd*/),
	.cpu_type(active_cpu),
	.cpu_stall(osd_pause | ss_busy),

	.ss_addr(ss_addr),
	.ss_wdata(ss_wdata),
	.ss_wren(ss_wren),
	.ss_rdata(top_ss_rdata),
	.machine_ce(machine_ce),
	.cpu_frozen(cpu_frozen),

	.reset_cold(RESET | status[0]),
	.reset_warm(buttons[1] | virtual_keyboard_reset),
	.soft_reset(soft_reset),

	.hblank(HBlank),
	.vblank(VBlank),
	.hsync(HSync),
	.vsync(VSync),
	.r(core_R),
	.g(core_G),
	.b(core_B),
	.video_switch(video_toggle),
	.palette_switch(palette_toggle),
	.SCREEN_MODE( status[20:19] ),
	.TEXT_COLOR( text_color ),
	.COLOR_PALETTE(status[25:24]),
	.use_composite(status[4]),
	.comp_preset(status[2:1]),
	.comp_hfix(status[62]),
	.comp_hue_adj({1'b0, status[61:57]} << 1),
	.NTSC_VERTICAL_COMB(~status[32]),
	.PALMODE(status[22]),
	.ROMSWITCH(~status[23]),

	.AUDIO_L(core_audio_l),
	.AUDIO_R(core_audio_r),
	.TAPE_IN(tape_adc_act & tape_adc),

	.PS2_Key(core_ps2_key),
	.virtual_keyboard_active(virtual_keyboard_active),
	.virtual_keyboard_event(virtual_keyboard_event),
	.virtual_keyboard_pressed(virtual_keyboard_pressed),
	.virtual_keyboard_code(virtual_keyboard_code),
	.virtual_control(virtual_keyboard_control_active),
	.virtual_open_apple(virtual_open_apple),
	.virtual_closed_apple(virtual_closed_apple),

	.joy(core_joyd),
	.joy_an(core_joya),
	// Joy-to-key is disabled while the virtual keyboard is enabled: the user is
	// expected to type with the keyboard instead, so the joystick must not inject
	// keystrokes at the same time. The raw joystick (gameport) is unaffected.
	.JOY_TO_KEY_EN(status[43] && !virtual_keyboard_enabled),
	
	// WOZ SD block interface: hps_io channel 0 -> drive 1, channel 2 ->
	// drive 2 (channel 1 stays the HDD).  hps_io's streaming protocol is
	// exactly what the WOZ expects; sd_blk_cnt is left unconnected (0 =
	// single-block requests, which is all the WOZ issues).
	.SD_LBA0(sd_lba[0]),
	.SD_RD0(sd_rd[0]),
	.SD_WR0(sd_wr[0]),
	.SD_ACK0(sd_ack[0]),
	.SD_BUFF_DIN0(sd_buff_din[0]),
	.SD_LBA1(sd_lba[2]),
	.SD_RD1(sd_rd[2]),
	.SD_WR1(sd_wr[2]),
	.SD_ACK1(sd_ack[2]),
	.SD_BUFF_DIN1(sd_buff_din[2]),
	.SD_BUFF_ADDR(sd_buff_addr),
	.SD_BUFF_DOUT(sd_buff_dout),
	.SD_BUFF_WR(sd_buff_wr),
	.IMG_MOUNTED0(disk_mount[0]),
	.IMG_MOUNTED1(disk_mount[1]),
	.IMG_READONLY(img_readonly),
	.IMG_SIZE(img_size),

	.DISK_READY(DISK_READY),
	.D1_ACTIVE(D1_ACTIVE),
	.D2_ACTIVE(D2_ACTIVE),
	.D1_MOTOR_ON(D1_MOTOR_ON),
	.D2_MOTOR_ON(D2_MOTOR_ON),
	.D1_IO_ACTIVE(D1_IO_ACTIVE),
	.D2_IO_ACTIVE(D2_IO_ACTIVE),
	.D1_STEP_ACTIVE(D1_STEP_ACTIVE),
	.D2_STEP_ACTIVE(D2_STEP_ACTIVE),
	.D1_TRACK_ZERO_STEP(D1_TRACK_ZERO_STEP),
	.D2_TRACK_ZERO_STEP(D2_TRACK_ZERO_STEP),
	.DISK_ACT(led),

	.D1_WP(status[26]),
	.D2_WP(status[27]),

	.HDD_SECTOR(sd_lba[1]),
	.HDD_READ(hdd_read),
	.HDD_WRITE(hdd_write),
	.HDD_MOUNTED(hdd_mounted),
	.HDD_PROTECT(hdd_protect),
	.HDD_RAM_ADDR(sd_buff_addr),
	.HDD_RAM_DI(sd_buff_dout),
	.HDD_RAM_DO(sd_buff_din[1]),
	.HDD_RAM_WE(sd_buff_wr & sd_ack[1]),

	.ram_addr(ram_addr),
	.ram_do(ram_dout),
	.ram_di(ram_din),
	.ram_we(ram_we),
	.ram_aux(ram_aux),
	
	.ioctl_addr(ioctl_addr),
	.ioctl_data(ioctl_data),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),


	.UART_TXD(UART_TXD),
	.UART_RXD(UART_RXD),
	.UART_RTS(UART_RTS),
	.UART_CTS(UART_CTS),
	.UART_DTR(UART_DTR),
	.UART_DSR(UART_DSR),
	.RTC(RTC),
	
	.mouse_x(virtual_keyboard_active ? 9'sd0 : {ps2_mouse[4],ps2_mouse[15:8]}),
	.mouse_y(virtual_keyboard_active ? 9'sd0 : {ps2_mouse[5],ps2_mouse[23:16]}),
	.mouse_button(virtual_keyboard_active ? 1'b0 : ps2_mouse[0]),
	.mouse_strobe(virtual_keyboard_active ? 1'b0 : mouse_strobe),

	.mouse_4_inslot(mouse_4_inslot),
	.mouse_5_inslot(mouse_5_inslot),
	.mb_4_inslot(mb_4_inslot),
	.mb_5_inslot(mb_5_inslot),
	.saturn_5_inslot(saturn_5_inslot),
	.softcard_4_inslot(softcard_4_inslot)
);

wire [2:0] scale = status[11:9];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;
wire       scandoubler = (scale || forced_scandoubler);

assign VGA_SL = sl[1:0];

wire [7:0] core_R, core_G, core_B;
wire [7:0] R,G,B;
wire HSync, VSync, HBlank, VBlank;
wire [23:0] drive_overlay_rgb;
wire [6:0] virtual_font_character;
wire [2:0] virtual_font_row;
wire [7:0] virtual_font_data;
wire virtual_font_alternate;
wire virtual_font_lowercase;

// Floppy drive sound: DISABLED in the WOZ variant (user decision,
// 2026-09-08) - the flux drives expose no motor/step/track-zero signals.
// The instance is kept with all motion inputs tied off so it can be
// re-enabled trivially; it contributes silence.
floppy_sound floppy_sound
(
	.clk(clk_sys),
	.reset(RESET | status[0] | buttons[1] | virtual_keyboard_reset | soft_reset),
	.enable(1'b0),
	.gain(2'd0),
	.drive1_motor(1'b0),
	.drive2_motor(1'b0),
	.drive1_io(1'b0),
	.drive2_io(1'b0),
	.drive1_step(1'b0),
	.drive2_step(1'b0),
	.drive1_track_zero_step(1'b0),
	.drive2_track_zero_step(1'b0),
	.sample(floppy_audio)
);

drive_status_overlay drive_status_overlay
(
	.clk(clk_sys),
	.reset(RESET | status[0]),
	.enable(~status[35]),
	.hblank(HBlank),
	.vblank(VBlank),
	.rgb_in({core_R, core_G, core_B}),
	.drive1_motor(D1_ACTIVE),
	.drive1_activity(sd_rd[0] | sd_wr[0]),	// WOZ: activity = SD traffic
	.drive2_motor(D2_ACTIVE),
	.drive2_activity(sd_rd[2] | sd_wr[2]),
	.hdd_mounted(hdd_mounted),
	.hdd_activity(hdd_read | hdd_write),
	.rgb_out(drive_overlay_rgb)
);

apple2_font_rom apple2_font_rom
(
	.CLK_14M(clk_sys),
	.ROMSWITCH(~status[23]),
	.alternate_character(virtual_font_alternate),
	.lowercase_character(virtual_font_lowercase),
	.character_code(virtual_font_character),
	.glyph_row(virtual_font_row),
	.ioctl_addr(ioctl_addr),
	.ioctl_data(ioctl_data),
	.ioctl_wr(ioctl_wr),
	.glyph_data(virtual_font_data)
);

virtual_keyboard_overlay virtual_keyboard_overlay
(
	.clk(clk_sys),
	.reset(RESET | status[0]),
	.active(virtual_keyboard_active),
	.commands_page(virtual_keyboard_commands),
	.selected_row(virtual_keyboard_row),
	.selected_col(virtual_keyboard_col),
	.shift_latched(virtual_keyboard_shift_active),
	.control_latched(virtual_keyboard_control_active),
	.caps_latched(virtual_keyboard_caps),
	.open_apple(virtual_open_apple),
	.closed_apple(virtual_closed_apple),
	.transparency(virtual_keyboard_visibility),
	.overlay_top(virtual_keyboard_top),
	.pixel_clock_double(!status[16]),
	.hblank(HBlank),
	.vblank(VBlank),
	.rgb_in(drive_overlay_rgb),
	.font_alternate(virtual_font_alternate),
	.font_lowercase(virtual_font_lowercase),
	.font_character(virtual_font_character),
	.font_row(virtual_font_row),
	.font_data(virtual_font_data),
	.rgb_out({R, G, B})
);

video_mixer #(.LINE_LENGTH(580), .GAMMA(1)) video_mixer
(
	.*,
	.hq2x(scale==1),
	.freeze_sync()
);

wire [17:0] ram_addr;
reg  [15:0] ram_dout;
wire  [7:0]	ram_din;
wire        ram_we;
wire        ram_aux;

wire dd_reset = RESET | status[0] | buttons[1] | virtual_keyboard_reset | soft_reset;
wire ram_main_select = ram_addr[17:16] == 2'b00;
wire ram_machine_write = ram_we && !ss_busy;
wire [7:0] main_ram_q_a;
wire [7:0] main_ram_q_b;
wire [7:0] aux_ram_q_a;
wire [7:0] aux_ram_q_b;
wire [7:0] saturn_ram_q_a;

dpram #(16, 8) main_ram (
	.address_a(ram_addr[15:0]), .address_b(ram_ss_addr),
	.clock_a(clk_sys), .clock_b(clk_sys),
	.data_a(ram_din), .data_b(ram_ss_wdata),
	.enable_a(1'b1), .enable_b(1'b1),
	.wren_a(ram_machine_write && !ram_aux && ram_main_select),
	.wren_b(ram_ss_wr && !ram_ss_bank && !dd_reset),
	.q_a(main_ram_q_a), .q_b(main_ram_q_b)
);

dpram #(16, 8) aux_ram (
	.address_a(ram_addr[15:0]), .address_b(ram_ss_addr),
	.clock_a(clk_sys), .clock_b(clk_sys),
	.data_a(ram_din), .data_b(ram_ss_wdata),
	.enable_a(1'b1), .enable_b(1'b1),
	.wren_a(ram_machine_write && ram_aux),
	.wren_b(ram_ss_wr && ram_ss_bank && !dd_reset),
	.q_a(aux_ram_q_a), .q_b(aux_ram_q_b)
);

dpram #(17, 8) saturn_ram (
	.address_a(ram_addr[16:0]), .address_b(17'd0),
	.clock_a(clk_sys), .clock_b(clk_sys),
	.data_a(ram_din), .data_b(8'd0),
	.enable_a(1'b1), .enable_b(1'b0),
	.wren_a(ram_machine_write && !ram_aux && !ram_main_select),
	.wren_b(1'b0),
	.q_a(saturn_ram_q_a), .q_b()
);

always @(posedge clk_sys) begin
	ram_dout[7:0] <= ram_main_select ? main_ram_q_a : saturn_ram_q_a;
	ram_dout[15:8] <= aux_ram_q_a;
end

assign ram_ss_rdata = ram_ss_bank ? aux_ram_q_b : main_ram_q_b;
assign ss_rdata = (ss_addr == 10'd10) ? {63'd0, active_cpu} : top_ss_rdata;

// Save states are available only with Saturn out of slot 5 and no reset,
// download, or save-state transaction in flight. This gates the OSD command
// lines (status_menumask bit 7); the manager independently rejects.
savestate_ui savestate_ui (
	.clk(clk_sys),
	.reset(dd_reset),
	.allow_ss(!saturn_5_inslot && !softcard_4_inslot && !dd_reset && !ioctl_download && !ss_busy),
	.ss_busy(ss_busy),
	.ss_done(ss_done),
	.ss_error(ss_error),
	.ss_error_code(ss_error_code),
	.osd_slot(status[47:46]),
	.osd_save(status[48]),
	.osd_restore(status[49]),
	.hk_save(save_request),
	.hk_load(load_request),
	.ss_save_req(ui_save_req),
	.ss_load_req(ui_load_req),
	.ss_slot(ui_ss_slot),
	.info_req(ss_info_req),
	.info(ss_info),
	.status_menumask(ss_menumask)
);

savestate_manager state_manager (
	.clk(clk_sys), .reset(dd_reset),
	.request_save(ui_save_req), .request_load(ui_load_req),
	.allow_save_state(!saturn_5_inslot),
	.cpu_type(current_cpu), .cpu_frozen(cpu_frozen),
	.stall(), .machine_ce(machine_ce), .busy(ss_busy), .done(ss_done),
	.error(ss_error), .error_code(ss_error_code), .locked_cpu_type(ss_locked_cpu),
	.ss_addr(ss_addr), .ss_wdata(ss_wdata), .ss_wren(ss_wren), .ss_rdata(ss_rdata),
	.ram_bank(ram_ss_bank), .ram_addr(ram_ss_addr), .ram_rd(ram_ss_rd),
	.ram_wr(ram_ss_wr), .ram_wdata(ram_ss_wdata), .ram_rdata(ram_ss_rdata),
	.slot_addr(slot_addr), .slot_rd(slot_rd), .slot_wr(slot_wr),
	.slot_wdata(slot_wdata), .slot_rdata(slot_rdata), .slot_ready(slot_ready)
);

savestate_ddr #(.BASE_ADDR(29'h07C00000)) ddr_ss (
	.clk(clk_sys), .reset(dd_reset),
	.slot_addr(slot_addr), .slot_sel(ui_ss_slot), .slot_rd(slot_rd), .slot_wr(slot_wr),
	.slot_wdata(slot_wdata), .slot_rdata(slot_rdata), .slot_ready(slot_ready),
	.ddram_clk(DDRAM_CLK), .ddram_busy(DDRAM_BUSY),
	.ddram_burstcnt(DDRAM_BURSTCNT), .ddram_addr(DDRAM_ADDR),
	.ddram_dout(DDRAM_DOUT), .ddram_dout_ready(DDRAM_DOUT_READY),
	.ddram_rd(DDRAM_RD), .ddram_din(DDRAM_DIN), .ddram_be(DDRAM_BE),
	.ddram_we(DDRAM_WE)
);

reg  hdd_mounted = 0;
wire hdd_read;
wire hdd_write;
reg  hdd_protect;
reg  cpu_wait_hdd = 0;

always @(posedge clk_sys) begin
	reg state = 0;
	reg old_ack = 0;
	reg hdd_read_pending = 0;
	reg hdd_write_pending = 0;

	old_ack <= sd_ack[1];
	hdd_read_pending <= hdd_read_pending | hdd_read;
	hdd_write_pending <= hdd_write_pending | hdd_write;

	if (img_mounted[1]) begin
		hdd_mounted <= img_size != 0;
		hdd_protect <= img_readonly;
	end

	if(dd_reset) begin
		state <= 0;
		cpu_wait_hdd <= 0;
		hdd_read_pending <= 0;
		hdd_write_pending <= 0;
		sd_rd[1] <= 0;
		sd_wr[1] <= 0;
	end
	else if(!state) begin
		if (hdd_read_pending | hdd_write_pending) begin
			state <= 1;
			sd_rd[1] <= hdd_read_pending;
			sd_wr[1] <= hdd_write_pending;
			cpu_wait_hdd <= 1;
		end
	end
	else begin
		if (~old_ack & sd_ack[1]) begin
			hdd_read_pending <= 0;
			hdd_write_pending <= 0;
			sd_rd[1] <= 0;
			sd_wr[1] <= 0;
		end
		else if(old_ack & ~sd_ack[1]) begin
			state <= 0;
			cpu_wait_hdd <= 0;
		end
	end
end


// WOZ IMG_MOUNTED levels: latch the one-cycle hps_io mount pulse into a
// level (img_size != 0 = disk present).  The WOZ takes IMG_MOUNTED as a
// LEVEL that stays high while the image is mounted.
always @(posedge clk_sys) begin
	if (img_mounted[0])
		disk_mount[0] <= img_size != 0;
end
always @(posedge clk_sys) begin
	if (img_mounted[2])
		disk_mount[1] <= img_size != 0;
end
	
wire D1_ACTIVE,D2_ACTIVE;
wire D1_MOTOR_ON,D2_MOTOR_ON;
wire D1_IO_ACTIVE,D2_IO_ACTIVE;
wire D1_STEP_ACTIVE,D2_STEP_ACTIVE;
wire D1_TRACK_ZERO_STEP,D2_TRACK_ZERO_STEP;
wire [1:0] DISK_READY;	// unused in WOZ mode (no track buffer)
reg [1:0]disk_mount;



// WOZ variant: no floppy_track instances.  The hps_io SD channels 0 and 2
// feed the WOZ drives directly through the apple2_top SD ports above
// (the WOZ speaks the hps_io streaming protocol natively - no track
// buffer bridge needed).


wire tape_adc, tape_adc_act;
ltc2308_tape ltc2308_tape
(
	.clk(CLK_50M),
	.ADC_BUS(ADC_BUS),
	.dout(tape_adc),
	.active(tape_adc_act)
);

endmodule
