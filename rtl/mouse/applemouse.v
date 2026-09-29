//-------------------------------------------------------------------------------
//
// Apple Mouse Card
//
// (c)2025 Gyorgy Szombathelyi
//
// jt6805 CPU by Jose Tejada
// https://github.com/jotego/jtcores/tree/master/modules/jt680x
//
// pia6821.vhd
// Author : John E. Kent
//
//-------------------------------------------------------------------------------

module applemouse(
    CLK_14M,
    CLK_2M,
    PHASE_ZERO,
    IO_SELECT,      // e.g., C700 - C7FF ROM
    IO_STROBE,      // e.g., C800 - CFFF I/O locations
    DEVICE_SELECT,
    RESET,
    A,
    D_IN,           // From 6502
    D_OUT,          // To 6502
    RNW,
    OE,
    IRQ_N,

    // MOUSE
    STROBE,
    X,
    Y,
    SCALE,
    BUTTON
);
    input         CLK_14M;
    input         CLK_2M;
    input         PHASE_ZERO;
    input         IO_SELECT;
    input         IO_STROBE;
    input         DEVICE_SELECT;
    input         RESET;
    input  [15:0] A;
    input  [7:0]  D_IN;
    output [7:0]  D_OUT;
    input         RNW;
    output        OE;
    output        IRQ_N;

    // MOUSE
    input         STROBE;
    input  [8:0]  X;
    input  [8:0]  Y;
    input  [1:0]  SCALE;
    input         BUTTON;

    wire [10:0]   rom_addr;
    wire [7:0]    rom_dout;

    wire [10:0]   mcu_rom_addr;
    wire [7:0]    mcu_rom_dout;

    wire [7:0]    pia_dout;
    wire [7:0]    pia_pa_in;
    wire [7:0]    pia_pa_out;
    wire [7:0]    pia_pb_in;
    wire [7:0]    pia_pb_out;

    wire [7:0]    mcu_pa_in;
    wire [7:0]    mcu_pa_out;
    reg  [7:0]    mcu_pb_in;
    wire [7:0]    mcu_pb_out;
    wire [3:0]    mcu_pc_in;
    wire [3:0]    mcu_pc_out;

    reg           clk_2m_d;
    reg           clk_2en;

    reg           pressed;
    // Signed pulse backlog, separate from the 9-bit host packet format.
    // A large report must not clip just because it arrived in one packet.
    reg signed [31:0] mx;
    reg signed [31:0] my;
    wire          mcu_wr;
    wire          mcu_rd;
    wire [12:0]   mcu_addr;
    // 341-0269 polls movement with LDA $01 at $0403 ($0404 is its operand);
    // tag the ROM fetch so other port-B reads can't consume queued movement.
    reg           motion_read_armed;
    wire          mcu_pb_read = mcu_rd && mcu_addr == 13'd1
                                && motion_read_armed;

    always @(posedge CLK_14M) begin
        if (RESET)
            motion_read_armed <= 1'b0;
        else if (mcu_rd)
            motion_read_armed <= (mcu_addr == 13'h0404);
    end

    // Each accepted pin phase transition is one coordinate count in 341-0269.
    // SCALE selects x1, x2, x4 or x8; the top-level default is x1.
    function automatic [31:0] stepped_backlog;
        input signed [31:0] value;
        begin
            if (value < 0)
                stepped_backlog = value + 32'sd1;
            else if (value != 0)
                stepped_backlog = value - 32'sd1;
            else
                stepped_backlog = value;
        end
    endfunction

    function automatic [31:0] saturating_add_scaled;
        input signed [31:0] backlog;
        input [8:0] delta;
        input [1:0] scale;
        reg signed [32:0] sum;
        begin
            sum = $signed({backlog[31], backlog})
                + ($signed({{24{delta[8]}}, delta}) <<< scale);
            if (sum > 33'sd2147483647)
                saturating_add_scaled = 32'h7fffffff;
            else if (sum < -33'sd2147483648)
                saturating_add_scaled = 32'h80000000;
            else
                saturating_add_scaled = sum[31:0];
        end
    endfunction

    always @(posedge CLK_14M)
    begin
        if (RESET == 1'b1)
        begin
            pressed <= 1'b0;
            mx      <= 32'sd0;
            my      <= 32'sd0;
            mcu_pb_in[3:0] <= 4'b0;
        end
        else
        begin
            if (mcu_pb_read)
            begin
                if (mx[31] == 1'b1)
                begin
                    mx    <= mx + 32'sd1;
                    mcu_pb_in[1] <= ~mcu_pb_in[1];
                    mcu_pb_in[0] <= 1'b0;
                end
                else if (mx != 32'sd0)
                begin
                    mx    <= mx - 32'sd1;
                    mcu_pb_in[1] <= ~mcu_pb_in[1];
                    mcu_pb_in[0] <= 1'b1;
                end

                if (my[31] == 1'b1)
                begin
                    my    <= my + 32'sd1;
                    mcu_pb_in[3] <= ~mcu_pb_in[3];
                    mcu_pb_in[2] <= 1'b1;
                end
                else if (my != 32'sd0)
                begin
                    my    <= my - 32'sd1;
                    mcu_pb_in[3] <= ~mcu_pb_in[3];
                    mcu_pb_in[2] <= 1'b0;
                end
            end

            if (STROBE == 1'b1)
            begin
                pressed <= BUTTON;
                mx      <= saturating_add_scaled(mcu_pb_read ? stepped_backlog(mx) : mx, X, SCALE);
                my      <= saturating_add_scaled(mcu_pb_read ? stepped_backlog(my) : my, Y, SCALE);
            end
        end
    end

    assign D_OUT = (DEVICE_SELECT == 1'b1) ? pia_dout : rom_dout;
    assign OE = IO_SELECT | DEVICE_SELECT;
    assign IRQ_N = mcu_pb_out[6];

    pia6821 pia(
        .clk(CLK_14M),
        .rst(RESET),
        .cs(DEVICE_SELECT),
        .rw(RNW),
        .addr(A[1:0]),
        .data_in(D_IN),
        .data_out(pia_dout),
        .irqa(),
        .irqb(),
        .pa_i(pia_pa_in),
        .pa_o(pia_pa_out),
        .pa_oe(),
        .ca1(1'b1),
        .ca2_i(1'b1),
        .ca2_o(),
        .ca2_oe(),
        .pb_i(pia_pb_in),
        .pb_o(pia_pb_out),
        .pb_oe(),
        .cb1(1'b1),
        .cb2_i(1'b1),
        .cb2_o(),
        .cb2_oe()
    );

    always @(posedge CLK_14M)
    begin
        clk_2m_d <= CLK_2M;
        if (RESET)
            clk_2en <= 1'b0;
        else
            clk_2en <= CLK_2M && !clk_2m_d;
    end

    jtframe_6805mcu mcu(
        .rst(RESET),
        .clk(CLK_14M),
        .cen(clk_2en),
        .wr(mcu_wr),
        .rd(mcu_rd),
        .addr(mcu_addr),
        .dout(),
        .irq(1'b0),
        .timer(1'b1),

        .pa_in(mcu_pa_in),
        .pa_out(mcu_pa_out),
        .pb_in(mcu_pb_in),
        .pb_out(mcu_pb_out),
        .pc_in(mcu_pc_in),
        .pc_out(mcu_pc_out),

        .rom_addr(mcu_rom_addr),
        .rom_data(mcu_rom_dout),
        .rom_cs()
    );

    assign mcu_pa_in = pia_pa_out;
    assign pia_pa_in = mcu_pa_out;

    assign mcu_pc_in = pia_pb_out[7:4];
    assign pia_pb_in[7:4] = mcu_pc_out;
    assign pia_pb_in[3:1] = 3'b111;
    assign pia_pb_in[0] = D_IN[0];

    always @(*)
    begin
        mcu_pb_in[7]   = ~pressed;
        mcu_pb_in[6]   = 1'b1;
        mcu_pb_in[5:4] = 2'b11;
    end

    // 341-0270-C
    assign rom_addr = {pia_pb_out[3:1], A[7:0]};
    applemouse_rom rom(
        .addr(rom_addr),
        .clk(CLK_14M),
        .data(rom_dout)
    );

    // 341-0269
    applemouse_mcu_rom mcu_rom(
        .addr(mcu_rom_addr),
        .clk(CLK_14M),
        .data(mcu_rom_dout)
    );

endmodule
