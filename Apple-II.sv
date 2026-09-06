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
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
 
assign LED_USER  = led;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;
assign VGA_SCALER= 0;
assign VGA_DISABLE = 0;
assign VGA_F1    = 0;
assign HDMI_FREEZE = 0;
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
	"Apple-II;UART19200:9600:4800:2400:1200:300;",
	"-;",
	"S0,NIBDSKDO PO ;",
	"S2,NIBDSKDO PO ;",
	"OQR,Write Protect,None,Drive 1,Drive 2,Drive 1 & 2;",
	"-;",
	"S1,HDV;",
	"-;",
	"OJK,Display,Color,B&W,Green,Amber;",
	"OOP,Color palette,NTSC //e,IIgs,AppleWin,Custom;",
	"FC2,A2P,Custom Palette;",	
	"-;",
	"P1,System & BIOS;",
	"P1-;",
	"P1O5,CPU,65C02,6502;",
	"P1OM,PAL Mode,NTSC,PAL;",
	"P1-;",
	"P1ON,Video Rom,US,LOCAL;",
	"P1F1,BIN,Load 8k Video ROM;", 
	"P1-;",
	"P1oA,Virtual keyboard,Off,On;",
	"P1o89,Keypad visibility,100%,75%,50%,25%;",
	"P1-;",
	"P2,Audio & Video;",
	"P2-;",	
	"P2O78,Stereo mix,none,25%,50%,100%;",
	"P2-;",	
	"P2OG,Pixel Clock,Double,Normal;",
	"P2OL,Lo-Res Text,Clean,Composite;",
	"P2O4,Color sharpness,RGB,Composite;",
	"P2o0,NTSC vertical blend,On,Off;",
	"P2-;",	
	"P2O9B,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;", 
	"P2OCD,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P2OEF,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
	"P2-;",	
	"P3,Hardware;",
	"P3-;",	
	"P3OST,Slot 4,Mocking board,Mouse,Empty;",
	"P3OUV,Slot 5,Mouse,Mocking board,256K Saturn,Empty;",
	"P3O6,Analog X/Y,Normal,Swapped;",
	"P3OHI,Paddle as analog,No,X,Y;",
	"P3o46,Analog X center,0,-16,-32,-48,-64,-72,+32,+48;",
	"P3o7,Joystick mode,Absolute,Relative;",
	"P3-;",	
	"P3o3,Disk LED overlay,Yes,No;",
	"P3o12,Disk drive sound,Off,On (1x),On (2x),On (4x);",
	"P3-;",
	"-;",
	"R0,Cold Reset;",
	"JA,Fire 1,Fire 2,Keyboard On,Keyb. visibility,Keyboard Enter,Keyboard Space;",
	"jn,A|P,B;",
	"jp,Y|P,B;",
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
	.joystick(joystick_0[9:0]),
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

hps_io #(.CONF_STR(CONF_STR), .VDNUM(3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status),
	.status_in({status[63:43],virtual_keyboard_enabled_toggle?~status[42]:status[42],virtual_keyboard_transparency_cycle?virtual_keyboard_transparency_req:status[41:40],status[39:26],palette_toggle?palette_req:status[25:24],status[23:21],video_toggle?screen_mode_req:status[20:19],status[18:0]}),
	.status_set(video_toggle || palette_toggle || virtual_keyboard_transparency_cycle || virtual_keyboard_enabled_toggle),
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

wire [15:0] joya;
wire  [5:0] joyd;
wire [15:0] core_joya = virtual_keyboard_active ? 16'h0000 : joya;
wire  [5:0] core_joyd = virtual_keyboard_active ? 6'h00 : joyd;

