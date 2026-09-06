//
// Apple ][ floppy sound generator for MiSTer FPGA
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


module floppy_sound #(
	parameter integer MOTOR_NOISE_DIVIDER = 4096,
	parameter integer MOTOR_ENVELOPE_DIVIDER = 190909,
	parameter integer MOTOR_TONE_HALF_PERIOD = 16649,
	parameter integer SPINDLE_HALF_PERIOD = 1431818,
	parameter integer STEP_DECAY_DIVIDER = 2048,
	parameter integer STEP_RING_DECAY_DIVIDER = 24576,
	parameter integer IO_TEXTURE_DIVIDER = 4096,
	parameter integer IO_DECAY_DIVIDER = 4096,
	parameter integer IO_RETRIGGER_CYCLES = 4096,
	parameter integer MOTOR_LEVEL = 6,
	parameter integer MOTOR_TONE_LEVEL = 4,
	parameter integer STEP_LEVEL_SHIFT = 2,
	parameter integer STEP_RING_LEVEL_SHIFT = 2,
	parameter integer TRACK_ZERO_LEVEL_SHIFT = 3,
	parameter integer IO_LEVEL_SHIFT = 1
) (
	input  wire       clk,
	input  wire       reset,
	input  wire       enable,
	input  wire [1:0] gain,
	input  wire       drive1_motor,
	input  wire       drive2_motor,
	input  wire       drive1_io,
	input  wire       drive2_io,
	input  wire       drive1_step,
	input  wire       drive2_step,
	input  wire       drive1_track_zero_step,
	input  wire       drive2_track_zero_step,
	output reg  [9:0] sample
);

localparam integer MOTOR_DIVIDER_BITS = $clog2(MOTOR_NOISE_DIVIDER);
localparam integer MOTOR_ENVELOPE_DIVIDER_BITS = $clog2(MOTOR_ENVELOPE_DIVIDER);
localparam integer MOTOR_TONE_COUNTER_BITS = $clog2(MOTOR_TONE_HALF_PERIOD);
localparam integer SPINDLE_COUNTER_BITS = $clog2(SPINDLE_HALF_PERIOD);
localparam integer STEP_DIVIDER_BITS = $clog2(STEP_DECAY_DIVIDER);
localparam integer STEP_RING_DIVIDER_BITS = $clog2(STEP_RING_DECAY_DIVIDER);
localparam integer IO_TEXTURE_DIVIDER_BITS = $clog2(IO_TEXTURE_DIVIDER);
localparam integer IO_DIVIDER_BITS = $clog2(IO_DECAY_DIVIDER);
localparam integer IO_RETRIGGER_BITS = $clog2(IO_RETRIGGER_CYCLES + 1);

reg [MOTOR_DIVIDER_BITS-1:0] motor_divider = 0;
reg [MOTOR_ENVELOPE_DIVIDER_BITS-1:0] motor_envelope_divider = 0;
reg [MOTOR_TONE_COUNTER_BITS-1:0] motor_tone_counter = 0;
reg [SPINDLE_COUNTER_BITS-1:0] spindle_counter = 0;
reg [STEP_DIVIDER_BITS-1:0] step_divider = 0;
reg [STEP_RING_DIVIDER_BITS-1:0] step_ring_divider = 0;
reg [IO_TEXTURE_DIVIDER_BITS-1:0] io_texture_divider = 0;
reg [IO_DIVIDER_BITS-1:0] io_divider = 0;
reg [IO_RETRIGGER_BITS-1:0] drive1_io_cooldown = 0;
reg [IO_RETRIGGER_BITS-1:0] drive2_io_cooldown = 0;
reg [12:0] noise_lfsr = 13'h1FFF;
reg [3:0] motor_envelope = 0;
reg [3:0] drive1_step_envelope = 0;
reg [3:0] drive2_step_envelope = 0;
reg [2:0] drive1_step_ring = 0;
reg [2:0] drive2_step_ring = 0;
reg [2:0] drive1_stop_envelope = 0;
reg [2:0] drive2_stop_envelope = 0;
reg [2:0] drive1_io_envelope = 0;
reg [2:0] drive2_io_envelope = 0;
reg drive1_io_d = 0;
reg drive2_io_d = 0;
reg motor_tone_phase = 0;
reg spindle_phase = 0;
reg io_texture_phase = 0;

