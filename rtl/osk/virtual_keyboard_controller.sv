module virtual_keyboard_controller #(
	parameter integer RESET_CYCLES = 1024,
	parameter integer BUTTON_HOLD_CYCLES = 65536,
	parameter integer CLK_HZ = 14318181,
	parameter integer INITIAL_DELAY_MS = 500,
	parameter integer REPEAT_INTERVAL_1_MS = 160,
	parameter integer REPEAT_INTERVAL_2_MS = 90,
	parameter integer REPEAT_INTERVAL_3_MS = 50,
	parameter integer STAGE2_AFTER_MS = 900,
	parameter integer STAGE3_AFTER_MS = 1600,
	parameter integer SNAP_AFTER_MS = 2200,
	parameter bit SNAP_ENABLED = 1,
	parameter bit WRAP = 0,
	parameter bit DIAGONAL_LOCKED = 1
) (
	input  wire        clk,
	input  wire        reset,
	input  wire [10:0] ps2_key,
	input  wire [10:0] joystick,
	input  wire        enabled,
	output reg  [10:0] filtered_ps2_key = 0,
	output reg         active = 0,
	output reg         commands_page = 0,
	output reg  [2:0]  selected_row = 1,
	output reg  [3:0]  selected_col = 1,
	output reg         shift_latched = 0,
	output reg         control_latched = 0,
	output reg         caps_latched = 1,
	output wire        shift_active,
	output wire        control_active,
	output reg         enabled_toggle = 0,
	output reg         open_apple = 0,
	output reg         closed_apple = 0,
	output reg         transparency_cycle = 0,
	output reg         overlay_top = 0,
	output reg         virtual_event = 0,
	output reg         virtual_pressed = 0,
	output reg  [6:0]  virtual_code = 0,
	output reg         command_reset = 0
);

localparam [7:0] SC_F10   = 8'h09;
localparam [7:0] SC_ESC   = 8'h76;
localparam [7:0] SC_ENTER = 8'h5A;
localparam [7:0] SC_UP    = 8'h75;
localparam [7:0] SC_DOWN  = 8'h72;
localparam [7:0] SC_LEFT  = 8'h6B;
localparam [7:0] SC_RIGHT = 8'h74;
localparam [7:0] SC_PAGE_UP = 8'h7D;
localparam [7:0] SC_PAGE_DOWN = 8'h7A;
localparam [7:0] SC_LEFT_SHIFT = 8'h12;
localparam [7:0] SC_RIGHT_SHIFT = 8'h59;
localparam [7:0] SC_CTRL = 8'h14;
localparam [7:0] SC_CAPS = 8'h58;

localparam [2:0] CMD_NONE = 0;
localparam [2:0] CMD_WARM = 1;
localparam [2:0] CMD_COLD = 2;
localparam [2:0] CMD_TEST = 3;

localparam [2:0] DIR_NONE  = 0;
localparam [2:0] DIR_RIGHT = 1;
localparam [2:0] DIR_LEFT  = 2;
localparam [2:0] DIR_DOWN  = 3;
localparam [2:0] DIR_UP    = 4;

localparam [2:0] SOURCE_NONE   = 0;
localparam [2:0] SOURCE_SELECT = 1;
localparam [2:0] SOURCE_BACK   = 2;
localparam [2:0] SOURCE_ENTER  = 3;
localparam [2:0] SOURCE_SPACE  = 4;

localparam integer RESET_BITS = $clog2(RESET_CYCLES + 1);
localparam integer HOLD_BITS = $clog2(BUTTON_HOLD_CYCLES + 1);
localparam integer CYCLES_PER_MS = CLK_HZ / 1000;
localparam integer MS_DIVIDER_BITS = $clog2(CYCLES_PER_MS + 1);
localparam [MS_DIVIDER_BITS-1:0] MS_DIVIDER_MAX =
	CYCLES_PER_MS[MS_DIVIDER_BITS-1:0] - 1'b1;
localparam [RESET_BITS-1:0] RESET_COUNT_VALUE = RESET_CYCLES[RESET_BITS-1:0];
localparam [HOLD_BITS-1:0] HOLD_COUNT_VALUE = BUTTON_HOLD_CYCLES[HOLD_BITS-1:0];

