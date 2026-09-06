//
// Apple ][ drive status overlay for MiSTer FPGA
//
// Based on the work of
// Copyright (c) 2016 Sorgelig
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
/////////////////////////////////////////////////////////////////////////

module drive_status_overlay #(
	parameter integer LED_X = 538,
	parameter integer LED_Y = 182,
	parameter integer LED_WIDTH = 2,
	parameter integer LED_HEIGHT = 2,
	parameter integer LED_SPACING = 2,
	parameter integer ACTIVITY_HOLD_CYCLES = 715909,
	parameter [23:0] FLOPPY_DIM_COLOR = 24'h500000,
	parameter [23:0] FLOPPY_BRIGHT_COLOR = 24'hFF1808,
	parameter [23:0] HDD_DIM_COLOR = 24'h005000,
	parameter [23:0] HDD_BRIGHT_COLOR = 24'h18FF08
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        enable,
	input  wire        hblank,
	input  wire        vblank,
	input  wire [23:0] rgb_in,
	input  wire        drive1_motor,
	input  wire        drive1_activity,
	input  wire        drive2_motor,
	input  wire        drive2_activity,
	input  wire        hdd_mounted,
	input  wire        hdd_activity,
	output reg  [23:0] rgb_out
);

localparam integer ACTIVITY_HOLD_BITS = $clog2(ACTIVITY_HOLD_CYCLES + 1);
localparam [ACTIVITY_HOLD_BITS-1:0] ACTIVITY_HOLD_VALUE =
	ACTIVITY_HOLD_CYCLES[ACTIVITY_HOLD_BITS-1:0];
localparam integer DRIVE2_LED_X = LED_X + LED_WIDTH + LED_SPACING;
localparam integer HDD_LED_X = DRIVE2_LED_X + LED_WIDTH + LED_SPACING;

reg [9:0] video_x = 0;
reg [8:0] video_y = 0;
reg hblank_d = 1;
reg [ACTIVITY_HOLD_BITS-1:0] drive1_activity_hold = 0;
reg [ACTIVITY_HOLD_BITS-1:0] drive2_activity_hold = 0;
reg [ACTIVITY_HOLD_BITS-1:0] hdd_activity_hold = 0;

wire drive1_led_pixel = !hblank && !vblank &&
	(video_x >= LED_X) && (video_x < LED_X + LED_WIDTH) &&
	(video_y >= LED_Y) && (video_y < LED_Y + LED_HEIGHT);
wire drive2_led_pixel = !hblank && !vblank &&
	(video_x >= DRIVE2_LED_X) && (video_x < DRIVE2_LED_X + LED_WIDTH) &&
	(video_y >= LED_Y) && (video_y < LED_Y + LED_HEIGHT);
wire hdd_led_pixel = !hblank && !vblank &&
	(video_x >= HDD_LED_X) && (video_x < HDD_LED_X + LED_WIDTH) &&
	(video_y >= LED_Y) && (video_y < LED_Y + LED_HEIGHT);

always @(posedge clk) begin
	hblank_d <= hblank;

	if(reset || vblank) begin
		video_x <= 0;
		video_y <= 0;
	end else begin
		if(hblank) video_x <= 0;
		else video_x <= video_x + 1'd1;

		if(!hblank_d && hblank) video_y <= video_y + 1'd1;
	end

	if(reset) begin
		drive1_activity_hold <= 0;
		drive2_activity_hold <= 0;
		hdd_activity_hold <= 0;
	end else begin
		if(drive1_activity) drive1_activity_hold <= ACTIVITY_HOLD_VALUE;
		else if(drive1_activity_hold) drive1_activity_hold <= drive1_activity_hold - 1'd1;

		if(drive2_activity) drive2_activity_hold <= ACTIVITY_HOLD_VALUE;
		else if(drive2_activity_hold) drive2_activity_hold <= drive2_activity_hold - 1'd1;

		if(hdd_activity) hdd_activity_hold <= ACTIVITY_HOLD_VALUE;
		else if(hdd_activity_hold) hdd_activity_hold <= hdd_activity_hold - 1'd1;
	end
end

always @(*) begin
	rgb_out = rgb_in;
	if(enable && drive1_led_pixel && drive1_motor)
		rgb_out = drive1_activity_hold ? FLOPPY_BRIGHT_COLOR : FLOPPY_DIM_COLOR;
	else if(enable && drive2_led_pixel && drive2_motor)
		rgb_out = drive2_activity_hold ? FLOPPY_BRIGHT_COLOR : FLOPPY_DIM_COLOR;
	else if(enable && hdd_led_pixel && hdd_mounted)
		rgb_out = hdd_activity_hold ? HDD_BRIGHT_COLOR : HDD_DIM_COLOR;
end

endmodule
