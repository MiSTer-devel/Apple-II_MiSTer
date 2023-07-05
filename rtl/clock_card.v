`timescale 1ns / 1ps

module clock_card(

    input         IO_SELECT_N,
    input  [15:0] ADDRESS,
    input         RW_N,
    // input SYNC -- only slot 7
    input         IO_STROBE_N,
    //output        RDY,
    //input       DMA,
    //output        IRQ_N,
    //output        NMI_N,
    input         RESET,
    //input         INH_N,
    input         CLK_14M,
  //  input         CLK_7M,
    input         CLK_2M,
    input         PH_2,
    input         DEVICE_SELECT_N,
    input  [7:0]  DATA_IN,
    output [7:0]  DATA_OUT,
    //output   ROM_EN,

    input [64:0]  RTC


);


reg [20:0] second_div;
reg TICK;
reg V_SYNC;

always @(posedge CLK_2M)
begin
	second_div<=second_div+1'b1;
	V_SYNC<=1'b0;
	//$display("second_div %d",second_div);
	if (second_div==('d1000000/'d60))
	begin
		second_div<=1'b0;
		V_SYNC<=1'b1;
		$display("V_SYNC is now 1");
	end
end

reg     [3:0]           YEARS_TENS;
reg     [3:0]           YEARS_ONES;
reg                     MONTHS_TENS;
reg     [3:0]           MONTHS_ONES;
reg     [2:0]           DAY_WEEK;
reg     [1:0]           DAYS_TENS;
reg     [3:0]           DAYS_ONES;
reg     [1:0]           HOURS_TENS;
reg     [3:0]           HOURS_ONES;
reg     [2:0]           MINUTES_TENS;
reg     [3:0]           MINUTES_ONES;
reg     [2:0]           SECONDS_TENS;
reg     [3:0]           SECONDS_ONES;
reg     [5:0]           DEB_COUNTER;


//wire SLOT_IO = (ADDRESS[15:4]        == 12'hC0C)   ?  1'b1: 1'b0;
wire SLOT_IO = ~DEVICE_SELECT_N;

/*****************************************************************************
* Hardware Clock
******************************************************************************/
wire [7:0] CLK_IN =
		({SLOT_IO, ADDRESS[3:0]}== 5'b10000)?  8'h32:							// Year thousand
		({SLOT_IO, ADDRESS[3:0]}== 5'b10001)?  8'h30:							// Year hundreds
		({SLOT_IO, ADDRESS[3:0]}== 5'b10010)? {4'h3,  YEARS_TENS}:			// Year tens
		({SLOT_IO, ADDRESS[3:0]}== 5'b10011)? {4'h3,  YEARS_ONES}:			// Year ones
		({SLOT_IO, ADDRESS[3:0]}== 5'b10100)? {7'h18, MONTHS_TENS}:		// Month tens
		({SLOT_IO, ADDRESS[3:0]}== 5'b10101)? {4'h3,  MONTHS_ONES}:		// Month ones
		({SLOT_IO, ADDRESS[3:0]}== 5'b10110)? {5'h06, DAY_WEEK}:			// Day of week
		({SLOT_IO, ADDRESS[3:0]}== 5'b10111)? {6'h0C, DAYS_TENS}:
		({SLOT_IO, ADDRESS[3:0]}== 5'b11000)? {4'h3,  DAYS_ONES}:
		({SLOT_IO, ADDRESS[3:0]}== 5'b11001)? {6'h0C, HOURS_TENS}:
		({SLOT_IO, ADDRESS[3:0]}== 5'b11010)? {4'h3,  HOURS_ONES}:
		({SLOT_IO, ADDRESS[3:0]}== 5'b11011)? {5'h06, MINUTES_TENS}:
		({SLOT_IO, ADDRESS[3:0]}== 5'b11100)? {4'h3,  MINUTES_ONES}:
		({SLOT_IO, ADDRESS[3:0]}== 5'b11101)? {5'h06, SECONDS_TENS}:
		({SLOT_IO, ADDRESS[3:0]}== 5'b11110)? {4'h3,  SECONDS_ONES}:
															{2'b00, DEB_COUNTER};		/*Not needed for Apple*/


reg flg;

always @(negedge PH_2)
begin
	flg <= RTC[64];
	if (flg!=RTC[64])
	begin
		$display("setting time");
		SECONDS_TENS<= RTC[6:4];
		SECONDS_ONES<= RTC[3:0];

		MINUTES_TENS<= RTC[14:12];
		MINUTES_ONES<= RTC[11:8];

		HOURS_TENS<= RTC[21:20];
		HOURS_ONES<= RTC[19:16];

		DAY_WEEK<= RTC[50:48];
		DAYS_TENS<= RTC[29:28];
		DAYS_ONES<= RTC[27:24];

		MONTHS_TENS<= RTC[36];
		MONTHS_ONES<= RTC[35:32];

		YEARS_TENS <= RTC[47:44];
		YEARS_ONES<= RTC[43:40];
	end
	else
	case({RW_N, SLOT_IO, ADDRESS[3:0]})
		6'b010010:									// Write C0C2
		begin
			YEARS_TENS <= DATA_IN[3:0];		// 0-9
		end
		6'b010011:									// Write C0C3
		begin
			YEARS_ONES <= DATA_IN[3:0];		// 0-9
		end
		6'b010100:									// Write C0C4
		begin
			MONTHS_TENS <= DATA_IN[0];		// 0-1
		end
		6'b010101:									// Write C0C5
		begin
			MONTHS_ONES <= DATA_IN[3:0];		// 0-9
		end
		6'b010110:									// Write C0C6
		begin
			DAY_WEEK <= DATA_IN[2:0];			// 0-6
		end
		6'b010111:									// Write C0C7
		begin
			DAYS_TENS <= DATA_IN[1:0];		// 0-3
		end
		6'b011000:									// Write C0C8
		begin
			DAYS_ONES <= DATA_IN[3:0];		// 0-9
		end
		6'b011001:									// Write C0C9
		begin
			HOURS_TENS <= DATA_IN[1:0];		// 0-2
		end
		6'b011010:									// Write C0CA
		begin
			HOURS_ONES <= DATA_IN[3:0];		// 0-9
		end
		6'b011011:									// Write C0CB
		begin
			MINUTES_TENS <= DATA_IN[2:0];	// 0-5
		end
		6'b011100:									// Write C0CC
		begin
			MINUTES_ONES <= DATA_IN[3:0];	// 0-9
		end
		6'b011101:									// Write C0CD
		begin
			SECONDS_TENS <= DATA_IN[2:0];	// 0-5
		end
		6'b011110:									// Write C0CE
		begin
			SECONDS_ONES <= DATA_IN[3:0];		// 0-9
		end
		default:
		begin
			TICK <= V_SYNC;
			if(TICK & ~V_SYNC)					// EDGE DETECT
			begin
// 1/60 timer
				if(DEB_COUNTER == 6'd59)
				begin
					DEB_COUNTER <= 6'd0;
					if(SECONDS_ONES == 4'd9)
					begin
						SECONDS_ONES <= 4'd0;
						if(SECONDS_TENS == 3'd5)
						begin
							SECONDS_TENS <= 3'd0;
							if(MINUTES_ONES == 4'd9)
							begin
								MINUTES_ONES <= 4'd0;
								if(MINUTES_TENS == 3'd5)
								begin
									MINUTES_TENS <= 3'd0;
									if((HOURS_ONES == 4'd9) || ((HOURS_ONES == 4'd3)&&(HOURS_TENS == 3'd2)))
									begin
										HOURS_ONES <= 3'd0;
										if(HOURS_TENS == 3'd2)
										begin
											HOURS_TENS <= 2'd0;
											if(DAYS_ONES == 4'd9)
											begin
												DAYS_ONES <= 4'd0;
												DAYS_TENS <= DAYS_TENS + 1'b1;
											end
											else
											begin
												DAYS_ONES <= DAYS_ONES + 1'b1;
											end
											if(DAY_WEEK == 3'd6)
											begin
												DAY_WEEK <= 3'd0;
											end
											else
											begin
												DAY_WEEK <= DAY_WEEK + 1'b1;
											end
										end
										else
										begin
											HOURS_TENS <= HOURS_TENS + 1'b1;
										end
									end
									else
									begin
										HOURS_ONES <= HOURS_ONES + 1'b1;
									end
								end
								else
								begin
									MINUTES_TENS <= MINUTES_TENS + 1'b1;
								end
							end
							else
							begin
								MINUTES_ONES <= MINUTES_ONES + 1'b1;
							end
						end
						else
						begin
							SECONDS_TENS <= SECONDS_TENS + 1'b1;
						end
					end
					else
					begin
						SECONDS_ONES <= SECONDS_ONES + 1'b1;
					end
				end
				else
				begin
					$display("increment deb_counter seconds %d SECONDS_ONES %d",DEB_COUNTER,SECONDS_ONES);
					DEB_COUNTER <= DEB_COUNTER + 1'b1;
				end
			end
		end
	endcase
end

wire [7:0] DOA_CS;
wire [7:0] ROM_ADDR = ADDRESS[7:0];
assign DATA_OUT = ~IO_SELECT_N ? DOA_CS :  CLK_IN;

   rom #(8,8,"rtl/roms/clock.hex") roms (
           .clock(CLK_14M),
           .ce(1'b1),
           .a(ROM_ADDR),
           .data_out(DOA_CS)
   );
   endmodule
