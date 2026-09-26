//===========================================================================--
//
// S Y N T H E Z I A B L E I/O Port C O R E
//
// www.OpenCores.Org - May 2004
// This core adheres to the GNU public license
//
// File name : pia6821.v
//
// Purpose : Implements 2 x 8 bit parallel I/O ports
// with programmable data direction registers
//
// Author : John E. Kent
//
// Verilog port of pia6821.vhd (v0.0.3, Slingshot)
//
// Memory Map
//
// IO + $00 - Port A Data & Direction register
// IO + $01 - Port A Control register
// IO + $02 - Port B Data & Direction register
// IO + $03 - Port B Control Register
//
//===========================================================================--

module pia6821(
    clk,
    rst,
    cs,
    rw,
    addr,
    data_in,
    data_out,
    irqa,
    irqb,
    pa_i,
    pa_o,
    pa_oe,
    ca1,
    ca2_i,
    ca2_o,
    ca2_oe,
    pb_i,
    pb_o,
    pb_oe,
    cb1,
    cb2_i,
    cb2_o,
    cb2_oe
);
    input        clk;
    input        rst;
    input        cs;
    input        rw;
    input  [1:0] addr;
    input  [7:0] data_in;
    output reg [7:0] data_out;
    output       irqa;
    output       irqb;
    input  [7:0] pa_i;
    output [7:0] pa_o;
    output [7:0] pa_oe;
    input        ca1;
    input        ca2_i;
    output       ca2_o;
    output       ca2_oe;
    input  [7:0] pb_i;
    output [7:0] pb_o;
    output [7:0] pb_oe;
    input        cb1;
    input        cb2_i;
    output       cb2_o;
    output       cb2_oe;

    reg [7:0] porta_ddr;
    reg [7:0] porta_data;
    reg [5:0] porta_ctrl;
    wire      porta_read;

    reg [7:0] portb_ddr;
    reg [7:0] portb_data;
    reg [5:0] portb_ctrl;
    wire      portb_read;
    reg       portb_write;

    reg       ca1_del;
    reg       ca1_rise;
    reg       ca1_fall;
    wire      ca1_edge;
    reg       irqa1;

    reg       ca2_del;
    reg       ca2_rise;
    reg       ca2_fall;
    wire      ca2_edge;
    reg       irqa2;
    reg       ca2_out;

    reg       cb1_del;
    reg       cb1_rise;
    reg       cb1_fall;
    wire      cb1_edge;
    reg       irqb1;

    reg       cb2_del;
    reg       cb2_rise;
    reg       cb2_fall;
    wire      cb2_edge;
    reg       irqb2;
    reg       cb2_out;

    //--------------------------------
    // read I/O port
    //--------------------------------
    wire [7:0] pa_read_data;
    wire [7:0] pb_read_data;

    assign pa_read_data = porta_ctrl[2] ? pa_i : porta_ddr;
    assign porta_read   = porta_ctrl[2] & cs;

    assign pb_read_data = portb_ctrl[2] ? ((portb_ddr & portb_data) | (~portb_ddr & pb_i)) : portb_ddr;
    assign portb_read   = portb_ctrl[2] & cs;

    always @(*)
    begin: pia_read
        case (addr)
            2'b00 : data_out = pa_read_data;
            2'b01 : data_out = {irqa1, irqa2, porta_ctrl};
            2'b10 : data_out = pb_read_data;
            2'b11 : data_out = {irqb1, irqb2, portb_ctrl};
            default : data_out = 8'b0;
        endcase
    end

    //---------------------------------
    // Write I/O ports
    //---------------------------------
    always @(posedge clk or posedge rst)
    begin: pia_write
        if (rst == 1'b1)
        begin
            porta_ddr  <= 8'b0;
            porta_data <= 8'b0;
            porta_ctrl <= 6'b0;
            portb_ddr  <= 8'b0;
            portb_data <= 8'b0;
            portb_ctrl <= 6'b0;
            portb_write <= 1'b0;
        end
        else if (cs == 1'b1 && rw == 1'b0)
        begin
            case (addr)
                2'b00 :
                    if (porta_ctrl[2] == 1'b0)
                    begin
                        porta_ddr  <= data_in;
                        porta_data <= porta_data;
                    end
                    else
                    begin
                        porta_ddr  <= porta_ddr;
                        porta_data <= data_in;
                    end
                2'b01 :
                    porta_ctrl <= data_in[5:0];
                2'b10 :
                    if (portb_ctrl[2] == 1'b0)
                    begin
                        portb_ddr  <= data_in;
                        portb_data <= portb_data;
                    end
                    else
                    begin
                        portb_ddr  <= portb_ddr;
                        portb_data <= data_in;
                    end
                2'b11 :
                    portb_ctrl <= data_in[5:0];
                default : ;
            endcase
            portb_write <= (addr == 2'b10 && portb_ctrl[2] == 1'b1) ? 1'b1 : 1'b0;
        end
        else
        begin
            portb_write <= 1'b0;
        end
    end

    //---------------------------------
    // direction control port a
    //---------------------------------
    assign pa_o  = porta_ddr & porta_data;
    assign pa_oe = porta_ddr;

    //---------------------------------
    // CA1 Edge detect
    //---------------------------------
    always @(negedge clk or posedge rst)
    begin: ca1_input
        if (rst == 1'b1)
        begin
            ca1_del  <= 1'b0;
            ca1_rise <= 1'b0;
            ca1_fall <= 1'b0;
            irqa1    <= 1'b0;
        end
        else
        begin
            ca1_del  <= ca1;
            ca1_rise <= (~ca1_del) & ca1;
            ca1_fall <= ca1_del & (~ca1);
            if (ca1_edge == 1'b1)
                irqa1 <= 1'b1;
            else if (porta_read == 1'b1)
                irqa1 <= 1'b0;
        end
    end

    assign ca1_edge = porta_ctrl[1] ? ca1_rise : ca1_fall;

    //---------------------------------
    // CA2 Edge detect
    //---------------------------------
    always @(negedge clk or posedge rst)
    begin: ca2_input
        if (rst == 1'b1)
        begin
            ca2_del  <= 1'b0;
            ca2_rise <= 1'b0;
            ca2_fall <= 1'b0;
            irqa2    <= 1'b0;
        end
        else
        begin
            ca2_del  <= ca2_i;
            ca2_rise <= (~ca2_del) & ca2_i;
            ca2_fall <= ca2_del & (~ca2_i);
            if (porta_ctrl[5] == 1'b0 && ca2_edge == 1'b1)
                irqa2 <= 1'b1;
            else if (porta_read == 1'b1)
                irqa2 <= 1'b0;
        end
    end

    assign ca2_edge = porta_ctrl[4] ? ca2_rise : ca2_fall;

    //---------------------------------
    // CA2 output control
    //---------------------------------
    always @(negedge clk or posedge rst)
    begin: ca2_output
        if (rst == 1'b1)
            ca2_out <= 1'b0;
        else
            case (porta_ctrl[5:3])
                3'b100 :		// read PA clears, CA1 edge sets
                    if (porta_read == 1'b1)
                        ca2_out <= 1'b0;
                    else if (ca1_edge == 1'b1)
                        ca2_out <= 1'b1;
                3'b101 :		// read PA clears, E sets
                    ca2_out <= ~porta_read;
                3'b110 :		// set low
                    ca2_out <= 1'b0;
                3'b111 :		// set high
                    ca2_out <= 1'b1;
                default :		// no change
                    ;
            endcase
    end

    //---------------------------------
    // CA2 direction control
    //---------------------------------
    assign ca2_o  = porta_ctrl[5] ? ca2_out : 1'b0;
    assign ca2_oe = porta_ctrl[5];

    //---------------------------------
    // direction control port b
    //---------------------------------
    assign pb_o  = portb_ddr & portb_data;
    assign pb_oe = portb_ddr;

    //---------------------------------
    // CB1 Edge detect
    //---------------------------------
    always @(negedge clk or posedge rst)
    begin: cb1_input
        if (rst == 1'b1)
        begin
            cb1_del  <= 1'b0;
            cb1_rise <= 1'b0;
            cb1_fall <= 1'b0;
            irqb1    <= 1'b0;
        end
        else
        begin
            cb1_del  <= cb1;
            cb1_rise <= (~cb1_del) & cb1;
            cb1_fall <= cb1_del & (~cb1);
            if (cb1_edge == 1'b1)
                irqb1 <= 1'b1;
            else if (portb_read == 1'b1)
                irqb1 <= 1'b0;
        end
    end

    assign cb1_edge = portb_ctrl[1] ? cb1_rise : cb1_fall;

    //---------------------------------
    // CB2 Edge detect
    //---------------------------------
    always @(negedge clk or posedge rst)
    begin: cb2_input
        if (rst == 1'b1)
        begin
            cb2_del  <= 1'b0;
            cb2_rise <= 1'b0;
            cb2_fall <= 1'b0;
            irqb2    <= 1'b0;
        end
        else
        begin
            cb2_del  <= cb2_i;
            cb2_rise <= (~cb2_del) & cb2_i;
            cb2_fall <= cb2_del & (~cb2_i);
            if (portb_ctrl[5] == 1'b0 && cb2_edge == 1'b1)
                irqb2 <= 1'b1;
            else if (portb_read == 1'b1)
                irqb2 <= 1'b0;
        end
    end

    assign cb2_edge = portb_ctrl[4] ? cb2_rise : cb2_fall;

    //---------------------------------
    // CB2 output control
    //---------------------------------
    always @(negedge clk or posedge rst)
    begin: cb2_output
        if (rst == 1'b1)
            cb2_out <= 1'b0;
        else
            case (portb_ctrl[5:3])
                3'b100 :		// write PB clears, CB1 edge sets
                    if (portb_write == 1'b1)
                        cb2_out <= 1'b0;
                    else if (cb1_edge == 1'b1)
                        cb2_out <= 1'b1;
                3'b101 :		// write PB clears, E sets
                    cb2_out <= ~portb_write;
                3'b110 :		// set low
                    cb2_out <= 1'b0;
                3'b111 :		// set high
                    cb2_out <= 1'b1;
                default :		// no change
                    ;
            endcase
    end

    //---------------------------------
    // CB2 direction control
    //---------------------------------
    assign cb2_o  = portb_ctrl[5] ? cb2_out : 1'b0;
    assign cb2_oe = portb_ctrl[5];

    //---------------------------------
    // IRQ control
    //---------------------------------
    assign irqa = (irqa1 & porta_ctrl[0]) | (irqa2 & porta_ctrl[3]);
    assign irqb = (irqb1 & portb_ctrl[0]) | (irqb2 & portb_ctrl[3]);

endmodule
