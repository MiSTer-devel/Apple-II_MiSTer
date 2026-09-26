//
// Mockingboard clone for the Apple II
// Model A: two AY-3-8913 chips for six audio channels
//
// Top file by W. Soltys <wsoltys@gmail.com>
// 
// loosely based on:
// http://www.downloads.reactivemicro.com/Public/Apple%20II%20Items/Hardware/Mockingboard_v1/Mockingboard-v1a-Docs.pdf
// http://www.applelogic.org/CarteBlancheIIProj6.html
//

//  use ieee.std_logic_unsigned.all;

module MOCKINGBOARD(
    CLK_14M,
    PHASE_ZERO,
    PHASE_ZERO_R,
    PHASE_ZERO_F,
    I_ADDR,
    I_DATA,
    O_DATA,
    OE,
    I_RW_L,
    O_IRQ_L,
    O_NMI_L,
    I_IOSEL_L,
    I_RESET_L,
    I_ENA_H,
    O_AUDIO_L,
    O_AUDIO_R
);
    input        CLK_14M;
    input        PHASE_ZERO;
    input        PHASE_ZERO_R;
    input        PHASE_ZERO_F;
    input [7:0]  I_ADDR;
    input [7:0]  I_DATA;
    output [7:0] O_DATA;
    output       OE;
    
    input        I_RW_L;
    output       O_IRQ_L;
    output       O_NMI_L;
    input        I_IOSEL_L;
    input        I_RESET_L;
    input        I_ENA_H;
    
    output [9:0] O_AUDIO_L;
    output [9:0] O_AUDIO_R;
    
    
    wire [7:0]   o_pb_l;
    wire [7:0]   o_pb_r;
    
    wire [7:0]   i_psg_r;
    wire [7:0]   o_psg_r;
    wire [7:0]   i_psg_l;
    wire [7:0]   o_psg_l;
    
    wire [7:0]   o_psg_al;
    wire [7:0]   o_psg_bl;
    wire [7:0]   o_psg_cl;
    wire [9:0]   o_psg_ol;
    
    wire [7:0]   o_psg_ar;
    wire [7:0]   o_psg_br;
    wire [7:0]   o_psg_cr;
    wire [9:0]   o_psg_or;
    
    wire [7:0]   o_data_l;
    wire [7:0]   o_data_r;
    
    wire         lirq;
    wire         rirq;
    
    wire         PSG_EN;
    wire         VIA_CE_F;
    
    // Bus Direction (0 - read , 1 - write)
    // Bus control
    
    assign O_DATA = (I_ADDR[7] == 1'b0) ? o_data_l : o_data_r;
    assign O_IRQ_L = (~lirq) | (~I_ENA_H);
    assign O_NMI_L = (~rirq) | (~I_ENA_H);
    assign OE = ~I_IOSEL_L;
    
    assign PSG_EN = PHASE_ZERO_F;
    assign VIA_CE_F = PHASE_ZERO_R;
    
    // Left Channel Combo
    
    via6522 m6522_left(
        .clk(CLK_14M),
        .ce(VIA_CE_F),
        //.falling(VIA_CE_F),
        .reset(~I_RESET_L),
        
        .addr(I_ADDR[3:0]),
        .strobe((~I_IOSEL_L) & I_ENA_H & (~I_ADDR[7])),
        .we((~I_RW_L) & (~I_ADDR[7]) & (~I_IOSEL_L) & I_ENA_H),
        //.ren(I_RW_L & (~I_ADDR[7]) & (~I_IOSEL_L) & I_ENA_H),
        .data_in(I_DATA),
        .data_out(o_data_l),
        
        //.phi2_ref(),
        
        .porta_out(i_psg_l),
        //.port_a_t(),
        .porta_in(o_psg_l),
        
        .portb_out(o_pb_l),
        //.portb_t(),
        .portb_in(8'hFF),
        
        .ca1_in(1'b1),
        .ca2_out(),
        .ca2_in(1'b1),
        .cb1_out(),
        .cb1_in(1'b1),
        //.cb1_t(),
        .cb2_out(),
        .cb2_in(1'b1),
        //.cb2_t(),
        .irq(lirq)
    );
    
    
    YM2149 psg_left(
        .CLK(CLK_14M),
        .CE(PSG_EN & I_ENA_H),
        .RESET(~o_pb_l[2]),
        .BDIR(o_pb_l[1]),
        .BC(o_pb_l[0]),
        .DI(i_psg_l),
        .DO(o_psg_l),
        .CHANNEL_A(o_psg_al),
        .CHANNEL_B(o_psg_bl),
        .CHANNEL_C(o_psg_cl),
        
        .SEL(1'b0),
        .MODE(1'b0),
        
        .ACTIVE(),
        
        .IOA_in(8'h00),
        .IOA_out(),
        
        .IOB_in(8'h00),
        .IOB_out()
    );
    
    assign O_AUDIO_L = (({2'b00, o_psg_al}) + ({2'b00, o_psg_bl}) + ({2'b00, o_psg_cl}));
    
    // Right Channel Combo
    
    via6522 m6522_right(
        .clk(CLK_14M),
        .ce(VIA_CE_F),
        //.falling(VIA_CE_F),
        .reset(~I_RESET_L),
        
        .addr(I_ADDR[3:0]),
        .strobe((~I_IOSEL_L) & I_ENA_H & I_ADDR[7]),
        .we((~I_RW_L) & I_ADDR[7] & (~I_IOSEL_L) & I_ENA_H),
        //.ren(I_RW_L & I_ADDR[7] & (~I_IOSEL_L) & I_ENA_H),
        .data_in(I_DATA),
        .data_out(o_data_r),
        
        //.phi2_ref(),
        
        .porta_out(i_psg_r),
        //.port_a_t(),
        .porta_in(o_psg_r),
        
        .portb_out(o_pb_r),
        //.port_b_t(),
        .portb_in(8'hFF),
        
        .ca1_in(1'b1),
        .ca2_out(),
        .ca2_in(1'b1),
        .cb1_out(),
        .cb1_in(1'b1),
        .cb2_out(),
        .cb2_in(1'b1),
        .irq(rirq)
    );
    
    
    YM2149 psg_right(
        .CLK(CLK_14M),
        .CE(PSG_EN & I_ENA_H),
        .RESET(~o_pb_r[2]),
        .BDIR(o_pb_r[1]),
        .BC(o_pb_r[0]),
        .DI(i_psg_r),
        .DO(o_psg_r),
        .CHANNEL_A(o_psg_ar),
        .CHANNEL_B(o_psg_br),
        .CHANNEL_C(o_psg_cr),
        
        .SEL(1'b0),
        .MODE(1'b0),
        
        .ACTIVE(),
        
        .IOA_in(8'h00),
        .IOA_out(),
        
        .IOB_in(8'h00),
        .IOB_out()
    );
    
    assign O_AUDIO_R = (({2'b00, o_psg_ar}) + ({2'b00, o_psg_br}) + ({2'b00, o_psg_cr}));
    
endmodule
