


module superserial(

    input         IO_SELECT_N,
    input  [15:0] ADDRESS,
    input         RW_N,
    // input SYNC -- only slot 7
    input         IO_STROBE_N,
    //output        RDY,
    //input       DMA,
    output        IRQ_N,
    //output        NMI_N,
    input         RESET,
    //input         INH_N,
	 input         CLK_50M,
    input         CLK_14M,
  //  input         CLK_7M,
    input         CLK_2M,
    input         PH_2,
    input         DEVICE_SELECT_N,
    input  [7:0]  DATA_IN,
    output [7:0]  DATA_OUT,
    output   ROM_EN,

    // serial pass through to the framework
    input         UART_RXD,
    output        UART_TXD,
    input         UART_CTS,
    output        UART_RTS,
    output        UART_DTR,
    input         UART_DSR

);


//  The Super Serial Card has 
//  a 2k rom.
//  The 256byte section actually starts at address 0x700
//  The full 2k rom is mapped in when the card is selected (into a shared
//  address space)
//
//  All cards unamp their 2k rom when they see CFFF1
//  

//
// Super Serial Rom
//
wire [7:0] DOA_C8S;
wire [7:0] DATA_SERIAL_OUT;
wire [7:0] SSC;

// NOT SURE WHAT THIS IS DOING - are there dips on the card? Check manual. Maybe move this to the framework.

// DATA_SERIAL_OUT can contain Data, Status, command or control - because ADDRESS[1:0] is passed to the serial chip - and it has a mux in the chip.
// we need to HANDLE C081 - DIPSW1 and  C082 - DIPSW2 

assign SSC =                                    
//      Bits 7=SW1-1 6=SW1-2 5=SW1-3 4=SW1-4 3=X     2=X     1=SW1-5 0=SW1-6
//        OFF     OFF     OFF     ON      1       1       ON      ON
//      | 9600 BAUD                     |               | SSC Firmware Mode
     (ADDRESS[3:0]  == 4'h1)        ?        8'b11101100:
//      Bits 7=SW2-1 6=X     5=SW2-2 4=X     3=SW2-3 2=SW2=4 1=SW2-5 0=CTS
//        ON      1       ON      1       ON      ON      ON
//      |1 STOP |       |8 BITS |       | No Parity     |Add LF | CTS
     (ADDRESS[3:0]  == 4'h2)        ?       {7'b0101000, UART_CTS}:
     (ADDRESS[3]    == 1'b1)        ?        DATA_SERIAL_OUT: 8'b11111111;
/*
  Map and Unmap the ROM - setup ROM_EN and ENA_C8S
*/
reg				SLOTCXROM;
wire				ENA_C8S;
reg				C8S2;
wire APPLE_C0;


assign APPLE_C0	= (ADDRESS[15:8]	== 8'b11000000) ? 1'b1: 1'b0;

always @(posedge CLK_14M)
begin
	if(RESET)
	begin
		SLOTCXROM <= 1'b0;
	end
	else
	begin
			if(~RW_N)
			begin
				case({APPLE_C0, ADDRESS[7:0]})
				9'h106:		SLOTCXROM <= 1'b0;
				9'h107:		SLOTCXROM <= 1'b1;
				endcase
			end
	end
end


always @ (posedge CLK_14M)
begin
	if(RESET)
	begin
		C8S2 <= 1'b0;
	end
	else
	begin
		case (ADDRESS[15:8])
		8'hC2:
		begin
			if(!SLOTCXROM)								// SSC ROM
				C8S2 <= 1'b1;
		end
		8'hCF:
		begin
			if(!SLOTCXROM)
			begin
				if(ADDRESS[7:0] == 8'hFF)
				  C8S2 <= 1'b0;
			end
		end
		endcase
	end
end

assign ENA_C8S = ({(C8S2 & !SLOTCXROM),ADDRESS[15:11]} == 6'b111001) ? 1'b1: 1'b0;
assign ROM_EN = ENA_C8S;
//assign DATA_OUT2 = ENA_C8S ? DOA_C8S : SSC;
																									
																									/* END TESTING */

/*
always @(posedge CLK_14M)
begin
         //if ((ADDRESS[3:0]  == 4'hC))
         if ((ADDRESS[15:0]  == 16'hC205))
		$display("IO_SELECT_N %x ROM_EN %x IO_STROBE_N %x DEVICE_SELECT_N %x ADDR %x ROM_ADDR %x RW_N %x DOA_C8S %x DATA_OUT %x",IO_SELECT_N,ROM_EN,IO_STROBE_N,DEVICE_SELECT_N,ADDRESS,ROM_ADDR,RW_N,DOA_C8S,DATA_OUT);
end
*/

wire [10:0] ROM_ADDR = ROM_EN ? ADDRESS[10:0] : { 3'b111 ,ADDRESS[7:0]} ;
assign DATA_OUT = ~IO_SELECT_N ? DOA_C8S : (ROM_EN & ~IO_STROBE_N) ? DOA_C8S : SSC;

ssc_rom rom (.clk(CLK_14M),.addr(ROM_ADDR),.data(DOA_C8S));
//
//  Serial Port
//

reg     [4:0]           CLK_6551;
// 14.31818
// 50 MHz / 27 = 1.852 MHz
always @(posedge CLK_50M)
begin
        if(RESET)
                CLK_6551 <= 5'd0;
        else
                case(CLK_6551)
                5'd26:
                        CLK_6551 <= 5'd0;
                default:
                        CLK_6551 <= CLK_6551 + 1'b1;
                endcase
end

assign IRQ_N = SER_IRQ;
wire SER_IRQ;



glb6551 COM2(
.RESET_N(~RESET),
.RX_CLK(),
.RX_CLK_IN(CLK_6551[4]),
.XTAL_CLK_IN(CLK_6551[4]),
//.PH_2(PH_2),
.PH_2(CLK_14M),
.DI(DATA_IN),
.DO(DATA_SERIAL_OUT),
.IRQ(SER_IRQ),
// IS THIS DEVICE SELECT OR IO_SELECT?
.CS({!ADDRESS[3], ~DEVICE_SELECT_N}),           // C0A8-C0AF // we should be able to use IO_SELECT_N and it should reference our slot - and make it movable i think
.RW_N(RW_N),
.RS(ADDRESS[1:0]),
.TXDATA_OUT(UART_TXD),
.RXDATA_IN(UART_RXD),
.RTS(UART_RTS),
.CTS(UART_CTS),
.DCD(1'b1),
.DTR(UART_DTR),
.DSR(UART_DSR)
);


endmodule

