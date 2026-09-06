//
// Apple ][ joystick input handler for MiSTer FPGA
// Copyright (c) 2026 Newsdee
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

module joystick_input #(
	parameter integer RELATIVE_UPDATE_CYCLES = 143182
) (
	input  wire        clk,
	input  wire        reset,
	input  wire [15:0] joystick_digital,
	input  wire [15:0] joystick_analog,
	input  wire  [7:0] paddle,
	input  wire        swap_axes,
	input  wire        paddle_as_x,
	input  wire        paddle_as_y,
	input  wire  [2:0] x_center,
	input  wire        relative_mode,
	output wire [15:0] joy_an,
	output wire  [7:0] joy
);

localparam integer RELATIVE_UPDATE_BITS = $clog2(RELATIVE_UPDATE_CYCLES);

wire [7:0] paddle_value = {~paddle[7], paddle[6:0]};
wire [15:0] axes = swap_axes ? joystick_analog :
	{joystick_analog[7:0], joystick_analog[15:8]};
wire [15:0] absolute_untrimmed = {
	paddle_as_x ? paddle_value : axes[15:8],
	paddle_as_y ? paddle_value : axes[7:0]
};

reg signed [7:0] x_center_offset;
always @(*) begin
	case(x_center)
		3'd1: x_center_offset = -8'sd16;
		3'd2: x_center_offset = -8'sd32;
		3'd3: x_center_offset = -8'sd48;
		3'd4: x_center_offset = -8'sd64;
		3'd5: x_center_offset = -8'sd72;
		3'd6: x_center_offset =  8'sd32;
		3'd7: x_center_offset =  8'sd48;
		default: x_center_offset = 8'sd0;
	endcase
end

wire signed [8:0] absolute_x_adjusted =
	$signed({absolute_untrimmed[15], absolute_untrimmed[15:8]}) + x_center_offset;
wire [7:0] absolute_x = absolute_x_adjusted > 9'sd127 ? 8'h7F :
	absolute_x_adjusted < -9'sd128 ? 8'h80 : absolute_x_adjusted[7:0];
wire [15:0] absolute_axes = {absolute_x, absolute_untrimmed[7:0]};

reg [RELATIVE_UPDATE_BITS-1:0] relative_update_counter = 0;
reg signed [8:0] relative_x = 0;
reg signed [8:0] relative_y = 0;
reg relative_mode_d = 0;
reg signed [4:0] relative_x_delta;
reg signed [4:0] relative_y_delta;

always @(*) begin
	relative_x_delta = 5'sd0;
	relative_y_delta = 5'sd0;

	if(joystick_digital[0] && !joystick_digital[1])
		relative_x_delta = 5'sd3;
	else if(joystick_digital[1] && !joystick_digital[0])
		relative_x_delta = -5'sd3;
	else if($signed(axes[15:8]) > 8'sd112)
		relative_x_delta = 5'sd6;
	else if($signed(axes[15:8]) > 8'sd96)
		relative_x_delta = 5'sd5;
	else if($signed(axes[15:8]) > 8'sd80)
		relative_x_delta = 5'sd4;
	else if($signed(axes[15:8]) > 8'sd64)
		relative_x_delta = 5'sd3;
	else if($signed(axes[15:8]) > 8'sd40)
		relative_x_delta = 5'sd2;
	else if($signed(axes[15:8]) > 8'sd16)
		relative_x_delta = 5'sd1;
	else if($signed(axes[15:8]) < -8'sd112)
		relative_x_delta = -5'sd6;
	else if($signed(axes[15:8]) < -8'sd96)
		relative_x_delta = -5'sd5;
	else if($signed(axes[15:8]) < -8'sd80)
		relative_x_delta = -5'sd4;
	else if($signed(axes[15:8]) < -8'sd64)
		relative_x_delta = -5'sd3;
	else if($signed(axes[15:8]) < -8'sd40)
		relative_x_delta = -5'sd2;
	else if($signed(axes[15:8]) < -8'sd16)
		relative_x_delta = -5'sd1;

	if(joystick_digital[2] && !joystick_digital[3])
		relative_y_delta = 5'sd3;
	else if(joystick_digital[3] && !joystick_digital[2])
		relative_y_delta = -5'sd3;
	else if($signed(axes[7:0]) > 8'sd112)
		relative_y_delta = 5'sd6;
	else if($signed(axes[7:0]) > 8'sd96)
		relative_y_delta = 5'sd5;
	else if($signed(axes[7:0]) > 8'sd80)
		relative_y_delta = 5'sd4;
	else if($signed(axes[7:0]) > 8'sd64)
		relative_y_delta = 5'sd3;
	else if($signed(axes[7:0]) > 8'sd40)
		relative_y_delta = 5'sd2;
	else if($signed(axes[7:0]) > 8'sd16)
		relative_y_delta = 5'sd1;
	else if($signed(axes[7:0]) < -8'sd112)
		relative_y_delta = -5'sd6;
	else if($signed(axes[7:0]) < -8'sd96)
		relative_y_delta = -5'sd5;
	else if($signed(axes[7:0]) < -8'sd80)
		relative_y_delta = -5'sd4;
	else if($signed(axes[7:0]) < -8'sd64)
		relative_y_delta = -5'sd3;
	else if($signed(axes[7:0]) < -8'sd40)
		relative_y_delta = -5'sd2;
	else if($signed(axes[7:0]) < -8'sd16)
		relative_y_delta = -5'sd1;
end

wire signed [9:0] relative_x_next =
	{relative_x[8], relative_x} + {{5{relative_x_delta[4]}}, relative_x_delta};
wire signed [9:0] relative_y_next =
	{relative_y[8], relative_y} + {{5{relative_y_delta[4]}}, relative_y_delta};
wire signed [8:0] relative_x_output = relative_x[8] ?
	(relative_x + 9'sd1) >>> 1 : relative_x >>> 1;
wire signed [8:0] relative_y_output = relative_y[8] ?
	(relative_y + 9'sd1) >>> 1 : relative_y >>> 1;

always @(posedge clk) begin
	relative_mode_d <= relative_mode;

	if(reset || (relative_mode && !relative_mode_d)) begin
		relative_update_counter <= 0;
		relative_x <= 0;
		relative_y <= 0;
	end else if(relative_mode) begin
		if(relative_update_counter == RELATIVE_UPDATE_CYCLES - 1) begin
			relative_update_counter <= 0;
			relative_x <= relative_x_next > 10'sd254 ? 9'sh0FE :
				relative_x_next < -10'sd256 ? 9'sh100 : relative_x_next[8:0];
			relative_y <= relative_y_next > 10'sd254 ? 9'sh0FE :
				relative_y_next < -10'sd256 ? 9'sh100 : relative_y_next[8:0];
		end else begin
			relative_update_counter <= relative_update_counter + 1'd1;
		end
	end else begin
		relative_update_counter <= 0;
	end
end

assign joy_an = relative_mode ?
	{relative_x_output[7:0], relative_y_output[7:0]} : absolute_axes;
assign joy = joystick_digital[7:0] &
	{2'b11, 2'b11, {2{~|axes[7:0]}}, {2{~|axes[15:8]}}};

endmodule