reg raw_toggle = 0;
reg virtual_key_down = 0;
reg [RESET_BITS-1:0] reset_counter = 0;
reg [HOLD_BITS-1:0] hold_counter = 0;
reg [2:0] command = CMD_NONE;
reg [6:0] joystick_buttons_d = 0;
reg [2:0] virtual_key_source = SOURCE_NONE;
reg enabled_d = 0;
reg physical_left_shift = 0;
reg physical_right_shift = 0;
reg physical_control = 0;
reg [MS_DIVIDER_BITS-1:0] ms_divider = 0;
reg [2:0] direction = DIR_NONE;
reg first_step_done = 0;
reg repeat_active = 0;
reg [31:0] hold_elapsed_ms = 0;
reg [31:0] step_elapsed_ms = 0;
reg [1:0] repeat_stage = 0;
reg snapped = 0;
reg back_repeat_active = 0;
reg [31:0] back_hold_elapsed_ms = 0;
reg [31:0] back_step_elapsed_ms = 0;
reg [1:0] back_repeat_stage = 0;

wire new_event = ps2_key[10] != raw_toggle;
wire joystick_fire_pressed = joystick[4] && !joystick_buttons_d[0];
wire joystick_fire_released = !joystick[4] && joystick_buttons_d[0];
wire visibility_pressed = joystick[6] && !joystick_buttons_d[2];
wire transparency_pressed = joystick[7] && !joystick_buttons_d[3];
wire move_pressed = joystick[8] && !joystick_buttons_d[4];
wire enter_pressed = joystick[9] && !joystick_buttons_d[5];
wire enter_released = !joystick[9] && joystick_buttons_d[5];
wire space_pressed = joystick[10] && !joystick_buttons_d[6];
wire space_released = !joystick[10] && joystick_buttons_d[6];
wire key_down = ps2_key[9];
wire extended = ps2_key[8];
wire [7:0] scan_code = ps2_key[7:0];
wire millisecond_tick = ms_divider == MS_DIVIDER_MAX;

function automatic [2:0] requested_direction(input [3:0] directions);
	begin
		if(directions[0]) requested_direction = DIR_RIGHT;
		else if(directions[1]) requested_direction = DIR_LEFT;
		else if(directions[2]) requested_direction = DIR_DOWN;
		else if(directions[3]) requested_direction = DIR_UP;
		else requested_direction = DIR_NONE;
	end
endfunction

function automatic direction_held(input [2:0] held_direction, input [3:0] directions);
	begin
		case(held_direction)
			DIR_RIGHT: direction_held = directions[0];
			DIR_LEFT: direction_held = directions[1];
			DIR_DOWN: direction_held = directions[2];
			DIR_UP: direction_held = directions[3];
			default: direction_held = 0;
		endcase
	end
endfunction

wire [2:0] next_direction = requested_direction(joystick[3:0]);
wire locked_direction_held = direction_held(direction, joystick[3:0]);
wire direction_press = active && next_direction != DIR_NONE &&
	(direction == DIR_NONE || !locked_direction_held ||
	 (!DIAGONAL_LOCKED && next_direction != direction));
wire [31:0] next_hold_elapsed_ms = hold_elapsed_ms + 1'd1;
wire [31:0] next_step_elapsed_ms = step_elapsed_ms + 1'd1;
wire [1:0] effective_repeat_stage = next_hold_elapsed_ms >= STAGE3_AFTER_MS ? 3 :
	next_hold_elapsed_ms >= STAGE2_AFTER_MS ? 2 : repeat_stage;
wire [31:0] navigation_interval_ms = effective_repeat_stage == 3 ? REPEAT_INTERVAL_3_MS :
	effective_repeat_stage == 2 ? REPEAT_INTERVAL_2_MS : REPEAT_INTERVAL_1_MS;
wire navigation_snap_due = millisecond_tick && locked_direction_held && SNAP_ENABLED &&
	!snapped && next_hold_elapsed_ms >= SNAP_AFTER_MS;
wire navigation_first_repeat_due = millisecond_tick && locked_direction_held &&
	first_step_done && !repeat_active && next_hold_elapsed_ms >= INITIAL_DELAY_MS;
wire navigation_repeat_due = millisecond_tick && locked_direction_held && repeat_active &&
	first_step_done && !snapped && next_step_elapsed_ms >= navigation_interval_ms;
wire navigation_step = direction_press || navigation_snap_due ||
	navigation_first_repeat_due || navigation_repeat_due;