joystick_input joystick_input
(
	.clk(clk_sys),
	.reset(RESET | status[0] | buttons[1] | virtual_keyboard_reset | soft_reset),
	.joystick_digital(joystick_0),
	.joystick_analog(joystick_a0),
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
wire virtual_keyboard_enabled = status[42];
wire [1:0] virtual_keyboard_visibility = status[41:40];
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
	.cpu_type(~status[5]),

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
	.GRAY_SEAM_FIX(~status[4]),
	.SEAM_RUN_FILL(1'b1),
	.SEAM_RUN_WIDE(1'b0),
	.NTSC_VERTICAL_COMB(~status[32]),
	.PALMODE(status[22]),
	.ROMSWITCH(~status[23]),

	.AUDIO_L(core_audio_l),
	.AUDIO_R(core_audio_r),
	.TAPE_IN(tape_adc_act & tape_adc),

	.ps2_key(filtered_ps2_key),
	.virtual_keyboard_active(virtual_keyboard_active),
	.virtual_keyboard_event(virtual_keyboard_event),
	.virtual_keyboard_pressed(virtual_keyboard_pressed),
	.virtual_keyboard_code(virtual_keyboard_code),
	.virtual_control(virtual_keyboard_control_active),
	.virtual_open_apple(virtual_open_apple),
	.virtual_closed_apple(virtual_closed_apple),

	.joy(core_joyd),
	.joy_an(core_joya),
	
	.TRACK1(TRACK1),
	.TRACK1_ADDR(TRACK1_RAM_ADDR),
	.TRACK1_DI(TRACK1_RAM_DI),
	.TRACK1_DO (TRACK1_RAM_DO),
	.TRACK1_WE (TRACK1_RAM_WE),
	.TRACK1_BUSY (TRACK1_RAM_BUSY),
	//-- Track buffer interface disk 2
	.TRACK2(TRACK2),
	.TRACK2_ADDR(TRACK2_RAM_ADDR),
	.TRACK2_DI(TRACK2_RAM_DI),
	.TRACK2_DO (TRACK2_RAM_DO),
	.TRACK2_WE (TRACK2_RAM_WE),
	.TRACK2_BUSY (TRACK2_RAM_BUSY),

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
	.saturn_5_inslot(saturn_5_inslot)
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

floppy_sound floppy_sound
(
	.clk(clk_sys),
	.reset(RESET | status[0] | buttons[1] | virtual_keyboard_reset | soft_reset),
	.enable(status[34:33] != 2'd0),
	.gain(status[34:33] - 2'd1),
	.drive1_motor(D1_MOTOR_ON),
	.drive2_motor(D2_MOTOR_ON),
	.drive1_io(D1_IO_ACTIVE),
	.drive2_io(D2_IO_ACTIVE),
	.drive1_step(D1_STEP_ACTIVE),
	.drive2_step(D2_STEP_ACTIVE),
	.drive1_track_zero_step(D1_TRACK_ZERO_STEP),
	.drive2_track_zero_step(D2_TRACK_ZERO_STEP),
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
	.drive1_activity(D1_IO_ACTIVE),
	.drive2_motor(D2_ACTIVE),
	.drive2_activity(D2_IO_ACTIVE),
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

reg [7:0] ram0[196608];
always @(posedge clk_sys) begin
	if(ram_we & ~ram_aux) begin
		ram0[ram_addr] <= ram_din;
		ram_dout[7:0]  <= ram_din;
	end else begin
		ram_dout[7:0]  <= ram0[ram_addr];
	end
end

reg [7:0] ram1[65536];
always @(posedge clk_sys) begin
	if(ram_we & ram_aux) begin
		ram1[ram_addr[15:0]] <= ram_din;
		ram_dout[15:8] <= ram_din;
	end else begin
		ram_dout[15:8] <= ram1[ram_addr[15:0]];
	end
end

wire dd_reset = RESET | status[0] | buttons[1] | virtual_keyboard_reset | soft_reset;

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


always @(posedge clk_sys) begin
	if (img_mounted[0]) begin
		disk_mount[0] <= img_size != 0;
		DISK_CHANGE[0] <= ~DISK_CHANGE[0];
		//disk_protect <= img_readonly;
	end
end
always @(posedge clk_sys) begin
	if (img_mounted[2]) begin
		disk_mount[1] <= img_size != 0;
		DISK_CHANGE[1] <= ~DISK_CHANGE[1];
		//disk_protect <= img_readonly;
	end
end
	
wire D1_ACTIVE,D2_ACTIVE;
wire D1_MOTOR_ON,D2_MOTOR_ON;
wire D1_IO_ACTIVE,D2_IO_ACTIVE;
wire D1_STEP_ACTIVE,D2_STEP_ACTIVE;
wire D1_TRACK_ZERO_STEP,D2_TRACK_ZERO_STEP;
wire TRACK1_RAM_BUSY;
wire [12:0] TRACK1_RAM_ADDR;
wire [7:0] TRACK1_RAM_DI;
wire [7:0] TRACK1_RAM_DO;
wire TRACK1_RAM_WE;
wire [5:0] TRACK1;

wire TRACK2_RAM_BUSY;
wire [12:0] TRACK2_RAM_ADDR;
wire [7:0] TRACK2_RAM_DI;
wire [7:0] TRACK2_RAM_DO;
wire TRACK2_RAM_WE;
wire [5:0] TRACK2;

wire [1:0] DISK_READY;
reg [1:0] DISK_CHANGE;
reg [1:0]disk_mount;



floppy_track floppy_track_1
(
   .clk(clk_sys),
   .reset(dd_reset),
	
   .ram_addr(TRACK1_RAM_ADDR),
   .ram_di(TRACK1_RAM_DI),
   .ram_do(TRACK1_RAM_DO),
   .ram_we(TRACK1_RAM_WE),
	
   .track (TRACK1),
   .busy  (TRACK1_RAM_BUSY),
   .change(DISK_CHANGE[0]),
   .mount (disk_mount[0]),
   .ready  (DISK_READY[0]),
   .active (D1_ACTIVE),

   .sd_buff_addr (sd_buff_addr),
   .sd_buff_dout (sd_buff_dout),
   .sd_buff_din  (sd_buff_din[0]),
   .sd_buff_wr   (sd_buff_wr),

   .sd_lba       (sd_lba[0] ),
   .sd_rd        (sd_rd[0]),
   .sd_wr       ( sd_wr[0]),
   .sd_ack       (sd_ack[0])	
);


floppy_track floppy_track_2
(
   .clk(clk_sys),
   .reset(dd_reset),
	
   .ram_addr(TRACK2_RAM_ADDR),
   .ram_di(TRACK2_RAM_DI),
   .ram_do(TRACK2_RAM_DO),
   .ram_we(TRACK2_RAM_WE),
	
   .track (TRACK2),
   .busy  (TRACK2_RAM_BUSY),
   .change(DISK_CHANGE[1]),
   .mount (disk_mount[1]),
   .ready  (DISK_READY[1]),
   .active (D2_ACTIVE),

   .sd_buff_addr (sd_buff_addr),
   .sd_buff_dout (sd_buff_dout),
   .sd_buff_din  (sd_buff_din[2]),
   .sd_buff_wr   (sd_buff_wr),

   .sd_lba       (sd_lba[2] ),
   .sd_rd        (sd_rd[2]),
   .sd_wr       ( sd_wr[2]),
   .sd_ack       (sd_ack[2])	
);


wire tape_adc, tape_adc_act;
ltc2308_tape ltc2308_tape
(
	.clk(CLK_50M),
	.ADC_BUS(ADC_BUS),
	.dout(tape_adc),
	.active(tape_adc_act)
);

endmodule
