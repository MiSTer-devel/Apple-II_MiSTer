module virtual_keyboard_overlay #(
	parameter integer PANEL_X = 4,
	parameter integer PANEL_Y = 94,
	parameter integer PANEL_WIDTH = 552,
	parameter integer PANEL_HEIGHT = 98
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        active,
	input  wire        commands_page,
	input  wire [2:0]  selected_row,
	input  wire [3:0]  selected_col,
	input  wire        shift_latched,
	input  wire        control_latched,
	input  wire        caps_latched,
	input  wire        open_apple,
	input  wire        closed_apple,
	input  wire [1:0]  transparency,
	input  wire        overlay_top,
	input  wire        pixel_clock_double,
	input  wire        hblank,
	input  wire        vblank,
	input  wire [23:0] rgb_in,
	output reg         font_alternate,
	output reg         font_lowercase,
	output reg  [6:0]  font_character,
	output reg  [2:0]  font_row,
	input  wire [7:0]  font_data,
	output reg  [23:0] rgb_out
);

localparam [23:0] PANEL_COLOR = 24'hD0C4B1;
localparam [23:0] BORDER_COLOR = 24'hB8B8B0;
localparam [23:0] WELL_COLOR = 24'h686A65;
localparam [23:0] LINE_COLOR = 24'h4F504C;
localparam [23:0] KEY_COLOR = 24'h343633;
localparam [23:0] SELECT_COLOR = 24'h506D61;
localparam [23:0] LATCH_COLOR = 24'h8A7040;
localparam [23:0] TEXT_COLOR = 24'hF2EEE2;
localparam [23:0] INACTIVE_TEXT_COLOR = 24'h8F8C84;
localparam [23:0] ON_HOUSING_COLOR = 24'h656864;
localparam [23:0] ON_LIGHT_COLOR = 24'hA8D89A;
localparam [23:0] ON_BORDER_COLOR = 24'h20211F;
localparam [23:0] SELECT_SHADOW_COLOR = 24'h3B5148;
localparam [23:0] LATCH_SHADOW_COLOR = 24'h66522F;
localparam [23:0] BADGE_BEVEL_COLOR = 24'h5B5D57;
localparam [23:0] BADGE_INNER_BEVEL_COLOR = 24'h484A45;
localparam [23:0] BADGE_INNER_SHADOW_COLOR = 24'h292A27;
localparam [23:0] BADGE_SHADOW_COLOR = 24'h161715;
localparam [23:0] BADGE_GREEN = 24'h63C65A;
localparam [23:0] BADGE_YELLOW = 24'hF2C84B;
localparam [23:0] BADGE_ORANGE = 24'hF28B3C;
localparam [23:0] BADGE_RED = 24'hE9564F;
localparam [23:0] BADGE_PURPLE = 24'hA64D9B;
localparam [23:0] BADGE_BLUE = 24'h3D91C9;

reg [9:0] source_x = 0;
reg [8:0] video_y = 0;
reg hblank_d = 1;