wire [2:0] navigation_direction = direction_press ? next_direction : direction;
wire navigation_right = navigation_step && navigation_direction == DIR_RIGHT;
wire navigation_left = navigation_step && navigation_direction == DIR_LEFT;
wire navigation_down = navigation_step && navigation_direction == DIR_DOWN;
wire navigation_up = navigation_step && navigation_direction == DIR_UP;

wire [31:0] next_back_hold_elapsed_ms = back_hold_elapsed_ms + 1'd1;
wire [31:0] next_back_step_elapsed_ms = back_step_elapsed_ms + 1'd1;
wire [1:0] effective_back_repeat_stage = next_back_hold_elapsed_ms >= STAGE3_AFTER_MS ? 3 :
	next_back_hold_elapsed_ms >= STAGE2_AFTER_MS ? 2 : back_repeat_stage;
wire [31:0] back_interval_ms = effective_back_repeat_stage == 3 ? REPEAT_INTERVAL_3_MS :
	effective_back_repeat_stage == 2 ? REPEAT_INTERVAL_2_MS : REPEAT_INTERVAL_1_MS;
wire back_pressed = active && joystick[5] && !joystick_buttons_d[1];
wire back_released = !joystick[5] && joystick_buttons_d[1];
wire back_first_repeat_due = millisecond_tick && joystick[5] && !back_repeat_active &&
	next_back_hold_elapsed_ms >= INITIAL_DELAY_MS;
wire back_repeat_due = millisecond_tick && joystick[5] && back_repeat_active &&
	next_back_step_elapsed_ms >= back_interval_ms;
wire back_step = back_pressed || back_first_repeat_due || back_repeat_due;

assign shift_active = shift_latched | physical_left_shift | physical_right_shift;
assign control_active = control_latched | physical_control;

function automatic [3:0] row_last_col(input [2:0] row);
	case(row)
		0: row_last_col = 14;
		1: row_last_col = 13;
		2: row_last_col = 13;
		3: row_last_col = 12;
		default: row_last_col = 8;
	endcase
endfunction

function automatic [3:0] row_snap_down_col(input [2:0] row, input [3:0] col);
	begin
		if(row == 4) row_snap_down_col = col;
		else if((row == 0 && col == 14) || (row == 2 && col == 13)) row_snap_down_col = 8;
		else if(col <= 2) row_snap_down_col = col;
		else if(col <= 7) row_snap_down_col = 2;
		else if(col <= 11) row_snap_down_col = 8;
		else row_snap_down_col = 7;
	end
endfunction

function automatic [3:0] row_snap_up_col(input [2:0] row, input [3:0] col);
	begin
		if(row == 2 && col == 13) row_snap_up_col = 14;
		else if(row == 4) begin
			case(col)
				1: row_snap_up_col = 2;
				2: row_snap_up_col = 6;
				3: row_snap_up_col = 8;
				4: row_snap_up_col = 9;
				5: row_snap_up_col = 10;
				6: row_snap_up_col = 11;
				7: row_snap_up_col = 12;
				8: row_snap_up_col = 14;
				default: row_snap_up_col = 0;
			endcase
		end else row_snap_up_col = col;
	end
endfunction

function automatic [7:0] normal_code(input [2:0] row, input [3:0] col);
	begin
		normal_code = 0;
		case(row)
			0: case(col)
				0: normal_code = 7'h1B;
				1: normal_code = "1"; 2: normal_code = "2";
				3: normal_code = "3"; 4: normal_code = "4";
				5: normal_code = "5"; 6: normal_code = "6";
				7: normal_code = "7"; 8: normal_code = "8";
				9: normal_code = "9"; 10: normal_code = "0";
				11: normal_code = "-"; 12: normal_code = "=";
				13: normal_code = 7'h7F;
				default: normal_code = 0;
			endcase
			1: case(col)
				0: normal_code = 7'h09;
				1: normal_code = "Q"; 2: normal_code = "W";
				3: normal_code = "E"; 4: normal_code = "R";
				5: normal_code = "T"; 6: normal_code = "Y";
				7: normal_code = "U"; 8: normal_code = "I";
				9: normal_code = "O"; 10: normal_code = "P";
				11: normal_code = "["; 12: normal_code = "]";
				13: normal_code = 7'h0D;
			endcase
			2: case(col)
				1: normal_code = "A"; 2: normal_code = "S";
				3: normal_code = "D"; 4: normal_code = "F";
				5: normal_code = "G"; 6: normal_code = "H";
				7: normal_code = "J"; 8: normal_code = "K";
				9: normal_code = "L"; 10: normal_code = ";";
				11: normal_code = "'"; 12: normal_code = 8'h60;
				default: normal_code = 0;
			endcase
			3: case(col)
				1: normal_code = 7'h5C;
				2: normal_code = "Z"; 3: normal_code = "X";
				4: normal_code = "C"; 5: normal_code = "V";
				6: normal_code = "B"; 7: normal_code = "N";
				8: normal_code = "M"; 9: normal_code = ",";
				10: normal_code = "."; 11: normal_code = "/";
				default: normal_code = 0;
			endcase
			4: case(col)
				2: normal_code = 7'h20;
				4: normal_code = 7'h08;
				5: normal_code = 7'h15;
				6: normal_code = 7'h0A;
				7: normal_code = 7'h0B;
				default: normal_code = 0;
			endcase
		endcase
	end
