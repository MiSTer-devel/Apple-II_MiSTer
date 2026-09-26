// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Newsdee

module savestate_hotkeys (
	input  wire        clk,
	input  wire        reset,
	input  wire [10:0] filtered_ps2_key,
	output reg  [10:0] core_ps2_key,
	output reg         save_request,
	output reg         load_request
);

reg filtered_ps2_key_toggle;

initial begin
	core_ps2_key = 11'd0;
	save_request = 1'b0;
	load_request = 1'b0;
	filtered_ps2_key_toggle = 1'b0;
end

always @(posedge clk) begin
	save_request <= 1'b0;
	load_request <= 1'b0;

	if (reset) begin
		filtered_ps2_key_toggle <= filtered_ps2_key[10];
		core_ps2_key <= 11'd0;
	end else if (filtered_ps2_key_toggle != filtered_ps2_key[10]) begin
		filtered_ps2_key_toggle <= filtered_ps2_key[10];
		if (!filtered_ps2_key[8] && (filtered_ps2_key[7:0] == 8'h03)) begin
			if (filtered_ps2_key[9]) load_request <= 1'b1;
		end else if (!filtered_ps2_key[8] && (filtered_ps2_key[7:0] == 8'h0B)) begin
			if (filtered_ps2_key[9]) save_request <= 1'b1;
		end else begin
			core_ps2_key[10] <= ~core_ps2_key[10];
			core_ps2_key[9:0] <= filtered_ps2_key[9:0];
		end
	end
end

endmodule