wire motor_running = drive1_motor | drive2_motor;
wire motor_audible = motor_running | (motor_envelope != 0);
wire drive1_io_event = drive1_io && !drive1_io_d;
wire drive2_io_event = drive2_io && !drive2_io_d;
wire [8:0] motor_level_product = ({5'd0, motor_envelope} * MOTOR_LEVEL[8:0]) +
	(spindle_phase ? motor_envelope : 4'd0);
wire [9:0] motor_sample = motor_audible && noise_lfsr[0] ?
	((motor_level_product + 9'd15) >> 4) : 10'd0;
wire [7:0] motor_tone_product = {4'd0, motor_envelope} * MOTOR_TONE_LEVEL[7:0];
wire [9:0] motor_tone_sample = motor_audible && motor_tone_phase ?
	((motor_tone_product + 8'd15) >> 4) : 10'd0;
wire drive1_track_zero_active = drive1_stop_envelope != 0;
wire drive2_track_zero_active = drive2_stop_envelope != 0;
wire [9:0] drive1_step_sample = !drive1_track_zero_active ?
	({6'd0, drive1_step_envelope} << STEP_LEVEL_SHIFT) : 10'd0;
wire [9:0] drive2_step_sample = !drive2_track_zero_active ?
	({6'd0, drive2_step_envelope} << STEP_LEVEL_SHIFT) : 10'd0;
wire [9:0] drive1_step_ring_sample = !drive1_track_zero_active && (noise_lfsr[4] ^ noise_lfsr[1]) ?
	({7'd0, drive1_step_ring} << STEP_RING_LEVEL_SHIFT) : 10'd0;
wire [9:0] drive2_step_ring_sample = !drive2_track_zero_active && (noise_lfsr[5] ^ noise_lfsr[2]) ?
	({7'd0, drive2_step_ring} << STEP_RING_LEVEL_SHIFT) : 10'd0;
wire [9:0] drive1_stop_sample = (noise_lfsr[6] ^ noise_lfsr[3]) ?
	({7'd0, drive1_stop_envelope} << TRACK_ZERO_LEVEL_SHIFT) : 10'd0;
wire [9:0] drive2_stop_sample = (noise_lfsr[7] ^ noise_lfsr[4]) ?
	({7'd0, drive2_stop_envelope} << TRACK_ZERO_LEVEL_SHIFT) : 10'd0;
wire [9:0] drive1_io_sample = io_texture_phase ? ({7'd0, drive1_io_envelope} << IO_LEVEL_SHIFT) : 10'd0;
wire [9:0] drive2_io_sample = !io_texture_phase ? ({7'd0, drive2_io_envelope} << IO_LEVEL_SHIFT) : 10'd0;
wire [10:0] mixed_sample = {1'b0, motor_sample} + {1'b0, motor_tone_sample} +
	{1'b0, drive1_step_sample} + {1'b0, drive2_step_sample} +
	{1'b0, drive1_step_ring_sample} + {1'b0, drive2_step_ring_sample} +
	{1'b0, drive1_stop_sample} + {1'b0, drive2_stop_sample} +
	{1'b0, drive1_io_sample} + {1'b0, drive2_io_sample};

always @(posedge clk) begin
	if(reset || !enable) begin
		motor_divider <= 0;
		motor_envelope_divider <= 0;
		motor_tone_counter <= 0;
		spindle_counter <= 0;
		step_divider <= 0;
		step_ring_divider <= 0;
		io_texture_divider <= 0;
		io_divider <= 0;
		drive1_io_cooldown <= 0;
		drive2_io_cooldown <= 0;
		noise_lfsr <= 13'h1FFF;
		motor_envelope <= 0;
		drive1_step_envelope <= 0;
		drive2_step_envelope <= 0;
		drive1_step_ring <= 0;
		drive2_step_ring <= 0;
		drive1_stop_envelope <= 0;
		drive2_stop_envelope <= 0;
		drive1_io_envelope <= 0;
		drive2_io_envelope <= 0;
		drive1_io_d <= 0;
		drive2_io_d <= 0;
		motor_tone_phase <= 0;
		spindle_phase <= 0;
		io_texture_phase <= 0;
	end else begin
		drive1_io_d <= drive1_io;
		drive2_io_d <= drive2_io;

		if(motor_audible) begin
			if(motor_divider == MOTOR_NOISE_DIVIDER - 1) begin
				motor_divider <= 0;
				noise_lfsr <= {noise_lfsr[11:0], noise_lfsr[12] ^ noise_lfsr[11] ^ noise_lfsr[10] ^ noise_lfsr[7]};
			end else begin
				motor_divider <= motor_divider + 1'd1;
			end
		end else begin
			motor_divider <= 0;
		end

		if((motor_running && motor_envelope != 4'hF) || (!motor_running && motor_envelope != 0)) begin
			if(motor_envelope_divider == MOTOR_ENVELOPE_DIVIDER - 1) begin
				motor_envelope_divider <= 0;
				if(motor_running)
					motor_envelope <= motor_envelope + 1'd1;
				else
					motor_envelope <= motor_envelope - 1'd1;
			end else begin
				motor_envelope_divider <= motor_envelope_divider + 1'd1;
			end
		end else begin
			motor_envelope_divider <= 0;
		end

		if(motor_audible) begin
			if(motor_tone_counter == MOTOR_TONE_HALF_PERIOD - 1) begin
				motor_tone_counter <= 0;
				motor_tone_phase <= ~motor_tone_phase;
			end else begin
				motor_tone_counter <= motor_tone_counter + 1'd1;
			end
		end else begin
			motor_tone_counter <= 0;
			motor_tone_phase <= 0;
		end

		if(motor_audible) begin
			if(spindle_counter == SPINDLE_HALF_PERIOD - 1) begin
				spindle_counter <= 0;
				spindle_phase <= ~spindle_phase;
			end else begin
				spindle_counter <= spindle_counter + 1'd1;
			end
		end else begin
			spindle_counter <= 0;
			spindle_phase <= 0;
		end

		if(drive1_step) begin
			drive1_step_envelope <= 4'hF;
			drive1_step_ring <= 3'h7;
		end
		if(drive2_step) begin
			drive2_step_envelope <= 4'hF;
			drive2_step_ring <= 3'h7;
		end
		if(drive1_track_zero_step) drive1_stop_envelope <= 3'h7;
		if(drive2_track_zero_step) drive2_stop_envelope <= 3'h7;

		if(step_divider == STEP_DECAY_DIVIDER - 1) begin
			step_divider <= 0;
			if(!drive1_step && drive1_step_envelope) drive1_step_envelope <= drive1_step_envelope - 1'd1;
			if(!drive2_step && drive2_step_envelope) drive2_step_envelope <= drive2_step_envelope - 1'd1;
		end else if(drive1_step_envelope || drive2_step_envelope) begin
			step_divider <= step_divider + 1'd1;
		end else begin
			step_divider <= 0;
		end

		if(step_ring_divider == STEP_RING_DECAY_DIVIDER - 1) begin
			step_ring_divider <= 0;
			if(!drive1_step && drive1_step_ring) drive1_step_ring <= drive1_step_ring - 1'd1;
			if(!drive2_step && drive2_step_ring) drive2_step_ring <= drive2_step_ring - 1'd1;
			if(!drive1_step && drive1_stop_envelope) drive1_stop_envelope <= drive1_stop_envelope - 1'd1;
			if(!drive2_step && drive2_stop_envelope) drive2_stop_envelope <= drive2_stop_envelope - 1'd1;
		end else if(drive1_step_ring || drive2_step_ring || drive1_stop_envelope || drive2_stop_envelope) begin
			step_ring_divider <= step_ring_divider + 1'd1;
		end else begin
			step_ring_divider <= 0;
		end

		if(drive1_io_envelope || drive2_io_envelope) begin
			if(io_texture_divider == IO_TEXTURE_DIVIDER - 1) begin
				io_texture_divider <= 0;
				io_texture_phase <= noise_lfsr[2] ^ noise_lfsr[5];
			end else begin
				io_texture_divider <= io_texture_divider + 1'd1;
			end
		end else begin
			io_texture_divider <= 0;
			io_texture_phase <= 0;
		end

		if(drive1_io_cooldown) drive1_io_cooldown <= drive1_io_cooldown - 1'd1;
		if(drive2_io_cooldown) drive2_io_cooldown <= drive2_io_cooldown - 1'd1;

		if(drive1_io_event && !drive1_io_cooldown) begin
			drive1_io_envelope <= 3'h7;
			drive1_io_cooldown <= IO_RETRIGGER_CYCLES[IO_RETRIGGER_BITS-1:0];
		end
		if(drive2_io_event && !drive2_io_cooldown) begin
			drive2_io_envelope <= 3'h7;
			drive2_io_cooldown <= IO_RETRIGGER_CYCLES[IO_RETRIGGER_BITS-1:0];
		end

		if(io_divider == IO_DECAY_DIVIDER - 1) begin
			io_divider <= 0;
			if(!(drive1_io_event && !drive1_io_cooldown) && drive1_io_envelope)
				drive1_io_envelope <= drive1_io_envelope - 1'd1;
			if(!(drive2_io_event && !drive2_io_cooldown) && drive2_io_envelope)
				drive2_io_envelope <= drive2_io_envelope - 1'd1;
		end else if(drive1_io_envelope || drive2_io_envelope) begin
			io_divider <= io_divider + 1'd1;
		end else begin
			io_divider <= 0;
		end
	end
end

always @(*) begin
	if(!enable || reset)
		sample = 10'd0;
	else if(mixed_sample > 11'd1023)
		sample = 10'h3FF;
	else if(gain == 2'd2 && mixed_sample > 11'd255)
		sample = 10'h3FF;
	else if(gain == 2'd2)
		sample = {mixed_sample[7:0], 2'b00};
	else if(gain == 2'd1 && mixed_sample > 11'd511)
		sample = 10'h3FF;
	else if(gain == 2'd1)
		sample = {mixed_sample[8:0], 1'b0};
	else
		sample = mixed_sample[9:0];
end

endmodule