endfunction

function automatic [7:0] shifted_code(input [2:0] row, input [3:0] col);
	begin
		shifted_code = normal_code(row, col);
		if(row == 0) begin
			case(col)
				1: shifted_code = "!"; 2: shifted_code = "@";
				3: shifted_code = "#"; 4: shifted_code = "$";
				5: shifted_code = "%"; 6: shifted_code = "^";
				7: shifted_code = "&"; 8: shifted_code = "*";
				9: shifted_code = "("; 10: shifted_code = ")";
				11: shifted_code = "_"; 12: shifted_code = "+";
			endcase
		end else if(row == 1) begin
			if(col == 11) shifted_code = "{";
			else if(col == 12) shifted_code = "}";
		end else if(row == 2) begin
			if(col == 10) shifted_code = ":";
			else if(col == 11) shifted_code = 7'h22;
			else if(col == 12) shifted_code = "~";
		end else if(row == 3) begin
			if(col == 1) shifted_code = "|";
			else if(col == 9) shifted_code = "<";
			else if(col == 10) shifted_code = ">";
			else if(col == 11) shifted_code = "?";
		end
	end
endfunction

function automatic is_letter(input [7:0] code);
	is_letter = code >= "A" && code <= "Z";
endfunction

task automatic release_virtual_key;
	begin
		if(virtual_key_down) begin
			virtual_pressed <= 0;
			virtual_event <= ~virtual_event;
			virtual_key_down <= 0;
			virtual_key_source <= SOURCE_NONE;
		end
	end
endtask

task automatic press_virtual_key(input [6:0] code, input [2:0] source);
	begin
		virtual_code <= code;
		virtual_pressed <= 1;
		virtual_event <= ~virtual_event;
		virtual_key_down <= 1;
		virtual_key_source <= source;
	end
endtask

task automatic close_overlay;
	begin
		if(virtual_key_source == SOURCE_SELECT || virtual_key_source == SOURCE_BACK)
			release_virtual_key();
		active <= 0;
		commands_page <= 0;
		shift_latched <= 0;
		control_latched <= 0;
		open_apple <= 0;
		closed_apple <= 0;
	end
endtask

task automatic open_overlay;
	begin
		active <= 1;
		commands_page <= 0;
		selected_row <= 1;
		selected_col <= 1;
		shift_latched <= 0;
		control_latched <= 0;
		open_apple <= 0;
		closed_apple <= 0;
	end
endtask

