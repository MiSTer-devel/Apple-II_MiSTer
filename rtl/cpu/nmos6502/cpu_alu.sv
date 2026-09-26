// Copyright (c) 2026 Jamie Blanks
//
// 65C02 ALU. Combinational: one operation per CPU cycle, well within the
// 96 MHz fabric budget at a 6 MHz clock enable.
//
// Covers ADC/SBC (binary and decimal per W65C02S, which produces valid NZ
// in decimal mode at the cost of an extra sequencer cycle), logic ops,
// shifts/rotates, increment/decrement, compare, bit test, and the Rockwell
// RMB/SMB bit set/clear used by the ST2204 BIOS.
//
// Flag outputs are "result flags"; the sequencer decides which flags each
// opcode actually writes.

module nmos6502_alu
(
	input  wire [3:0] op,        // ALU_* operation select
	input  wire [7:0] a,         // primary operand (register side)
	input  wire [7:0] b,         // secondary operand (memory side)
	input  wire       carry_in,
	input  wire       decimal,   // D flag for ADC/SBC

	output reg  [7:0] result,
	output reg        carry_out,
	output reg        overflow,
	output wire       negative,
	output wire       zero
);

	// Operation encodings (kept local; the decode table uses these values)
	localparam [3:0] ALU_ADC = 4'd0;
	localparam [3:0] ALU_SBC = 4'd1;
	localparam [3:0] ALU_AND = 4'd2;
	localparam [3:0] ALU_ORA = 4'd3;
	localparam [3:0] ALU_EOR = 4'd4;
	localparam [3:0] ALU_ASL = 4'd5;
	localparam [3:0] ALU_LSR = 4'd6;
	localparam [3:0] ALU_ROL = 4'd7;
	localparam [3:0] ALU_ROR = 4'd8;
	localparam [3:0] ALU_INC = 4'd9;
	localparam [3:0] ALU_DEC = 4'd10;
	localparam [3:0] ALU_CMP = 4'd11;   // a - b, sets carry, no store
	localparam [3:0] ALU_BIT = 4'd12;   // a & b for Z; N/V from b in sequencer
	localparam [3:0] ALU_TRB = 4'd13;   // b & ~a
	localparam [3:0] ALU_TSB = 4'd14;   // b | a
	localparam [3:0] ALU_PASS = 4'd15;  // b through (loads, transfers)

	wire        decimal_add = decimal && (op == ALU_ADC);
	wire        decimal_sub = decimal && (op == ALU_SBC);

	// Binary adder shared by ADC/SBC/CMP
	wire [7:0]  b_eff   = (op == ALU_SBC || op == ALU_CMP) ? ~b : b;
	wire        cin_eff = (op == ALU_CMP) ? 1'b1 : carry_in;
	wire [8:0]  sum     = {1'b0, a} + {1'b0, b_eff} + {8'd0, cin_eff};
	wire        bin_v   = (a[7] == b_eff[7]) && (sum[7] != a[7]);

	// Decimal adjust (W65C02S behavior: flags from the adjusted result)
	wire [4:0]  d_lo    = {1'b0, a[3:0]} + {1'b0, b_eff[3:0]} + {4'd0, cin_eff};
	wire        d_lo_c  = decimal_add ? (d_lo > 5'd9) : d_lo[4];
	// Only the low nibble of each +6 correction is kept, so the adders are
	// 4 bits wide; the nibble carries are the separate d_*_c terms.
	wire [3:0]  d_lo_adj = d_lo[3:0] + ((d_lo_c && decimal_add) ? 4'd6 : 4'd0);
	wire [4:0]  d_hi    = {1'b0, a[7:4]} + {1'b0, b_eff[7:4]} + {4'd0, d_lo_c};
	wire        d_hi_c  = (d_hi > 5'd9);
	wire [3:0]  d_hi_adj = d_hi[3:0] + (d_hi_c ? 4'd6 : 4'd0);

	// Decimal subtract (W65C02S/CMOS): correct the full binary result by
	// -$06 on low-nibble borrow and -$60 on byte borrow. The whole-byte
	// $06 subtraction may itself borrow into the high nibble (double
	// borrow), which the NMOS-style per-nibble masking gets wrong.
	wire [7:0]  s_cmos = sum[7:0] - ((~d_lo[4]) ? 8'h06 : 8'h00)
	                              - ((~sum[8])  ? 8'h60 : 8'h00);

	always @* begin
		result    = 8'h00;
		carry_out = carry_in;
		overflow  = 1'b0;
		case (op)
			ALU_ADC: begin
				if (decimal_add) begin
					result    = {d_hi_adj, d_lo_adj};
					carry_out = d_hi_c;
					// V is the overflow of the intermediate sum before
					// the high-nibble +6, i.e. bit 7 of
					// (hi << 4 | adjusted lo), which is exactly d_hi[3].
					// Taking it after the correction gets the flag wrong
					// on roughly a quarter of the operand space.
					overflow  = (a[7] == b_eff[7]) && (d_hi[3] != a[7]);
				end else begin
					result    = sum[7:0];
					carry_out = sum[8];
					overflow  = bin_v;
				end
			end
			ALU_SBC: begin
				// Decimal only changes the result; carry and overflow
				// come from the binary subtraction either way.
				result    = decimal_sub ? s_cmos : sum[7:0];
				carry_out = sum[8];
				overflow  = bin_v;
			end
			ALU_CMP: begin
				result    = sum[7:0];
				carry_out = sum[8];
			end
			ALU_AND: result = a & b;
			ALU_ORA: result = a | b;
			ALU_EOR: result = a ^ b;
			ALU_ASL: begin
				result    = {b[6:0], 1'b0};
				carry_out = b[7];
			end
			ALU_LSR: begin
				result    = {1'b0, b[7:1]};
				carry_out = b[0];
			end
			ALU_ROL: begin
				result    = {b[6:0], carry_in};
				carry_out = b[7];
			end
			ALU_ROR: begin
				result    = {carry_in, b[7:1]};
				carry_out = b[0];
			end
			ALU_INC: result = b + 8'd1;
			ALU_DEC: result = b - 8'd1;
			ALU_BIT: result = a & b;
			ALU_TRB: result = b & ~a;
			ALU_TSB: result = b | a;
			ALU_PASS: result = b;
			default: result = b;
		endcase
	end

	assign negative = result[7];
	assign zero     = (result == 8'h00);

endmodule
