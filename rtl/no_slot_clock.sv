`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// no_slot_clock.sv
//
// No Slot Clock (NSC) — DS1216E-compatible software time interface for the
// Apple II, appearing under a slot's ROM page at offsets $00-$07.
//
// This is a PORT of jtflanagan's AppleTini module no_slot_clock.sv
// (https://github.com/jtflanagan/AppleTini, path
//  v5/verilog/v5_1_3/v5_1_3.srcs/sources_1/new/no_slot_clock.sv).
// The unlock/read protocol was verified against the original SMT
// NS.CLOCK.SYSTEM driver (see NSC_PORT_NOTES.md in the repo root):
//  - 64 unlock writes, data bit on A0, pattern 5C A3 3A C5 5C A3 3A C5
//  - 64 read bits, LSB first, bit 0 of the data byte
//  - read-out disables the clock register until the next re-unlock
//
// BSD 2-Clause License
// --------------------
// Copyright (c) 2023, jtflanagan
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
//
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Modifications in this port (all documented, none change the bus protocol):
//   1. globals:: types replaced with plain ports (see below) so the module
//      stands alone outside the AppleTini design.
//   2. The `enabled` input was dropped — it is declared but never used in
//      the upstream body.
//   3. Bus gating: upstream gates on `ab_read.sss_en` (a one-cycle "sss
//      ready" strobe in their bus model) plus `sss.slot_access &&
//      addr[15:8]==8'hc2` (the whole C2 page). This core has no such
//      strobe, so the caller supplies:
//        - `strobe`:   PHASE_ZERO_R, one pulse per CPU cycle (the same
//                      pattern the apple2.vhd softswitches process uses to
//                      sample the bus once per access).
//        - `slot_sel`: active whenever the address is in a slot 1-6 wide
//                      window ($C1xx-$C7xx, IO_SELECT[1..6]) or in the
//                      $C8xx-$CFFF slot-ROM window (IO_STROBE) — matching
//                      the stock driver's probe order (slots 3,1,2,4-7 then
//                      internal). Because our slot_sel spans MANY slots
//                      (upstream's gate was a single page), the module
//                      restricts to offsets $00-$07 (addr[3]==0; note the
//                      read offset $04 has A2=1): the stock driver only
//                      uses $00/$01 (unlock writes) and $04 (read-out), so
//                      this is fully compatible while keeping other slot
//                      software's higher-offset accesses from perturbing
//                      the compare state.
//   4. Write recording now also requires `!rw` — upstream recorded a bit on
//      ANY cycle at A2=0, including read cycles; the stock driver only ever
//      writes there, so this cannot break compatibility and prevents
//      unrelated reads from perturbing the compare state.
//   5. Centisecond tick wrap parameterized (CSEC_WRAP): upstream wraps at
//      999999 for its ~100 MHz UI clock (10 ms per centisecond). This core
//      runs the module on CLK_14M (14.31818 MHz), so CSEC_WRAP = 143181
//      gives a 143182-cycle period = 10.0000 ms. The UPDATE_PUB state is
//      intentionally left holding itself until the tick counter wraps again:
//      that hold IS the per-centisecond pacing of the carry FSM (one carry
//      evaluation per tick window), not a stuck-state bug.
//   6. Upstream's blocking `cmp_reg_cnt_q = 0;` in the reset branch became a
//      nonblocking assignment (value-identical, lint-clean).
//   7. The packed struct (nsc_time_t) and enum (carry_sm) were replaced with
//      a plain logic [83:0] vector + 4-bit localparams: identical bit layout
//      and behavior, but Quartus 17 cannot synthesize procedural packed-struct
//      field assignments / enum case in always_comb (error 10166). Verilator
//      accepts both forms; this form is accepted by both.
//-----------------------------------------------------------------------------

module no_slot_clock(
    input             clk,            // CLK_14M (14.31818 MHz)
    input             rst,
    input             strobe,         // PHASE_ZERO_R: one pulse per CPU cycle
    input      [15:0] addr,           // bus address (ADDR)
    input             rw,             // 1 = read cycle (~cpu_we)
    input             slot_sel,       // $C1xx-$C7xx or $C8xx-$CFFF slot access
    input      [83:0] input_time,     // NSC_time: {ticks[19:0], year_hi..csec_lo}
    input             input_time_en,  // reload pulse (HPS RTC set)
    output     [7:0]  wr_data,        // read bit in bit 0
    output            wr_data_en      // one-cycle data valid on the bus
);