task automatic activate_selected_key;
	reg [7:0] code;
	begin
		code = 0;
		if(selected_row == 0 && selected_col == 14) begin
			commands_page <= 1;
			selected_col <= 0;
		end else if(selected_row == 2 && selected_col == 13) begin
			overlay_top <= ~overlay_top;
		end else if(selected_row == 2 && selected_col == 0) begin
			control_latched <= ~control_latched;
		end else if(selected_row == 3 && (selected_col == 0 || selected_col == 12)) begin
			shift_latched <= ~shift_latched;
		end else if(selected_row == 4 && selected_col == 0) begin
			caps_latched <= ~caps_latched;
		end else if(selected_row == 4 && selected_col == 1) begin
			open_apple <= ~open_apple;
		end else if(selected_row == 4 && selected_col == 3) begin
			closed_apple <= ~closed_apple;
		end else if(selected_row == 4 && selected_col == 8) begin
			transparency_cycle <= 1;
		end else begin
			code = normal_code(selected_row, selected_col);
			if(is_letter(code)) begin
				if(!(shift_active ^ caps_latched)) code = code + 7'h20;
			end else if(shift_active) begin
				code = shifted_code(selected_row, selected_col);
			end
			if(control_active && code >= 8'h40) code = code & 8'h1F;
			if(code != 0) begin
				press_virtual_key(code[6:0], SOURCE_SELECT);
			end
		end
	end
endtask

task automatic start_selected_command;
	begin
		command <= selected_col[2:0];
		reset_counter <= RESET_COUNT_VALUE;
		hold_counter <= HOLD_COUNT_VALUE;
		control_latched <= selected_col != CMD_WARM;
		open_apple <= selected_col == CMD_COLD;
		closed_apple <= selected_col == CMD_TEST;
	end
endtask

always @(posedge clk) begin
	command_reset <= 0;
	transparency_cycle <= 0;
	enabled_toggle <= 0;

	if(reset) begin
		raw_toggle <= ps2_key[10];
		filtered_ps2_key <= 0;
		active <= 0;
		commands_page <= 0;
		selected_row <= 1;
		selected_col <= 1;
		shift_latched <= 0;
		control_latched <= 0;
		caps_latched <= 1;
		enabled_toggle <= 0;
		open_apple <= 0;
		closed_apple <= 0;
		overlay_top <= 0;
		virtual_event <= 0;
		virtual_pressed <= 0;
		virtual_code <= 0;
		virtual_key_down <= 0;
		virtual_key_source <= SOURCE_NONE;
		reset_counter <= 0;
		hold_counter <= 0;
		command <= CMD_NONE;
		joystick_buttons_d <= joystick[10:4];
		enabled_d <= 0;
		physical_left_shift <= 0;
		physical_right_shift <= 0;
		physical_control <= 0;
		ms_divider <= 0;
		direction <= DIR_NONE;
		first_step_done <= 0;
		repeat_active <= 0;
		hold_elapsed_ms <= 0;
		step_elapsed_ms <= 0;
		repeat_stage <= 0;
		snapped <= 0;
		back_repeat_active <= 0;
		back_hold_elapsed_ms <= 0;
		back_step_elapsed_ms <= 0;
		back_repeat_stage <= 0;
	end else begin
		joystick_buttons_d <= joystick[10:4];
		enabled_d <= enabled;
		if(millisecond_tick) ms_divider <= 0;
		else ms_divider <= ms_divider + 1'd1;

		if(direction_press) begin
			direction <= next_direction;
			first_step_done <= 1;
			repeat_active <= 0;
			hold_elapsed_ms <= 0;
			step_elapsed_ms <= 0;
			repeat_stage <= 0;
			snapped <= 0;
		end else if(!active || !locked_direction_held) begin
			direction <= DIR_NONE;
			first_step_done <= 0;
			repeat_active <= 0;
			hold_elapsed_ms <= 0;
			step_elapsed_ms <= 0;
			repeat_stage <= 0;
			snapped <= 0;
		end else if(millisecond_tick) begin
			hold_elapsed_ms <= next_hold_elapsed_ms;
			if(next_hold_elapsed_ms >= STAGE3_AFTER_MS) repeat_stage <= 3;
			else if(next_hold_elapsed_ms >= STAGE2_AFTER_MS) repeat_stage <= 2;
			else if(repeat_active) repeat_stage <= 1;
			if(navigation_snap_due) snapped <= 1;
			if(navigation_first_repeat_due) begin
				repeat_active <= 1;
				repeat_stage <= 1;
			end
			if(navigation_snap_due || navigation_first_repeat_due || navigation_repeat_due)
				step_elapsed_ms <= 0;
			else if(repeat_active)
				step_elapsed_ms <= next_step_elapsed_ms;
		end

		if(!active || !joystick[5]) begin
			back_repeat_active <= 0;
			back_hold_elapsed_ms <= 0;
			back_step_elapsed_ms <= 0;
			back_repeat_stage <= 0;
		end else if(back_pressed) begin
			back_repeat_active <= 0;
			back_hold_elapsed_ms <= 0;
			back_step_elapsed_ms <= 0;
			back_repeat_stage <= 0;
		end else if(millisecond_tick) begin
			back_hold_elapsed_ms <= next_back_hold_elapsed_ms;
			if(next_back_hold_elapsed_ms >= STAGE3_AFTER_MS) back_repeat_stage <= 3;
			else if(next_back_hold_elapsed_ms >= STAGE2_AFTER_MS) back_repeat_stage <= 2;
			else if(back_repeat_active) back_repeat_stage <= 1;
			if(back_first_repeat_due) begin
				back_repeat_active <= 1;
				back_repeat_stage <= 1;
			end
			if(back_first_repeat_due || back_repeat_due)
				back_step_elapsed_ms <= 0;
			else if(back_repeat_active)
				back_step_elapsed_ms <= next_back_step_elapsed_ms;
		end
		if(new_event) begin
			raw_toggle <= ps2_key[10];
			if(!extended && scan_code == SC_LEFT_SHIFT)
				physical_left_shift <= key_down;
			else if(!extended && scan_code == SC_RIGHT_SHIFT)
				physical_right_shift <= key_down;
			else if(scan_code == SC_CTRL)
				physical_control <= key_down;
			else if(!key_down && !extended && scan_code == SC_CAPS)
				caps_latched <= ~caps_latched;
		end
		if(command != CMD_NONE) begin
			if(reset_counter != 0) begin
				command_reset <= 1;
				reset_counter <= reset_counter - 1'd1;
			end else if(hold_counter != 0) begin
				hold_counter <= hold_counter - 1'd1;
			end else begin
				command <= CMD_NONE;
				close_overlay();
				if(enabled) enabled_toggle <= 1;
			end
		end else if(!enabled && active) begin
			close_overlay();
		end else if(enabled && !enabled_d) begin
			open_overlay();
		end else if(visibility_pressed) begin
			enabled_toggle <= 1;
		end else if(active && transparency_pressed) begin
			transparency_cycle <= 1;
		end else if(active && move_pressed) begin
			overlay_top <= ~overlay_top;
		end else if(enter_pressed && !virtual_key_down) begin
			press_virtual_key(7'h0D, SOURCE_ENTER);
		end else if(enter_released && virtual_key_source == SOURCE_ENTER) begin
			release_virtual_key();
		end else if(space_pressed && !virtual_key_down) begin
			press_virtual_key(7'h20, SOURCE_SPACE);
		end else if(space_released && virtual_key_source == SOURCE_SPACE) begin
			release_virtual_key();
		end else if(active && back_step &&
			(!virtual_key_down || virtual_key_source == SOURCE_BACK)) begin
			press_virtual_key(7'h08, SOURCE_BACK);
		end else if(active && back_released && virtual_key_source == SOURCE_BACK) begin
			release_virtual_key();
		end else if(active && commands_page && navigation_snap_due && navigation_left) begin
			selected_col <= 0;
		end else if(active && commands_page && navigation_snap_due && navigation_right) begin
			selected_col <= 3;
		end else if(active && !commands_page && navigation_snap_due && navigation_left) begin
			selected_col <= 0;
		end else if(active && !commands_page && navigation_snap_due && navigation_right) begin
			selected_col <= row_last_col(selected_row);
		end else if(active && !commands_page && navigation_snap_due && navigation_up) begin
			selected_row <= 0;
			selected_col <= row_snap_up_col(selected_row, selected_col);
		end else if(active && !commands_page && navigation_snap_due && navigation_down) begin
			selected_row <= 4;
			selected_col <= row_snap_down_col(selected_row, selected_col);
		end else if(active && commands_page && navigation_left && selected_col != 0) begin
			selected_col <= selected_col - 1'd1;
		end else if(active && commands_page && navigation_right && selected_col != 3) begin
			selected_col <= selected_col + 1'd1;
		end else if(active && !commands_page && navigation_left && selected_col != 0) begin
			selected_col <= selected_col - 1'd1;
		end else if(active && !commands_page && navigation_right && selected_row == 1 && selected_col == 13) begin
			selected_row <= 2;
			selected_col <= 13;
		end else if(active && !commands_page && navigation_right && selected_row == 3 && selected_col == 12) begin
			selected_row <= 4;
			selected_col <= 8;
		end else if(active && !commands_page && navigation_right && selected_row == 2 && selected_col == 12) begin
			selected_row <= 1;
			selected_col <= 13;
		end else if(active && !commands_page && navigation_right && selected_col < row_last_col(selected_row)) begin
			selected_col <= selected_col + 1'd1;
		end else if(active && !commands_page && navigation_right && WRAP) begin
			selected_col <= 0;
		end else if(active && !commands_page && navigation_up && selected_row == 2 && selected_col == 13) begin
			selected_row <= 0;
			selected_col <= 14;
		end else if(active && !commands_page && navigation_up && selected_row == 4 && selected_col == 8) begin
			selected_row <= 2;
			selected_col <= 13;
		end else if(active && !commands_page && navigation_up && selected_row == 4 && selected_col == 2) begin
			selected_row <= 3;
			selected_col <= 6;
		end else if(active && !commands_page && navigation_up && selected_row == 4 && selected_col == 1) begin
			selected_row <= 3;
			selected_col <= 2;
		end else if(active && !commands_page && navigation_up && selected_row == 4 && selected_col == 3) begin
			selected_row <= 3;
			selected_col <= 8;
		end else if(active && !commands_page && navigation_up && selected_row == 4 && selected_col == 4) begin
			selected_row <= 3;
			selected_col <= 9;
		end else if(active && !commands_page && navigation_up && selected_row == 4 && selected_col == 5) begin
			selected_row <= 3;
			selected_col <= 10;
		end else if(active && !commands_page && navigation_up && selected_row == 4 && selected_col == 6) begin
			selected_row <= 3;
			selected_col <= 11;
		end else if(active && !commands_page && navigation_up && selected_row == 4 && selected_col == 7) begin
			selected_row <= 3;
			selected_col <= 12;
		end else if(active && !commands_page && navigation_up && selected_row != 0) begin
			selected_row <= selected_row - 1'd1;
			if(selected_col > row_last_col(selected_row - 1'd1)) selected_col <= row_last_col(selected_row - 1'd1);
		end else if(active && !commands_page && navigation_up && WRAP) begin
			selected_row <= 4;
			selected_col <= row_snap_down_col(selected_row, selected_col);
		end else if(active && !commands_page && navigation_down && selected_row == 1 && selected_col == 13) begin
			selected_row <= 3;
			selected_col <= 12;
		end else if(active && !commands_page && navigation_down && selected_row == 3 && selected_col == 12) begin
			selected_row <= 4;
			selected_col <= 7;
		end else if(active && !commands_page && navigation_down && selected_row == 3 &&
			selected_col >= 3 && selected_col <= 7) begin
			selected_row <= 4;
			selected_col <= 2;
		end else if(active && !commands_page && navigation_down && selected_row == 0 && selected_col == 14) begin
			selected_row <= 2;
			selected_col <= 13;
		end else if(active && !commands_page && navigation_down && selected_row == 2 && selected_col == 13) begin
			selected_row <= 4;
			selected_col <= 8;
		end else if(active && !commands_page && navigation_down && selected_row != 4) begin
			selected_row <= selected_row + 1'd1;
			if(selected_col > row_last_col(selected_row + 1'd1)) selected_col <= row_last_col(selected_row + 1'd1);
		end else if(active && !commands_page && navigation_down && WRAP) begin
			selected_row <= 0;
			if(selected_col > row_last_col(0)) selected_col <= row_last_col(0);
		end else if(active && joystick_fire_pressed && !virtual_key_down) begin
			if(commands_page) begin
				if(selected_col == 0) begin
					commands_page <= 0;
					selected_row <= 0;
					selected_col <= 14;
				end else start_selected_command();
			end else begin
				activate_selected_key();
			end
		end else if(active && joystick_fire_released && virtual_key_source == SOURCE_SELECT) begin
			release_virtual_key();
		end else if(new_event) begin
			if(!active) begin
				if(key_down && !extended && scan_code == SC_F10) begin
					enabled_toggle <= 1;
				end else begin
					filtered_ps2_key[10] <= ~filtered_ps2_key[10];
					filtered_ps2_key[9:0] <= ps2_key[9:0];
				end
			end else if(key_down && !extended && (scan_code == SC_F10 || scan_code == SC_ESC)) begin
				enabled_toggle <= 1;
			end else if(key_down && extended && scan_code == SC_PAGE_UP) begin
				overlay_top <= 1;
			end else if(key_down && extended && scan_code == SC_PAGE_DOWN) begin
				overlay_top <= 0;
			end else if(commands_page) begin
				if(key_down && extended && scan_code == SC_LEFT && selected_col != 0)
					selected_col <= selected_col - 1'd1;
				else if(key_down && extended && scan_code == SC_RIGHT && selected_col != 3)
					selected_col <= selected_col + 1'd1;
				else if(key_down && !extended && scan_code == SC_ENTER) begin
					if(selected_col == 0) begin
						commands_page <= 0;
						selected_row <= 0;
						selected_col <= 14;
					end else start_selected_command();
				end
			end else begin
				if(key_down && extended && scan_code == SC_LEFT && selected_col != 0)
					selected_col <= selected_col - 1'd1;
				else if(key_down && extended && scan_code == SC_RIGHT && selected_row == 1 && selected_col == 13) begin
					selected_row <= 2;
					selected_col <= 13;
				end
				else if(key_down && extended && scan_code == SC_RIGHT && selected_row == 3 && selected_col == 12) begin
					selected_row <= 4;
					selected_col <= 8;
				end
				else if(key_down && extended && scan_code == SC_RIGHT && selected_row == 2 && selected_col == 12) begin
					selected_row <= 1;
					selected_col <= 13;
				end
				else if(key_down && extended && scan_code == SC_RIGHT && selected_col < row_last_col(selected_row))
					selected_col <= selected_col + 1'd1;
				else if(key_down && extended && scan_code == SC_UP && selected_row == 2 && selected_col == 13) begin
					selected_row <= 0;
					selected_col <= 14;
				end else if(key_down && extended && scan_code == SC_UP && selected_row == 4 && selected_col == 8) begin
					selected_row <= 2;
					selected_col <= 13;
				end else if(key_down && extended && scan_code == SC_UP && selected_row == 4 && selected_col == 2) begin
					selected_row <= 3;
					selected_col <= 6;
				end else if(key_down && extended && scan_code == SC_UP && selected_row == 4 && selected_col == 1) begin
					selected_row <= 3;
					selected_col <= 2;
				end else if(key_down && extended && scan_code == SC_UP && selected_row == 4 && selected_col == 3) begin
					selected_row <= 3;
					selected_col <= 8;
				end else if(key_down && extended && scan_code == SC_UP && selected_row == 4 && selected_col == 4) begin
					selected_row <= 3;
					selected_col <= 9;
				end else if(key_down && extended && scan_code == SC_UP && selected_row == 4 && selected_col == 5) begin
					selected_row <= 3;
					selected_col <= 10;
				end else if(key_down && extended && scan_code == SC_UP && selected_row == 4 && selected_col == 6) begin
					selected_row <= 3;
					selected_col <= 11;
				end else if(key_down && extended && scan_code == SC_UP && selected_row == 4 && selected_col == 7) begin
					selected_row <= 3;
					selected_col <= 12;
				end
				else if(key_down && extended && scan_code == SC_UP && selected_row != 0) begin
					selected_row <= selected_row - 1'd1;
					if(selected_col > row_last_col(selected_row - 1'd1)) selected_col <= row_last_col(selected_row - 1'd1);
				end else if(key_down && extended && scan_code == SC_DOWN && selected_row == 1 && selected_col == 13) begin
					selected_row <= 3;
					selected_col <= 12;
				end else if(key_down && extended && scan_code == SC_DOWN && selected_row == 3 && selected_col == 12) begin
					selected_row <= 4;
					selected_col <= 7;
				end else if(key_down && extended && scan_code == SC_DOWN && selected_row == 3 &&
					selected_col >= 3 && selected_col <= 7) begin
					selected_row <= 4;
					selected_col <= 2;
				end else if(key_down && extended && scan_code == SC_DOWN && selected_row == 0 && selected_col == 14) begin
					selected_row <= 2;
					selected_col <= 13;
				end else if(key_down && extended && scan_code == SC_DOWN && selected_row == 2 && selected_col == 13) begin
					selected_row <= 4;
					selected_col <= 8;
				end else if(key_down && extended && scan_code == SC_DOWN && selected_row != 4) begin
					selected_row <= selected_row + 1'd1;
					if(selected_col > row_last_col(selected_row + 1'd1)) selected_col <= row_last_col(selected_row + 1'd1);
				end else if(key_down && !extended && scan_code == SC_ENTER) begin
					activate_selected_key();
				end else if(!key_down && !extended && scan_code == SC_ENTER) begin
					release_virtual_key();
				end
			end
		end
	end
end

endmodule