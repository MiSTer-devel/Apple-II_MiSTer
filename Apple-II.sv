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
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output  [1:0] VGA_SL,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;
assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_DIN, DDRAM_BE, DDRAM_RD, DDRAM_WE} = 0;
 
assign LED_USER  = led;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

assign VIDEO_ARX = status[1] ? 8'd16 : 8'd4;
assign VIDEO_ARY = status[1] ? 8'd9  : 8'd3; 
assign VGA_SL = 0;
assign VGA_F1 = 0;

`include "build_id.v" 
parameter CONF_STR = {
	"Apple-II;;",
	"-;",
	"S,NIB;",
	"-;",
	"O1,Aspect ratio,4:3,16:9;",
	"O23,Display,Color,B&W,Green,Amber;",
	"-;",
	"O4,Mocking board,Yes,No;",
	"O78,Stereo mix,none,25%,50%,100%;",
	"-;",
	"R6,Reset;",
	"J,Fire 1,Fire 2;",
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

wire clk_sys, clk_vid;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid),
	.outclk_1(clk_sys)
);

/////////////////  HPS  ///////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joystick_a0, joystick_a1;

wire  [5:0] joy = (joystick_0[5:0] | joystick_1[5:0]) & {2'b11, {4{~joya_en}}};
wire [15:0] joya = joystick_a0 ? joystick_a0 : joystick_a1;
wire        joya_en = |joya;


wire [10:0] ps2_key;

reg  [31:0] sd_lba;
reg         sd_rd;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire        sd_buff_wr;
wire        img_mounted;
wire [63:0] img_size;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(0),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(0),
	.sd_buff_wr(sd_buff_wr),
	.img_mounted(img_mounted),
	.img_size(img_size),

	.ioctl_wait(0),

	.ps2_key(ps2_key),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_analog_0(joystick_a0),
	.joystick_analog_1(joystick_a1)
);

/////////////////  RESET  /////////////////////////

wire reset = RESET | status[0] | buttons[1] | status[6];

///////////////////////////////////////////////////

wire [7:0] audio_l, audio_r;
wire speaker;

assign AUDIO_L = {1'b0, audio_l, 7'd0} + {2'b0, speaker, 13'd0};
assign AUDIO_R = {1'b0, audio_r, 7'd0} + {2'b0, speaker, 13'd0};
assign AUDIO_S = 0;
assign AUDIO_MIX = status[8:7];

assign CLK_VIDEO = clk_vid;
assign CE_PIXEL = ce_pix;

reg ce_pix;
always @(posedge CLK_VIDEO) begin
	reg [1:0] div = 0;
	
	div <= div + 1'd1;
	ce_pix <= !div;
end

wire led;
apple2_top apple2_top
(
	.CLK_14M(clk_sys),
	.CPU_WAIT(cpu_wait),

	.reset_in(reset),

	.VGA_DE(VGA_DE),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.SCREEN_MODE(status[3:2]),

	.AUDIO_L(audio_l),
	.AUDIO_R(audio_r),
	.SPEAKER(speaker),

	.ps2_key(ps2_key),

	.joy(joy),
	.joy_an(joya),

	.mb_enabled(~status[4]),

	
	.TRACK(track),
	.TRACK_RAM_ADDR({track_sec, sd_buff_addr}),
	.TRACK_RAM_DI(sd_buff_dout),
	.TRACK_RAM_WE(sd_buff_wr),

	.ram_addr(ram_addr),
	.ram_dout(ram_dout),
	.ram_din(ram_din),
	.ram_we(ram_we),

	.LED(led)
);

wire [17:0] ram_addr;
reg   [7:0] ram_dout;
wire  [7:0]	ram_din;
wire        ram_we;

reg [7:0] ram[262144]; //om-nom-nom :)
always @(posedge clk_sys) begin
	if(ram_we) begin
		ram[ram_addr] <= ram_din;
		ram_dout <= ram_din;
	end else begin
		ram_dout <= ram[ram_addr];
	end
end

wire [5:0] track;
reg  [3:0] track_sec;
reg        cpu_wait = 0;

always @(posedge clk_sys) begin
	reg [2:0] state = 0;
	reg [5:0] cur_track;
	reg       mounted = 0;
	reg       old_ack = 0;
	
	old_ack <= sd_ack;
	mounted <= mounted | img_mounted;
	
	case(state)
		0: if((cur_track != track) || (mounted && ~img_mounted)) begin
				cur_track <= track;
				mounted <= 0;
				if(img_size) begin
					track_sec <= 0;
					sd_lba <= 13 * track;
					state <= 1;
					sd_rd <= 1;
					cpu_wait <= 1;
				end
			end
			
		1: if(~old_ack & sd_ack) begin
				if(track_sec >= 12) sd_rd <= 0;
				sd_lba <= sd_lba + 1'd1;
			end else if(old_ack & ~sd_ack) begin
				track_sec <= track_sec + 1'd1;
				if(~sd_rd) state <= 0;
				cpu_wait <= 0;
			end
	endcase
end

endmodule