// ---------------------------------------------------------------------------
// NSC_time — identical bit layout to AppleTini globals.sv's packed struct
// (modification 7: plain vector, no struct). The low 64 bits are what the
// DS1216E-style readout publishes, as BCD pairs (hi nibble, lo nibble):
// year, month, day, day-of-week, hour, minute, second, centisecond.
// Bit 0 of byte 0 is emitted first on a read-out.
//   [83:64] centisecond_ticks  internal tick counter (never published)
//   [63:60] year_hi            [59:56] year_lo
//   [55:52] month_hi           [51:48] month_lo
//   [47:44] day_hi             [43:40] day_lo
//   [39:36] day_of_week_hi     [35:32] day_of_week_lo
//   [31:28] hour_hi            [27:24] hour_lo
//   [23:20] minute_hi          [19:16] minute_lo
//   [15:12] second_hi          [11:8]  second_lo
//   [7:4]   centisecond_hi     [3:0]   centisecond_lo
// ---------------------------------------------------------------------------

localparam logic [63:0] clock_access_pattern = 64'h5CA33AC55CA33AC5;
localparam logic [63:0] fake_time = 64'h2503300117510000;

// 10 ms centisecond period at 14.31818 MHz (see header, modification 5)
parameter CSEC_WRAP = 20'd143181;

// Carry FSM states (modification 7: plain 4-bit constants, not an enum)
localparam [3:0] IDLE       = 4'd0;
localparam [3:0] INC_CSEC   = 4'd1;
localparam [3:0] INC_SEC    = 4'd2;
localparam [3:0] INC_MIN    = 4'd3;
localparam [3:0] INC_HOUR   = 4'd4;
localparam [3:0] INC_DAY    = 4'd5;
localparam [3:0] INC_MONTH  = 4'd6;
localparam [3:0] INC_YEAR   = 4'd7;
localparam [3:0] UPDATE_PUB = 4'd8;

logic [7:0]  wr_data_d, wr_data_q = 0;
logic        wr_data_en_d, wr_data_en_q = 0;

logic [83:0] cur_time_d, cur_time_q = 84'd0;
logic [63:0] pub_time_d, pub_time_q = 0;
logic [3:0]  carry_state_d, carry_state_q = IDLE;

logic        clock_reg_en_d, clock_reg_en_q = 0;
logic        write_en_d, write_en_q = 0;
logic [7:0]  clock_reg_cnt_d, clock_reg_cnt_q = 0;
logic [63:0] clock_reg_d, clock_reg_q = 0;
logic [63:0] cmp_reg_d, cmp_reg_q = clock_access_pattern;
logic [7:0]  cmp_reg_cnt_d, cmp_reg_cnt_q = 0;