wire [9:0] video_x = pixel_clock_double ? source_x : {source_x[9:1], 1'b0};

reg [9:0] key_left;
reg [8:0] key_top;
reg [7:0] key_width;
reg [5:0] key_height;
reg [2:0] text_length;
reg [9:0] text_left;
reg [3:0] text_slot;
reg [2:0] glyph_column;
reg [3:0] glyph_y;
reg [8:0] panel_y;
reg [4:0] badge_x;
reg [4:0] badge_y;
reg [2:0] pixel_row;
reg [3:0] pixel_col;
reg key_pixel;
reg key_shadow_pixel;
reg badge_pixel;
reg [23:0] badge_color;
reg [23:0] overlay_color;
reg panel_pixel;
reg border_pixel;
reg well_pixel;
reg separator_pixel;
reg selected_pixel;
reg latched_pixel;
reg glyph_pixel;
reg glyph_inactive;
reg label_pixel;
reg on_light_pixel;
reg on_light_border_pixel;
reg on_light_lit_pixel;
reg [7:0] requested_character;

function automatic [7:0] key_character(input [2:0] row, input [3:0] col);
	begin
		key_character = 0;
		case(row)
			0: case(col)
				1: key_character = "1"; 2: key_character = "2";
				3: key_character = "3"; 4: key_character = "4";
				5: key_character = "5"; 6: key_character = "6";
				7: key_character = "7"; 8: key_character = "8";
				9: key_character = "9"; 10: key_character = "0";
				11: key_character = "-"; 12: key_character = "=";
				default: key_character = 0;
			endcase
			1: case(col)
				1: key_character = "Q"; 2: key_character = "W";
				3: key_character = "E"; 4: key_character = "R";
				5: key_character = "T"; 6: key_character = "Y";
				7: key_character = "U"; 8: key_character = "I";
				9: key_character = "O"; 10: key_character = "P";
				11: key_character = "["; 12: key_character = "]";
				default: key_character = 0;
			endcase
			2: case(col)
				1: key_character = "A"; 2: key_character = "S";
				3: key_character = "D"; 4: key_character = "F";
				5: key_character = "G"; 6: key_character = "H";
				7: key_character = "J"; 8: key_character = "K";
				9: key_character = "L"; 10: key_character = ";";
				11: key_character = "'"; 12: key_character = 8'h60;
				default: key_character = 0;
			endcase
			3: case(col)
				1: key_character = 7'h5C;
				2: key_character = "Z"; 3: key_character = "X";
				4: key_character = "C"; 5: key_character = "V";
				6: key_character = "B"; 7: key_character = "N";
				8: key_character = "M"; 9: key_character = ",";
				10: key_character = "."; 11: key_character = "/";
				default: key_character = 0;
			endcase
			default: key_character = 0;
		endcase
	end
endfunction

function automatic [7:0] shown_character(
	input [2:0] row,
	input [3:0] col,
	input shifted,
	input caps
);
	reg [7:0] code;
	begin
		code = key_character(row, col);
		shown_character = code;
		if(code >= "A" && code <= "Z") begin
			if(!(shifted ^ caps)) shown_character = code + 8'h20;
		end else if(row == 0 && shifted) begin
			case(col)
				1: shown_character = "!"; 2: shown_character = "@";
				3: shown_character = "#"; 4: shown_character = "$";
				5: shown_character = "%"; 6: shown_character = "^";
				7: shown_character = "&"; 8: shown_character = "*";
				9: shown_character = "("; 10: shown_character = ")";
				11: shown_character = "_"; 12: shown_character = "+";
				default: shown_character = code;
			endcase
		end else if(row == 1 && shifted) begin
			if(col == 11) shown_character = "{";
			else if(col == 12) shown_character = "}";
		end else if(row == 2 && shifted) begin
			if(col == 10) shown_character = ":";
			else if(col == 11) shown_character = 8'h22;
			else if(col == 12) shown_character = "~";
		end else if(row == 3 && shifted) begin
			if(col == 1) shown_character = "|";
			else if(col == 9) shown_character = "<";
			else if(col == 10) shown_character = ">";
			else if(col == 11) shown_character = "?";
		end
	end
endfunction

function automatic has_symbol_pair(input [2:0] row, input [3:0] col);
	begin
		has_symbol_pair = (row == 0 && col >= 1 && col <= 12) ||
			(row == 1 && (col == 11 || col == 12)) ||
			(row == 2 && (col >= 10 && col <= 12)) ||
			(row == 3 && (col == 1 || (col >= 9 && col <= 11)));
	end
endfunction

function automatic [2:0] label_length(input [2:0] row, input [3:0] col, input commands);
	begin
		if(commands && row == 0 && col <= 3) label_length = 4;
		else if(row == 0 && (col == 0 || col == 13 || col == 14)) label_length = 3;
		else if(row == 1 && col == 0) label_length = 2;
		else if(row == 1 && col == 13) label_length = 1;
		else if(row == 2 && col == 0) label_length = 4;
		else if(row == 2 && col == 13) label_length = 2;
		else if(row == 3 && col == 0) label_length = 1;
		else if(row == 3 && col == 12) label_length = 5;
		else if(row == 4 && col == 0) label_length = 4;
		else if(row == 4 && ((col >= 1 && col <= 7) && col != 2)) label_length = 1;
		else if(row == 4 && col == 8) label_length = 1;
		else label_length = key_character(row, col) == 0 ? 3'd0 : 3'd1;
	end
endfunction

function automatic [7:0] label_character(
	input [2:0] row,
	input [3:0] col,
	input [3:0] slot,
	input commands
);
	begin
		label_character = shown_character(row, col, shift_latched, caps_latched);
		if(commands && row == 0 && col <= 3) begin
			case(col)
				0: case(slot) 0: label_character="B"; 1: label_character="A"; 2: label_character="C"; default: label_character="K"; endcase
				1: case(slot) 0: label_character="W"; 1: label_character="A"; 2: label_character="R"; default: label_character="M"; endcase
				2: case(slot) 0: label_character="C"; 1: label_character="O"; 2: label_character="L"; default: label_character="D"; endcase
				default: case(slot) 0: label_character="T"; 1: label_character="E"; 2: label_character="S"; default: label_character="T"; endcase
			endcase
		end else if(row == 0 && col == 0) begin
			case(slot) 0: label_character="E"; 1: label_character="s"; default: label_character="c"; endcase
		end else if(row == 0 && col == 13) begin
			case(slot) 0: label_character="D"; 1: label_character="e"; default: label_character="l"; endcase
		end else if(row == 0 && col == 14) begin
			case(slot) 0: label_character="C"; 1: label_character="M"; default: label_character="D"; endcase
		end else if(row == 1 && col == 0) begin
			case(slot) 0: label_character=8'h55; default: label_character=8'h5F; endcase
		end else if(row == 1 && col == 13) begin
			label_character = 8'h4D;
		end else if(row == 2 && col == 0) begin
			case(slot) 0: label_character="C"; 1: label_character="t"; 2: label_character="r"; default: label_character="l"; endcase
		end else if(row == 2 && col == 13) begin
			if(slot == 0) label_character = 8'h46;
			else label_character = 8'h47;
		end else if(row == 3 && col == 0) begin
			label_character = 8'h52;
		end else if(row == 3 && col == 12) begin
			case(slot) 0: label_character="S"; 1: label_character="h"; 2: label_character="i"; 3: label_character="f"; default: label_character="t"; endcase
		end else if(row == 4 && col == 0) begin
			case(slot) 0: label_character="C"; 1: label_character="a"; 2: label_character="p"; default: label_character="s"; endcase
		end else if(row == 4 && col == 1) begin
			label_character = 8'h41;
		end else if(row == 4 && col == 3) begin
			label_character = 8'h40;
		end else if(row == 4) begin
			case(col)
				4: label_character = 8'h48;
				5: label_character = 8'h55;
				6: label_character = 8'h4A;
				7: label_character = 8'h4B;
				default: label_character = 0;
			endcase
		end
	end
endfunction

function automatic diamond_pixel(
	input [2:0] x,
	input [2:0] y
);
	begin
		diamond_pixel = (y == 1 && x == 3) ||
			(y == 2 && (x == 2 || x == 4)) ||
			(y == 3 && (x == 1 || x == 5)) ||
			(y == 4 && (x == 2 || x == 4)) ||
			(y == 5 && x == 3);
	end
endfunction

function automatic rendered_diamond_pixel(
	input [2:0] x,
	input [2:0] y
);
	reg [2:0] pair_x;
	begin
		pair_x = {x[2:1], 1'b0};
		rendered_diamond_pixel = pixel_clock_double ? diamond_pixel(x, y) :
			(diamond_pixel(pair_x, y) || diamond_pixel(pair_x + 1'd1, y));
	end
endfunction

function automatic rendered_font_pixel(
	input [7:0] data,
	input [2:0] column,
	input alternate
);
	reg [2:0] pair_column;
	begin
		pair_column = {column[2:1], 1'b0};
		if(pixel_clock_double)
			rendered_font_pixel = alternate ? !data[column] : data[column];
		else if(alternate)
			rendered_font_pixel = !(data[pair_column] && data[pair_column + 1'd1]);
		else
			rendered_font_pixel = data[pair_column] || data[pair_column + 1'd1];
	end
endfunction

function automatic horizontal_edge(input [9:0] target);
	begin
		horizontal_edge = pixel_clock_double ? video_x == target :
			video_x[9:1] == target[9:1];
	end
endfunction

function automatic [9:0] badge_logo_row(input [3:0] row);
	begin
		case(row)
			0: badge_logo_row = 10'b0011110000;
			1: badge_logo_row = 10'b0111111100;
			2: badge_logo_row = 10'b1111111110;
			3: badge_logo_row = 10'b1111110000;
			4: badge_logo_row = 10'b1111111000;
			5: badge_logo_row = 10'b1111111110;
			6: badge_logo_row = 10'b0111111110;
			7: badge_logo_row = 10'b0011111100;
			8: badge_logo_row = 10'b0001111000;
			default: badge_logo_row = 0;
		endcase
	end
endfunction

function automatic badge_logo_pixel(input signed [5:0] x, input signed [5:0] y);
	reg [9:0] row_bits;
	begin
		row_bits = badge_logo_row(y);
		badge_logo_pixel = x >= 0 && x < 10 && y >= 0 && y < 9 && row_bits[9-x];
	end
endfunction

function automatic [23:0] blend50(input [23:0] background, input [23:0] foreground);
	begin
		blend50[23:16] = {1'b0, background[23:17]} + {1'b0, foreground[23:17]};
		blend50[15:8] = {1'b0, background[15:9]} + {1'b0, foreground[15:9]};
		blend50[7:0] = {1'b0, background[7:1]} + {1'b0, foreground[7:1]};
	end
endfunction

function automatic [23:0] blend25(input [23:0] background, input [23:0] foreground);
	reg [9:0] red_sum;
	reg [9:0] green_sum;
	reg [9:0] blue_sum;
	begin
		red_sum = {2'b0, background[23:16]} + {1'b0, foreground[23:16], 1'b0} + {2'b0, foreground[23:16]};
		green_sum = {2'b0, background[15:8]} + {1'b0, foreground[15:8], 1'b0} + {2'b0, foreground[15:8]};
		blue_sum = {2'b0, background[7:0]} + {1'b0, foreground[7:0], 1'b0} + {2'b0, foreground[7:0]};
		blend25 = {red_sum[9:2], green_sum[9:2], blue_sum[9:2]};
	end
endfunction

function automatic [23:0] blend75(input [23:0] background, input [23:0] foreground);
	reg [9:0] red_sum;
	reg [9:0] green_sum;
	reg [9:0] blue_sum;
	begin
		red_sum = {2'b0, background[23:16]} + {1'b0, background[23:16], 1'b0} + {2'b0, foreground[23:16]};
		green_sum = {2'b0, background[15:8]} + {1'b0, background[15:8], 1'b0} + {2'b0, foreground[15:8]};
		blue_sum = {2'b0, background[7:0]} + {1'b0, background[7:0], 1'b0} + {2'b0, foreground[7:0]};
		blend75 = {red_sum[9:2], green_sum[9:2], blue_sum[9:2]};
	end
endfunction

function automatic [23:0] blend_color(
	input [23:0] background,
	input [23:0] foreground,
	input [1:0] mode
);
	begin
		case(mode)
			1: blend_color = blend25(background, foreground);
			2: blend_color = blend50(background, foreground);
			3: blend_color = blend75(background, foreground);
			default: blend_color = foreground;
		endcase
	end
endfunction

always @(posedge clk) begin
	hblank_d <= hblank;
	if(reset || vblank) begin
		source_x <= 0;
		video_y <= 0;
	end else begin
		if(hblank) source_x <= 0;
		else source_x <= source_x + 1'd1;
		if(!hblank_d && hblank) video_y <= video_y + 1'd1;
	end
end

always @(*) begin
	key_pixel = 0;
	key_shadow_pixel = 0;
	badge_pixel = 0;
	badge_color = KEY_COLOR;
	overlay_color = PANEL_COLOR;
	panel_pixel = 0;
	border_pixel = 0;
	well_pixel = 0;
	separator_pixel = 0;
	selected_pixel = 0;
	latched_pixel = 0;
	glyph_pixel = 0;
	glyph_inactive = 0;
	label_pixel = 0;
	on_light_pixel = 0;
	on_light_border_pixel = 0;
	on_light_lit_pixel = 0;
	font_character = 0;
	font_row = 0;
	font_alternate = 0;
	font_lowercase = 0;
	requested_character = 0;
	pixel_row = 0;
	pixel_col = 0;
	key_left = 0;
	key_top = 0;
	key_width = 0;
	key_height = 0;
	text_length = 0;
	text_left = 0;
	text_slot = 0;
	glyph_column = 0;
	glyph_y = 0;
	badge_x = 0;
	badge_y = 0;
	panel_y = overlay_top ? 9'd0 : 9'(PANEL_Y);

	if(active && !hblank && !vblank &&
		video_x >= PANEL_X && video_x < PANEL_X + PANEL_WIDTH &&
		video_y >= panel_y && video_y < panel_y + PANEL_HEIGHT) begin
		panel_pixel = video_x >= PANEL_X + 1 && video_x < PANEL_X + 551 &&
			video_y >= panel_y + 1 && video_y < panel_y + 97 &&
			!(((video_y == panel_y + 1 || video_y == panel_y + 96) &&
				(video_x < PANEL_X + 6 || video_x >= PANEL_X + 547)) ||
			  ((video_y == panel_y + 2 || video_y == panel_y + 95) &&
				(video_x == PANEL_X + 1 || video_x == PANEL_X + 550)));
		border_pixel = panel_pixel &&
			(video_y == panel_y + 1 || video_y == panel_y + 96 ||
			 horizontal_edge(PANEL_X + 1) || horizontal_edge(PANEL_X + 550));
		well_pixel = panel_pixel && video_x >= PANEL_X + 11 && video_x < PANEL_X + 487 &&
			video_y >= panel_y + 6 && video_y < panel_y + 90;
		separator_pixel = well_pixel && (video_y == panel_y + 22 || video_y == panel_y + 39 ||
			video_y == panel_y + 56 || video_y == panel_y + 73);
		if(video_x >= PANEL_X + 499 && video_x < PANEL_X + 539 &&
			video_y >= panel_y + 71 && video_y < panel_y + 91) begin
			badge_x = 5'((video_x - PANEL_X - 499) >> 1);
			badge_y = 5'(video_y - panel_y - 71);
			badge_pixel = !((badge_x == 0 || badge_x == 19) &&
				(badge_y == 0 || badge_y == 19));
			if(badge_y == 0 || badge_x == 0)
				badge_color = ON_BORDER_COLOR;
			else if(badge_y == 19 || badge_x == 19)
				badge_color = BADGE_BEVEL_COLOR;
			else
				badge_color = KEY_COLOR;
			if(badge_logo_pixel(badge_x - 6, badge_y - 7))
				badge_color = BADGE_SHADOW_COLOR;
			if(badge_logo_pixel(badge_x - 5, badge_y - 6)) begin
				case(badge_y)
					6, 7: badge_color = BADGE_GREEN;
					8: badge_color = BADGE_YELLOW;
					9: badge_color = BADGE_ORANGE;
					10, 11: badge_color = BADGE_RED;
					12: badge_color = BADGE_PURPLE;
					default: badge_color = BADGE_BLUE;
				endcase
			end
			if((badge_y == 4 && (badge_x == 11 || badge_x == 12)) ||
				(badge_y == 5 && badge_x == 11))
				badge_color = BADGE_GREEN;
		end
		if(commands_page) begin
			if(video_y >= panel_y + 24 && video_y < panel_y + 55 &&
				video_x >= PANEL_X + 14 && video_x < PANEL_X + 482) begin
				pixel_row = 0;
				if(video_x < PANEL_X + 132) begin
					pixel_col = 0; key_left = 10'(PANEL_X + 14);
				end else if(video_x < PANEL_X + 250) begin
					pixel_col = 1; key_left = 10'(PANEL_X + 132);
				end else if(video_x < PANEL_X + 368) begin
					pixel_col = 2; key_left = 10'(PANEL_X + 250);
				end else begin
					pixel_col = 3; key_left = 10'(PANEL_X + 368);
				end
				key_top = 9'(panel_y + 24);
				key_width = 114;
				key_height = 31;
				key_pixel = pixel_col < 4 && video_x < key_left + key_width;
				selected_pixel = key_pixel && pixel_col == selected_col;
			end else if(video_x >= PANEL_X + 499 && video_x < PANEL_X + 539 &&
				video_y >= panel_y + 7 && video_y < panel_y + 21) begin
				pixel_row = 0; pixel_col = 14; key_left = 10'(PANEL_X + 499);
				key_top = 9'(panel_y + 7); key_width = 40; key_height = 14; key_pixel = 1;
			end else if(video_x >= PANEL_X + 499 && video_x < PANEL_X + 539 &&
				video_y >= panel_y + 24 && video_y < panel_y + 38) begin
				pixel_row = 2; pixel_col = 13; key_left = 10'(PANEL_X + 499);
				key_top = 9'(panel_y + 24); key_width = 40; key_height = 14; key_pixel = 1;
			end else if(video_x >= PANEL_X + 499 && video_x < PANEL_X + 539 &&
				video_y >= panel_y + 41 && video_y < panel_y + 55) begin
				pixel_row = 4; pixel_col = 8; key_left = 10'(PANEL_X + 499);
				key_top = 9'(panel_y + 41); key_width = 40; key_height = 14; key_pixel = 1;
			end
		end else if(video_y >= panel_y + 7 && video_y < panel_y + 89) begin
			key_height = 14;
			if(video_y >= panel_y + 24 && video_y < panel_y + 55 &&
				((video_y < panel_y + 38 && video_x >= PANEL_X + 446 && video_x < PANEL_X + 484) ||
				 (video_y >= panel_y + 38 && video_x >= PANEL_X + 460 && video_x < PANEL_X + 484))) begin
				pixel_row = 1; pixel_col = 13; key_left = 10'(PANEL_X + 446);
				key_top = 9'(panel_y + 24); key_width = 38; key_height = 31; key_pixel = 1;
			end else if(video_y < panel_y + 21) begin
				pixel_row = 0; key_top = 9'(panel_y + 7);
				if(video_x >= PANEL_X + 14 && video_x < PANEL_X + 52) begin
					pixel_col = 0; key_left = 10'(PANEL_X + 14); key_width = 38; key_pixel = 1;
				end else if(video_x >= PANEL_X + 54 && video_x < PANEL_X + 436) begin
					pixel_col = 4'(1 + ((video_x - PANEL_X - 54) >> 5));
					key_left = 10'(PANEL_X + 54 + ((pixel_col - 1) << 5));
					key_width = 30; key_pixel = video_x < key_left + key_width;
				end else if(video_x >= PANEL_X + 438 && video_x < PANEL_X + 484) begin
					pixel_col = 13; key_left = 10'(PANEL_X + 438); key_width = 46; key_pixel = 1;
				end else if(video_x >= PANEL_X + 499 && video_x < PANEL_X + 539) begin
					pixel_col = 14; key_left = 10'(PANEL_X + 499); key_width = 40; key_pixel = 1;
				end
			end else if(video_y >= panel_y + 24 && video_y < panel_y + 38) begin
				pixel_row = 1; key_top = 9'(panel_y + 24);
				if(video_x >= PANEL_X + 14 && video_x < PANEL_X + 60) begin
					pixel_col = 0; key_left = 10'(PANEL_X + 14); key_width = 46; key_pixel = 1;
				end else if(video_x >= PANEL_X + 62 && video_x < PANEL_X + 444) begin
					pixel_col = 4'(1 + ((video_x - PANEL_X - 62) >> 5));
					key_left = 10'(PANEL_X + 62 + ((pixel_col - 1) << 5));
					key_width = 30; key_pixel = video_x < key_left + 30;
				end else if(video_x >= PANEL_X + 499 && video_x < PANEL_X + 539) begin
					pixel_row = 2; pixel_col = 13; key_left = 10'(PANEL_X + 499); key_width = 40; key_pixel = 1;
				end
			end else if(video_y >= panel_y + 41 && video_y < panel_y + 55) begin
				pixel_row = 2; key_top = 9'(panel_y + 41);
				if(video_x >= PANEL_X + 14 && video_x < PANEL_X + 74) begin
					pixel_col = 0; key_left = 10'(PANEL_X + 14); key_width = 60; key_pixel = 1;
				end else if(video_x >= PANEL_X + 76 && video_x < PANEL_X + 458) begin
					pixel_col = 4'(1 + ((video_x - PANEL_X - 76) >> 5));
					key_left = 10'(PANEL_X + 76 + ((pixel_col - 1) << 5));
					key_width = 30; key_pixel = video_x < key_left + 30;
				end else if(video_x >= PANEL_X + 499 && video_x < PANEL_X + 539) begin
					pixel_row = 4; pixel_col = 8; key_left = 10'(PANEL_X + 499); key_width = 40; key_pixel = 1;
				end
			end else if(video_y >= panel_y + 58 && video_y < panel_y + 72) begin
				pixel_row = 3; key_top = 9'(panel_y + 58);
				if(video_x >= PANEL_X + 14 && video_x < PANEL_X + 57) begin
					pixel_col = 0; key_left = 10'(PANEL_X + 14); key_width = 43; key_pixel = 1;
				end else if(video_x >= PANEL_X + 59 && video_x < PANEL_X + 409) begin
					pixel_col = 4'(1 + ((video_x - PANEL_X - 59) >> 5));
					key_left = 10'(PANEL_X + 59 + ((pixel_col - 1) << 5));
					key_width = 30; key_pixel = video_x < key_left + 30;
				end else if(video_x >= PANEL_X + 411 && video_x < PANEL_X + 484) begin
					pixel_col = 12; key_left = 10'(PANEL_X + 411); key_width = 73; key_pixel = 1;
				end
			end else if(video_y >= panel_y + 75 && video_y < panel_y + 89) begin
				pixel_row = 4; key_top = 9'(panel_y + 75);
				on_light_pixel = video_x >= PANEL_X + 64 && video_x < PANEL_X + 94 &&
					video_y >= key_top && video_y < key_top + 14 &&
					!((horizontal_edge(PANEL_X + 64) || horizontal_edge(PANEL_X + 93)) &&
					  (video_y == key_top || video_y == key_top + 13));
				on_light_border_pixel = on_light_pixel &&
					(horizontal_edge(PANEL_X + 64) || horizontal_edge(PANEL_X + 93) ||
					 video_y == key_top || video_y == key_top + 13);
				on_light_lit_pixel = video_x >= PANEL_X + 74 && video_x < PANEL_X + 84 &&
					video_y >= key_top + 4 && video_y < key_top + 10;
				if(video_x >= PANEL_X + 14 && video_x < PANEL_X + 62) begin
					pixel_col=0; key_left=10'(PANEL_X+14); key_width=48; key_pixel=1;
				end else if(video_x >= PANEL_X + 96 && video_x < PANEL_X + 126) begin
					pixel_col=1; key_left=10'(PANEL_X+96); key_width=30; key_pixel=1;
				end else if(video_x >= PANEL_X + 128 && video_x < PANEL_X + 318) begin
					pixel_col=2; key_left=10'(PANEL_X+128); key_width=190; key_pixel=1;
				end else if(video_x >= PANEL_X + 320 && video_x < PANEL_X + 350) begin
					pixel_col=3; key_left=10'(PANEL_X+320); key_width=30; key_pixel=1;
				end else if(video_x >= PANEL_X + 352 && video_x < PANEL_X + 383) begin
					pixel_col=4; key_left=10'(PANEL_X+352); key_width=31; key_pixel=1;
				end else if(video_x >= PANEL_X + 385 && video_x < PANEL_X + 416) begin
					pixel_col=5; key_left=10'(PANEL_X+385); key_width=31; key_pixel=1;
				end else if(video_x >= PANEL_X + 418 && video_x < PANEL_X + 449) begin
					pixel_col=6; key_left=10'(PANEL_X+418); key_width=31; key_pixel=1;
				end else if(video_x >= PANEL_X + 451 && video_x < PANEL_X + 484) begin
					pixel_col=7; key_left=10'(PANEL_X+451); key_width=33; key_pixel=1;
				end
			end
			selected_pixel = pixel_row == selected_row && pixel_col == selected_col;
			latched_pixel = (pixel_row == 2 && pixel_col == 0 && control_latched) ||
				(pixel_row == 3 && (pixel_col == 0 || pixel_col == 12) && shift_latched) ||
				(pixel_row == 4 && pixel_col == 0 && caps_latched) ||
				(pixel_row == 4 && pixel_col == 1 && open_apple) ||
				(pixel_row == 4 && pixel_col == 3 && closed_apple) ||
				(pixel_row == 4 && pixel_col == 8 && transparency > 1);
		end

		if(key_pixel && (commands_page || pixel_row != 1 || pixel_col != 13) &&
			((video_y == key_top &&
				(horizontal_edge(key_left) || horizontal_edge(key_left + key_width - 1))) ||
			 (video_y == key_top + key_height - 1 && horizontal_edge(key_left))))
			key_pixel = 0;
		if(key_pixel && !commands_page && pixel_row == 1 && pixel_col == 13 &&
			((video_y == key_top &&
				(horizontal_edge(key_left) || horizontal_edge(key_left + key_width - 1))) ||
			 (video_y == key_top + 13 && horizontal_edge(key_left))))
			key_pixel = 0;
		key_shadow_pixel = key_pixel && horizontal_edge(key_left + key_width - 1) &&
			video_y == key_top + key_height - 1;

		if(key_pixel) begin
			if(!commands_page && has_symbol_pair(pixel_row, pixel_col)) begin
				if(video_y < key_top + 6 ||
					((video_y == key_top + 6 || video_y == key_top + 7) && video_x < key_left + 16)) begin
					glyph_y = 4'(video_y - key_top);
					requested_character = shown_character(pixel_row, pixel_col, 1, caps_latched);
					glyph_inactive = !shift_latched;
					if(video_x >= key_left + 4 && video_x < key_left + 12 && glyph_y < 8) begin
						glyph_column = 3'(video_x - key_left - 4);
						label_pixel = 1;
					end
				end else begin
					glyph_y = 4'(video_y - key_top - 6);
					requested_character = shown_character(pixel_row, pixel_col, 0, caps_latched);
					glyph_inactive = shift_latched;
					if(video_x >= key_left + 18 && video_x < key_left + 26 && glyph_y < 8) begin
						glyph_column = 3'(video_x - key_left - 18);
						label_pixel = 1;
					end
				end
				if(requested_character != 0) begin
					font_character = requested_character[6:0];
					font_row = glyph_y[2:0];
					font_lowercase = requested_character >= 8'h60;
					if(label_pixel) glyph_pixel = rendered_font_pixel(font_data, glyph_column, 1'b0);
				end
			end else begin
				glyph_inactive = commands_page && !(pixel_row == 0 && pixel_col <= 3);
				text_length = label_length(pixel_row, pixel_col, commands_page);
				if(pixel_row == 1 && pixel_col == 13) begin
					text_left = 10'(key_left + ((key_width - (text_length << 3)) >> 1));
					if(video_y >= key_top + 3 && video_y < key_top + 11) begin
						glyph_y = 4'(video_y - key_top - 3);
						if(video_x >= text_left && video_x < text_left + 8) begin
							glyph_column = 3'(video_x - text_left);
							label_pixel = 1;
						end
					end
				end else begin
					text_left = 10'(key_left + ((key_width - (text_length << 3)) >> 1));
					if(video_y >= key_top + ((key_height - 8) >> 1) &&
						video_y < key_top + ((key_height - 8) >> 1) + 8) begin
						glyph_y = 4'(video_y - key_top - ((key_height - 8) >> 1));
						if(pixel_row == 2 && pixel_col == 13 &&
							video_x >= text_left + 2 && video_x < text_left + 10) begin
							text_slot = 0;
							glyph_column = 3'(video_x - text_left - 2);
							label_pixel = 1;
						end else if(pixel_row == 2 && pixel_col == 13 &&
							video_x >= text_left + 8 && video_x < text_left + 16) begin
							text_slot = 1;
							glyph_column = 3'(video_x - text_left - 8);
							label_pixel = 1;
						end else if(video_x < text_left) text_slot = 0;
						else begin
							text_slot = 4'((video_x - text_left + 1) >> 3);
							if(text_slot >= text_length) text_slot = 4'(text_length - 1'd1);
						end
						if(!(pixel_row == 2 && pixel_col == 13) &&
							video_x >= text_left && video_x < text_left + (text_length << 3)) begin
							glyph_column = 3'((video_x - text_left) & 7);
							label_pixel = 1;
						end
					end
				end
				if(text_length != 0 && glyph_y >= 0 && glyph_y < 8) begin
					requested_character = label_character(pixel_row, pixel_col, text_slot, commands_page);
					font_character = requested_character[6:0];
					font_row = glyph_y[2:0];
					font_lowercase = requested_character >= 8'h60;
					font_alternate = !(commands_page && pixel_row == 0 && pixel_col <= 3) &&
						((pixel_row == 1 && (pixel_col == 0 || pixel_col == 13)) ||
						 (pixel_row == 2 && pixel_col == 13) ||
						 (pixel_row == 3 && pixel_col == 0) ||
						 (pixel_row == 4 && ((pixel_col >= 1 && pixel_col <= 7) && pixel_col != 2)));
					if(pixel_row == 4 && pixel_col == 8 && label_pixel)
						glyph_pixel = rendered_diamond_pixel(glyph_column, glyph_y);
					else if(label_pixel)
						glyph_pixel = rendered_font_pixel(font_data, glyph_column, font_alternate);
				end
			end
		end
	end

	if(panel_pixel) begin
		overlay_color = border_pixel ? BORDER_COLOR : PANEL_COLOR;
		if(well_pixel)
			overlay_color = separator_pixel ? LINE_COLOR : WELL_COLOR;
		if(badge_pixel)
			overlay_color = badge_color;
		if(on_light_pixel) overlay_color = ON_HOUSING_COLOR;
		if(on_light_border_pixel) overlay_color = ON_BORDER_COLOR;
		if(on_light_lit_pixel) overlay_color = ON_LIGHT_COLOR;
		if(key_pixel) begin
			if(selected_pixel)
				overlay_color = SELECT_COLOR;
			else if(latched_pixel)
				overlay_color = LATCH_COLOR;
			else
				overlay_color = KEY_COLOR;
		end
		if(key_shadow_pixel) begin
			if(selected_pixel)
				overlay_color = SELECT_SHADOW_COLOR;
			else if(latched_pixel)
				overlay_color = LATCH_SHADOW_COLOR;
			else
				overlay_color = LINE_COLOR;
		end
		if(glyph_pixel)
			overlay_color = glyph_inactive ? INACTIVE_TEXT_COLOR : TEXT_COLOR;
	end
	rgb_out = panel_pixel ? blend_color(rgb_in, overlay_color, transparency) : rgb_in;
end

endmodule