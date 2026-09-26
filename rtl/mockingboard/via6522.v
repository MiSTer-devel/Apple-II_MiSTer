`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
//
// Engineer:	Thomas Skibo 
// 
// Create Date:	Sep 24, 2011
//
// Module Name: via6522
//
// Description:
//
//	A simple implementation of the 6522 Versatile Interface Adapter (VIA).
//	Tri-state lines aren't used.  Instead,  All PIA I/O signals have
//	seperate "in" and "out" signals.  Wire or ignore appropriately.
//
//	A seperate "slow clock" (a synchronous pulse) runs the timers.
//	Typically, it's 1Mhz.
//
/////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2011, Thomas Skibo.  All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
// * Redistributions of source code must retain the above copyright
//   notice, this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
// * The names of contributors may not be used to endorse or promote products
//   derived from this software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL Thomas Skibo OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
// LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
// OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
// SUCH DAMAGE.
//
//////////////////////////////////////////////////////////////////////////////

module via6522
(
	output reg [7:0] data_out,	// cpu interface
	input      [7:0] data_in,
	input      [3:0] addr,
	input            strobe,
	input            we,

	output       irq,
 
	output [7:0] porta_out,
	input      [7:0] porta_in,
	output [7:0] portb_out,
	input      [7:0] portb_in,

	input            ca1_in,
	output       ca2_out,
	input            ca2_in,
	output       cb1_out,
	input            cb1_in,
	output       cb2_out,
	input            cb2_in,

	input            ce,
	input            clk,
	input            reset
);

// Register address offsets
parameter [3:0]
	ADDR_PORTB     = 4'h0,
	ADDR_PORTA     = 4'h1,
	ADDR_DDRB      = 4'h2,
	ADDR_DDRA      = 4'h3,
	ADDR_TIMER1_LO = 4'h4,
	ADDR_TIMER1_HI = 4'h5,
	ADDR_TIMER1_LATCH_LO = 4'h6,
	ADDR_TIMER1_LATCH_HI = 4'h7,
	ADDR_TIMER2_LO = 4'h8,
	ADDR_TIMER2_HI = 4'h9,
	ADDR_SR        = 4'ha,
	ADDR_ACR       = 4'hb,
	ADDR_PCR       = 4'hc,
	ADDR_IFR       = 4'hd,
	ADDR_IER       = 4'he,
	ADDR_PORTA_NH  = 4'hf;

wire	wr_strobe = strobe && we;
wire	rd_strobe = strobe && !we;

// Clocking contract (equivalence harness and Mockingboard): `ce` marks the
// golden reference's falling slot. On the Mockingboard it is driven by
// VIA_CE_F (= PHASE_ZERO_R), the same pulse the golden via6522.vhd uses for
// its `falling` input; the complement represents the golden's `rising` slot.
// Internal state machine aligned to rtl/mockingboard/via6522.vhd (golden).
wire falling = ce;
wire rising  = ~ce;

///////////////////////////////////////////////////
// ACR/PCR bit aliases (golden alias declarations)
wire        tmr_a_output_en    = acr[7];
wire        tmr_a_freerun      = acr[6];
wire        tmr_b_count_mode   = acr[5];
wire        shift_dir          = acr[4];
wire [1:0]  shift_clk_sel      = acr[3:2];
wire [2:0]  shift_mode_control = acr[4:2];

wire        cb2_edge_select    = pcr[6];
wire        cb2_no_irq_clr     = pcr[5];
wire [1:0]  cb2_out_mode       = pcr[6:5];
wire        cb1_edge_select    = pcr[4];
wire        ca2_edge_select    = pcr[2];
wire        ca2_no_irq_clr     = pcr[1];
wire [1:0]  ca2_out_mode       = pcr[2:1];
wire        ca1_edge_select    = pcr[0];

///////////////////////////////////////////////////
// Control registers (written in the main process below)
reg [7:0] 	acr;
reg [7:0] 	pcr;

///////////////////////////////////////////////////
// PIO output registers and DDRs (golden pio_i record)
reg [7:0] 	pra;
reg [7:0] 	ddra;
reg [7:0] 	prb;
reg [7:0] 	ddrb;

// One-edge-delayed input samples (golden port_a_c/port_b_c)
reg [7:0] 	port_a_c;
reg [7:0] 	port_b_c;

always @(posedge clk) begin
	port_a_c <= porta_in;
	port_b_c <= portb_in;
end

// Input latch emulation (golden ira/irb): track the delayed input unless
// latched; re-latch on the CA1/CB1 event edge.
reg [7:0] 	ira;
reg [7:0] 	irb;

always @(posedge clk) begin
	if (!acr[0] || ca1_event) ira <= port_a_c;
	if (!acr[1] || cb1_event) irb <= port_b_c;
end

///////////////////////////////////////////////////
// CA1/CA2/CB1/CB2 edge detect flip-flops (golden caX_c/caX_d, both phases)
reg 	ca1_c, ca1_d;
reg 	ca2_c, ca2_d;
reg 	cb1_c, cb1_d;
reg 	cb2_c, cb2_d;

always @(posedge clk) begin
	ca1_c <= ca1_in;  ca1_d <= ca1_c;
	ca2_c <= ca2_in;  ca2_d <= ca2_c;
	cb1_c <= cb1_in;  cb1_d <= cb1_c;
	cb2_c <= cb2_in;  cb2_d <= cb2_c;
end

// Active transition events (combinational, golden irq_events bits)
wire	ca1_event = (ca1_c ^ ca1_d) & (ca1_d ^ ca1_edge_select);
wire	ca2_event = (ca2_c ^ ca2_d) & (ca2_d ^ ca2_edge_select);
wire	cb1_event = (cb1_c ^ cb1_d) & (cb1_d ^ cb1_edge_select);
wire	cb2_event = (cb2_c ^ cb2_d) & (cb2_d ^ cb2_edge_select);

///////////////////////////////////////////////////
// CA2/CB2 handshake and pulse output registers (golden)
reg 	ca2_handshake_o;
reg 	ca2_pulse_o;
reg 	cb2_handshake_o;
reg 	cb2_pulse_o;

always @(posedge clk) begin
	if (reset) begin
		ca2_handshake_o <= 1'b1;
		ca2_pulse_o     <= 1'b1;
		cb2_handshake_o <= 1'b1;
		cb2_pulse_o     <= 1'b1;
	end else begin
		if (ca1_event) ca2_handshake_o <= 1'b1;
		else if ((strobe && addr == ADDR_PORTA) && falling) ca2_handshake_o <= 1'b0;

		if (falling)
			ca2_pulse_o <= (strobe && addr == ADDR_PORTA) ? 1'b0 : 1'b1;

		if (cb1_event) cb2_handshake_o <= 1'b1;
		else if ((strobe && addr == ADDR_PORTB) && falling) cb2_handshake_o <= 1'b0;

		if (falling)
			cb2_pulse_o <= (strobe && addr == ADDR_PORTB) ? 1'b0 : 1'b1;
	end
end

// CA2 output (golden with-select on pcr(2:1))
assign ca2_out = (ca2_out_mode == 2'b00) ? ca2_handshake_o :
                 (ca2_out_mode == 2'b01) ? ca2_pulse_o :
                 (ca2_out_mode == 2'b10) ? 1'b0 :
                                                 1'b1;

///////////////////////////////////////////////////
// Interrupt flags and mask (golden irq_flags/irq_mask)
reg [6:0] 	irq_flags;
reg [6:0] 	irq_mask;

wire [6:0] 	irq_events = { timer_a_event, timer_b_event, cb1_event,
	                         cb2_event, serial_event, ca1_event, ca2_event };

// IRQ output is combinational in the golden (OR of flags and mask)
wire 	irq_out = |(irq_flags & irq_mask);
assign irq = irq_out;

reg 	trigger_serial;

// Main process: mirrors the golden's main clocked process. The textual
// order matters (last nonblocking assignment wins), as in the VHDL.
always @(posedge clk) begin
	// Interrupt logic
	irq_flags <= irq_flags | irq_events;

	if (falling) trigger_serial <= 1'b0;

	// Writes (golden: wen and falling)
	if (wr_strobe && falling) begin
		case (addr)
			ADDR_PORTB: begin             // ORB
				prb <= data_in;
				if (!cb2_no_irq_clr) irq_flags[3] <= 1'b0;
				irq_flags[4] <= 1'b0;
			end
			ADDR_PORTA: begin             // ORA
				pra <= data_in;
				if (!ca2_no_irq_clr) irq_flags[0] <= 1'b0;
				irq_flags[1] <= 1'b0;
			end
			ADDR_DDRB: ddrb <= data_in;
			ADDR_DDRA: ddra <= data_in;
			ADDR_TIMER1_LO:      timer_a_latch[7:0] <= data_in; // counter addr, write=latch LO
			ADDR_TIMER1_HI: begin
				timer_a_latch[15:8] <= data_in;
				irq_flags[6] <= 1'b0;
			end
			ADDR_TIMER1_LATCH_LO: timer_a_latch[7:0] <= data_in;
			ADDR_TIMER1_LATCH_HI: begin
				timer_a_latch[15:8] <= data_in;
				irq_flags[6] <= 1'b0;
			end
			ADDR_TIMER2_LO: timer_b_latch[7:0] <= data_in;
			ADDR_TIMER2_HI: irq_flags[5] <= 1'b0; // counter load happens in the timer B block
			ADDR_SR: begin
				irq_flags[2] <= 1'b0;
				if (!shift_active) trigger_serial <= 1'b1;
			end
			ADDR_ACR: acr <= data_in;
			ADDR_PCR: pcr <= data_in;
			ADDR_IFR: irq_flags <= irq_flags & ~data_in[6:0];
			ADDR_IER: irq_mask <= data_in[7] ? (irq_mask | data_in[6:0])
			                                       : (irq_mask & ~data_in[6:0]);
			ADDR_PORTA_NH: pra <= data_in; // ORA no handshake
		endcase
	end

	// Read actions (golden: ren and falling)
	if (rd_strobe && falling) begin
		case (addr)
			ADDR_PORTB: begin
				if (!cb2_no_irq_clr) irq_flags[3] <= 1'b0;
				irq_flags[4] <= 1'b0;
			end
			ADDR_PORTA: begin
				if (!ca2_no_irq_clr) irq_flags[0] <= 1'b0;
				irq_flags[1] <= 1'b0;
			end
			ADDR_TIMER1_LO: irq_flags[6] <= 1'b0; // TA LO counter read
			ADDR_TIMER2_LO: irq_flags[5] <= 1'b0; // TB LO counter read
			ADDR_SR: begin
				irq_flags[2] <= 1'b0;
				trigger_serial <= 1'b1;
			end
			default: ; // golden 'when others => null'
		endcase
	end

	if (reset) begin
		pra            <= 8'h00;
		ddra           <= 8'h00;
		prb            <= 8'h00;
		ddrb           <= 8'h00;
		irq_mask       <= 7'h00;
		irq_flags      <= 7'h00;
		acr            <= 8'h00;
		pcr            <= 8'h00;
		timer_a_latch  <= 16'h5550;
		timer_b_latch  <= 16'h5550;
		trigger_serial <= 1'b0;
	end
end

///////////////////////////////////////////////////
// Read data mux - registered on every clock edge, as in the golden.
always @(posedge clk) begin
	data_out <= 8'h00;
	case (addr)
		ADDR_PORTB:           data_out <= (prb & ddrb) | (irb & ~ddrb);
		ADDR_PORTA:           data_out <= ira;
		ADDR_DDRB:            data_out <= ddrb;
		ADDR_DDRA:            data_out <= ddra;
		ADDR_TIMER1_LO:       data_out <= timer_a_count[7:0];
		ADDR_TIMER1_HI:       data_out <= timer_a_count[15:8];
		ADDR_TIMER1_LATCH_LO: data_out <= timer_a_latch[7:0];
		ADDR_TIMER1_LATCH_HI: data_out <= timer_a_latch[15:8];
		ADDR_TIMER2_LO:       data_out <= timer_b_count[7:0];
		ADDR_TIMER2_HI:       data_out <= timer_b_count[15:8];
		ADDR_SR:              data_out <= shift_reg;
		ADDR_ACR:             data_out <= acr;
		ADDR_PCR:             data_out <= pcr;
		ADDR_IFR:             data_out <= {irq_out, irq_flags};
		ADDR_IER:             data_out <= {1'b0, irq_mask};
		ADDR_PORTA_NH:        data_out <= ira;
		default:              ; // golden 'when others => null'; 8'h00 default above
	endcase
end

///////////////////////////////////////////////////
// PIO outputs (golden continuous assigns)
assign porta_out      = pra;
assign portb_out[6:0] = prb[6:0];
assign portb_out[7]   = tmr_a_output_en ? timer_a_out : prb[7];

///////////////////////////////////////////////////
// Timer A (golden tmr_a block)
reg [15:0] 	timer_a_count;
reg [15:0] 	timer_a_latch;
reg 		timer_a_reload;
reg 		timer_a_oneshot_trig;
reg 		timer_a_toggle;

wire 	write_t1c_h   = (addr == ADDR_TIMER1_HI) && wr_strobe && falling;
wire 	timer_a_event = rising && timer_a_reload && (tmr_a_freerun || timer_a_oneshot_trig);
wire 	timer_a_out   = timer_a_toggle;

always @(posedge clk) begin
	if (falling) begin
		if (timer_a_reload) begin
			timer_a_count        <= timer_a_latch;
			timer_a_reload       <= 1'b0;
			timer_a_oneshot_trig <= 1'b0;
		end else begin
			if (timer_a_count == 16'h0000) timer_a_reload <= 1'b1;
			// Timer keeps counting in both free run and one shot.
			timer_a_count <= timer_a_count - 16'h0001;
		end
	end

	if (rising && timer_a_event) timer_a_toggle <= ~timer_a_toggle;

	if (write_t1c_h) begin
		timer_a_toggle       <= 1'b0;
		timer_a_count        <= {data_in, timer_a_latch[7:0]};
		timer_a_reload       <= 1'b0;
		timer_a_oneshot_trig <= 1'b1;
	end

	if (reset) begin
		timer_a_toggle       <= 1'b1;
		timer_a_count        <= 16'h5550; // golden latch_reset_pattern
		timer_a_reload       <= 1'b0;
		timer_a_oneshot_trig <= 1'b0;
	end
end

///////////////////////////////////////////////////
// Timer B (golden tmr_b block)
reg [15:0] 	timer_b_count;
reg [15:0] 	timer_b_latch;
reg 		timer_b_reload_lo;
reg 		timer_b_oneshot_trig;
reg 		timer_b_timeout;
reg 		timer_b_tick;
reg 		pb6_c, pb6_d;

wire 	write_t2c_h       = (addr == ADDR_TIMER2_HI) && wr_strobe && falling;
wire 	timer_b_event     = rising && timer_b_timeout;
wire 	timer_b_decrement = tmr_b_count_mode ? (pb6_d && !pb6_c) : 1'b1;

always @(posedge clk) begin
	if (rising) begin
		pb6_c <= portb_in[6];
		pb6_d <= pb6_c;
	end

	if (falling) begin
		timer_b_timeout <= 1'b0;
		timer_b_tick    <= 1'b0;

		if (timer_b_decrement) begin
			if (timer_b_count == 16'h0000) begin
				if (timer_b_oneshot_trig) begin
					timer_b_oneshot_trig <= 1'b0;
					timer_b_timeout      <= 1'b1;
				end
			end
			if (timer_b_count[7:0] == 8'h00) begin
				case (shift_mode_control)
					3'b001, 3'b101, 3'b100: begin // serial shift clock modes
						timer_b_reload_lo <= 1'b1;
						timer_b_tick      <= 1'b1;
					end
					default: ; // golden 'when others => null'
				endcase
			end
			timer_b_count <= timer_b_count - 16'h0001;
		end

		if (timer_b_reload_lo) begin
			timer_b_count[7:0] <= timer_b_latch[7:0];
			timer_b_reload_lo  <= 1'b0;
		end
	end

	if (write_t2c_h) begin
		timer_b_count        <= {data_in, timer_b_latch[7:0]};
		timer_b_oneshot_trig <= 1'b1;
	end

	if (reset) begin
		timer_b_count        <= 16'h5550; // golden latch_reset_pattern
		timer_b_reload_lo    <= 1'b0;
		timer_b_oneshot_trig <= 1'b0;
	end
end

///////////////////////////////////////////////////
// Serial port / shift register (golden ser block)
reg [7:0] 	shift_reg;
reg 		shift_active;
reg [2:0] 	bit_cnt;
reg 		shift_clock;
reg 		shift_clock_d;
reg 		ser_cb2_o;
reg 		shift_tick_r;
reg 		shift_tick_f;
reg 		ser_cb2_c; // ser block's own R-phase sample of cb2_in

wire 	serport_en = shift_dir | shift_clk_sel[1] | shift_clk_sel[0];

// shift_pulse (golden combinational process), forced low when inactive
wire 	shift_pulse_raw = (shift_clk_sel == 2'b10) ? 1'b1 :
	                      (shift_clk_sel == 2'b11) ? (shift_clock & ~shift_clock_d) :
	                                                timer_b_tick; // "00" and "01"
wire 	shift_pulse = shift_active ? shift_pulse_raw : 1'b0;

// Serial IRQ event (golden: shift_tick_r and not shift_active and rising)
wire 	serial_event = shift_tick_r && !shift_active && rising;

// R-phase: CB2 input sample, shift clock, CB1 output register, serial CB2 out
always @(posedge clk) begin
	if (rising) begin
		ser_cb2_c <= cb2_in;

		if (!shift_active)                shift_clock <= 1'b1;
		else if (shift_clk_sel == 2'b11)  shift_clock <= cb1_in;
		else if (shift_pulse)             shift_clock <= ~shift_clock;

		shift_clock_d <= shift_clock;

		if (shift_tick_f) ser_cb2_o <= shift_reg[7];
	end

	if (reset) begin
		shift_clock   <= 1'b1;
		shift_clock_d <= 1'b1;
		ser_cb2_o     <= 1'b1;
	end
end

// F-phase: tick detectors and register contents
always @(posedge clk) begin
	if (reset) begin
		shift_reg    <= 8'hFF;
		shift_tick_r <= 1'b0;
		shift_tick_f <= 1'b0;
	end else if (falling) begin
		shift_tick_r <= ~shift_clock_d & shift_clock;
		shift_tick_f <= shift_clock_d & ~shift_clock;

		if (wr_strobe && addr == ADDR_SR) shift_reg <= data_in;
		else if (shift_tick_r) begin
			if (shift_dir) shift_reg <= {shift_reg[6:0], shift_reg[7]}; // output
			else           shift_reg <= {shift_reg[6:0], ser_cb2_c};   // input
		end
	end
end

// F-phase: active state machine
always @(posedge clk) begin
	if (falling) begin
		if (!shift_active) begin
			if (trigger_serial) begin
				bit_cnt      <= 3'd7;
				shift_active <= 1'b1;
			end
		end else begin
			if (shift_clk_sel == 2'b00) begin
				shift_active <= shift_dir; // mode 000 goes inactive when dir is 0
			end else if (shift_pulse && shift_clock) begin
				if (bit_cnt == 3'd0) shift_active <= 1'b0;
				else                 bit_cnt      <= bit_cnt - 3'd1;
			end
		end
	end

	if (reset) begin
		shift_active <= 1'b0;
		bit_cnt      <= 3'd0;
	end
end

// CB1 output is the delayed shift clock (golden cb1_o = shift_clock_d)
assign cb1_out = shift_clock_d;

// CB2 output: serial register MSB when serport enabled, else handshake/pulse
wire 	hs_cb2_o = (cb2_out_mode == 2'b00) ? cb2_handshake_o :
	              (cb2_out_mode == 2'b01) ? cb2_pulse_o :
	              (cb2_out_mode == 2'b10) ? 1'b0 :
	                                             1'b1;
assign cb2_out = serport_en ? ser_cb2_o : hs_cb2_o;


endmodule // via6522