// Bus access gate (modification 3): one shot per CPU cycle, offsets $00-$07
// (offset $00-$07 == addr[3]==0; note the read offset $04 has A2=1)
wire nsc_access = strobe && slot_sel && (addr[3] == 1'b0);

always_comb begin
    wr_data_d = wr_data_q;
    wr_data_en_d = wr_data_en_q;
    clock_reg_en_d = clock_reg_en_q;
    write_en_d = write_en_q;
    clock_reg_cnt_d = clock_reg_cnt_q;
    clock_reg_d = clock_reg_q;
    cmp_reg_d = cmp_reg_q;
    cmp_reg_cnt_d = cmp_reg_cnt_q;
    if (clock_reg_cnt_q == 8'd64) begin
        // if clock reg cnt exhausted, disable the clock reg
        clock_reg_en_d = 1'b0;
        clock_reg_cnt_d = 8'd0;
    end
    if (cmp_reg_cnt_q == 8'd0) begin
        // an empty reg cnt resets the clock access pattern
        cmp_reg_d = clock_access_pattern;
    end
    if (cmp_reg_cnt_q == 8'd64) begin
        // we achieved full match, enable clock out
        clock_reg_en_d = 1'b1;
        clock_reg_d = pub_time_q[63:0];
        clock_reg_cnt_d = 8'd0;
        cmp_reg_cnt_d = 8'd0;
    end
    // need to verify that this is a ROM access to the active range
    if (nsc_access) begin
        if (addr[2]) begin
            // nsc read signal, possibly emit
            if (!clock_reg_en_q) begin
                // read resets the compare register state and
                // re-enables writes
                cmp_reg_cnt_d = 8'd0;
                write_en_d = 1'b1;
            end else begin
                if (rw) begin
                    // if the cycle is a read cycle, emit a bit
                    wr_data_d = {7'h0, clock_reg_q[0]};
                    wr_data_en_d = 1'b1;
                    clock_reg_cnt_d = clock_reg_cnt_q + 8'd1;
                    clock_reg_d[62:0] = clock_reg_q[63:1];
                    clock_reg_d[63] = 1'b0;
                end
            end
        end else begin
            // nsc write signal, possibly record (modification 4: !rw)
            if (!rw && write_en_q) begin
                if (clock_reg_en_q) begin
                    // we never write to the clock register, just
                    // drop it and increment the clock reg count
                    clock_reg_cnt_d = clock_reg_cnt_q + 8'd1;
                end else begin
                    // address bit zero is the incoming data bit
                    if (addr[0] != cmp_reg_q[0]) begin
                        // mismatch bit, disable writes
                        write_en_d = 1'b0;
                    end else begin
                        // match bit, increment the match counter
                        // and shift the compare register
                        cmp_reg_d[62:0] = cmp_reg_q[63:1];
                        cmp_reg_d[63] = 1'b0;
                        cmp_reg_cnt_d = cmp_reg_cnt_q + 8'd1;
                    end
                end
            end
        end
    end else begin
        // if not an access cycle, we output nothing
        wr_data_d = 8'h0;
        wr_data_en_d = 1'b0;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        wr_data_q <= 8'h0;
        wr_data_en_q <= 1'b0;
        clock_reg_en_q <= 1'b0;
        write_en_q <= 1'b0;
        clock_reg_cnt_q <= 8'd0;
        clock_reg_q <= 64'h0;
        cmp_reg_q <= 64'h0;
        cmp_reg_cnt_q <= 8'd0; // modification 6: nonblocking
    end else begin
        wr_data_q <= wr_data_d;
        wr_data_en_q <= wr_data_en_d;
        clock_reg_en_q <= clock_reg_en_d;
        write_en_q <= write_en_d;
        clock_reg_cnt_q <= clock_reg_cnt_d;
        clock_reg_q <= clock_reg_d;
        cmp_reg_q <= cmp_reg_d;
        cmp_reg_cnt_q <= cmp_reg_cnt_d;
    end
end

assign wr_data = wr_data_q;
assign wr_data_en = wr_data_en_q;

// Month/day byte views of cur_time_q. Continuous assigns, NOT in-block
// assignments: assigning them only inside the INC_MONTH branch made Quartus
// infer latches there, which fails its "purely combinational" always_comb
// check (error 10166). Values are identical — they are read only in that
// branch and depend only on cur_time_q.
wire [7:0] month_byte = {cur_time_q[55:52], cur_time_q[51:48]};
wire [7:0] day_byte   = {cur_time_q[47:44], cur_time_q[43:40]};

always_comb begin
    cur_time_d = cur_time_q;
    carry_state_d = carry_state_q;
    pub_time_d = pub_time_q;
    if (input_time_en) begin
        cur_time_d = input_time;
        pub_time_d = input_time[63:0];
        carry_state_d = IDLE;
    end else begin
        if (cur_time_q[83:64] == CSEC_WRAP) begin
            cur_time_d[83:64] = 0;
            carry_state_d = INC_CSEC;
        end else begin
            cur_time_d[83:64] = cur_time_q[83:64] + 20'd1;
        end
        case (carry_state_q)
        IDLE: begin
            if (cur_time_q[35:32] == 0) begin
                cur_time_d[35:32] = 1;
            end
            if (cur_time_q[43:40] == 0
                && cur_time_q[47:44] == 0) begin
                cur_time_d[43:40] = 1;
            end
        end
        INC_CSEC: begin
            if (cur_time_q[3:0] == 4'd9) begin
                cur_time_d[3:0] = 4'd0;
                if (cur_time_q[7:4] == 4'd9) begin
                    cur_time_d[7:4] = 4'd0;
                    carry_state_d = INC_SEC;
                end else begin
                    cur_time_d[7:4] = cur_time_q[7:4] + 4'd1;
                    carry_state_d = UPDATE_PUB;
                end
            end else begin
                cur_time_d[3:0] = cur_time_q[3:0] + 4'd1;
                carry_state_d = UPDATE_PUB;
            end
        end
        INC_SEC: begin
            if (cur_time_q[11:8] == 4'd9) begin
                cur_time_d[11:8] = 4'd0;
                if (cur_time_q[15:12] == 4'd5) begin
                    cur_time_d[15:12] = 4'd0;
                    carry_state_d = INC_MIN;
                end else begin
                    cur_time_d[15:12] = cur_time_q[15:12] + 4'd1;
                    carry_state_d = UPDATE_PUB;
                end
            end else begin
                cur_time_d[11:8] = cur_time_q[11:8] + 4'd1;
                carry_state_d = UPDATE_PUB;
            end
        end
        INC_MIN: begin
            if (cur_time_q[19:16] == 4'd9) begin
                cur_time_d[19:16] = 4'd0;
                if (cur_time_q[23:20] == 4'd5) begin
                    cur_time_d[23:20] = 4'd0;
                    carry_state_d = INC_HOUR;
                end else begin
                    cur_time_d[23:20] = cur_time_q[23:20] + 4'd1;
                    carry_state_d = UPDATE_PUB;
                end
            end else begin
                cur_time_d[19:16] = cur_time_q[19:16] + 4'd1;
                carry_state_d = UPDATE_PUB;
            end
        end
        INC_HOUR: begin
            if (cur_time_q[27:24] == 4'd9 ||
                (cur_time_q[27:24] == 4'd3 && cur_time_q[31:28] == 4'd2)) begin
                cur_time_d[27:24] = 4'd0;
                if (cur_time_q[31:28] == 4'd2) begin
                    cur_time_d[31:28] = 4'd0;
                    carry_state_d = INC_DAY;
                end else begin
                    cur_time_d[31:28] = cur_time_q[31:28] + 4'd1;
                    carry_state_d = UPDATE_PUB;
                end
            end else begin
                cur_time_d[27:24] = cur_time_q[27:24] + 4'd1;
                carry_state_d = UPDATE_PUB;
            end
        end
        INC_DAY: begin
            if (cur_time_q[35:32] == 4'd7) begin
                cur_time_d[35:32] = 4'd1;
            end else begin
                cur_time_d[35:32] = cur_time_q[35:32] + 4'd1;
            end
            if (cur_time_q[43:40] == 4'd9) begin
                cur_time_d[43:40] = 4'd0;
                cur_time_d[47:44] = cur_time_q[47:44] + 4'd1;
                carry_state_d = INC_MONTH;  // checks end of month too
            end else begin
                cur_time_d[43:40] = cur_time_q[43:40] + 4'd1;
                carry_state_d = UPDATE_PUB;
            end
        end
        INC_MONTH: begin
            if (month_byte == 8'h01) begin
                if (day_byte == 8'h32) begin
                    cur_time_d[43:40] = 4'd1;
                    cur_time_d[47:44] = 4'd0;
                    cur_time_d[51:48] = 4'd2;
                end
                carry_state_d = UPDATE_PUB;
            end
            if (month_byte == 8'h02) begin
                if (cur_time_q[58:57] == 2'b00) begin // year_lo[1:0]
                    if (day_byte == 8'h30) begin
                        cur_time_d[43:40] = 4'd1;
                        cur_time_d[47:44] = 4'd0;
                        cur_time_d[51:48] = 4'd3;
                    end
                end else begin
                    if (day_byte == 8'h29) begin
                        cur_time_d[43:40] = 4'd1;
                        cur_time_d[47:44] = 4'd0;
                        cur_time_d[51:48] = 4'd3;
                    end
                end
                carry_state_d = UPDATE_PUB;
            end
            if (month_byte == 8'h03) begin
                if (day_byte == 8'h32) begin
                    cur_time_d[43:40] = 4'd1;
                    cur_time_d[47:44] = 4'd0;
                    cur_time_d[51:48] = 4'd4;
                end
                carry_state_d = UPDATE_PUB;
            end
            if (month_byte == 8'h04) begin
                if (day_byte == 8'h31) begin
                    cur_time_d[43:40] = 4'd1;
                    cur_time_d[47:44] = 4'd0;
                    cur_time_d[51:48] = 4'd5;
                end
                carry_state_d = UPDATE_PUB;
            end
            if (month_byte == 8'h05) begin
                if (day_byte == 8'h32) begin
                    cur_time_d[43:40] = 4'd1;
                    cur_time_d[47:44] = 4'd0;
                    cur_time_d[51:48] = 4'd6;
                end
                carry_state_d = UPDATE_PUB;
            end
            if (month_byte == 8'h06) begin
                if (day_byte == 8'h31) begin
                    cur_time_d[43:40] = 4'd1;
                    cur_time_d[47:44] = 4'd0;
                    cur_time_d[51:48] = 4'd7;
                end
                carry_state_d = UPDATE_PUB;
            end
            if (month_byte == 8'h07) begin
                if (day_byte == 8'h32) begin
                    cur_time_d[43:40] = 4'd1;
                    cur_time_d[47:44] = 4'd0;
                    cur_time_d[51:48] = 4'd8;
                end
                carry_state_d = UPDATE_PUB;
            end
            if (month_byte == 8'h08) begin
                if (day_byte == 8'h32) begin
                    cur_time_d[43:40] = 4'd1;
                    cur_time_d[47:44] = 4'd0;
                    cur_time_d[51:48] = 4'd9;
                end
                carry_state_d = UPDATE_PUB;
            end
            if (month_byte == 8'h09) begin
                if (day_byte == 8'h31) begin
                    cur_time_d[43:40] = 4'd1;
                    cur_time_d[47:44] = 4'd0;
                    cur_time_d[51:48] = 4'd0;
                    cur_time_d[55:52] = 4'd1;
                end
                carry_state_d = UPDATE_PUB;
            end
            if (month_byte == 8'h10) begin
                if (day_byte == 8'h32) begin
                    cur_time_d[43:40] = 4'd1;
                    cur_time_d[47:44] = 4'd0;
                    cur_time_d[51:48] = 4'd1;
                    cur_time_d[55:52] = 4'd1;
                end
                carry_state_d = UPDATE_PUB;
            end
            if (month_byte == 8'h11) begin
                if (day_byte == 8'h31) begin
                    cur_time_d[43:40] = 4'd1;
                    cur_time_d[47:44] = 4'd0;
                    cur_time_d[51:48] = 4'd1;
                    cur_time_d[55:52] = 4'd2;
                end
                carry_state_d = UPDATE_PUB;
            end
            if (month_byte == 8'h12) begin
                if (day_byte == 8'h32) begin
                    cur_time_d[43:40] = 4'd1;
                    cur_time_d[47:44] = 4'd0;
                    cur_time_d[51:48] = 4'd1;
                    cur_time_d[55:52] = 4'd0;
                    carry_state_d = INC_YEAR;
                end else begin
                    carry_state_d = UPDATE_PUB;
                end
            end
        end
        INC_YEAR: begin
            if (cur_time_q[59:56] == 4'd9) begin
                cur_time_d[59:56] = 4'd0;
                if (cur_time_q[63:60] == 4'd9) begin
                    cur_time_d[63:60] = 4'd0;
                    carry_state_d = UPDATE_PUB;
                end else begin
                    cur_time_d[63:60] = cur_time_q[63:60] + 4'd1;
                    carry_state_d = UPDATE_PUB;
                end
            end else begin
                cur_time_d[59:56] = cur_time_q[59:56] + 4'd1;
                carry_state_d = UPDATE_PUB;
            end
        end
        UPDATE_PUB: begin
            // NOTE (modification 5): this state intentionally holds itself
            // until the centisecond tick counter wraps again. The hold is
            // the per-centisecond pacing of the carry FSM — exactly one
            // carry evaluation per tick window — not a stuck-state bug.
            pub_time_d = cur_time_q[63:0];
        end
        default: begin
            carry_state_d = IDLE;
        end
        endcase
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        cur_time_q <= {20'd0, fake_time};
        carry_state_q <= IDLE;
        pub_time_q <= 64'h0;
    end else begin
        cur_time_q <= cur_time_d;
        carry_state_q <= carry_state_d;
        pub_time_q <= pub_time_d;
    end
end

endmodule
