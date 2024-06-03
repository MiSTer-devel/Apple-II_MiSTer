///////////////////////////////////////////////////////
//
// Apple IIe floppy sound emulation
//  by Jesus Arias (2023) 
//  https://www.ele.uva.es/~jesus/
//  https://www.ele.uva.es/~jesus/a2.pdf
//
///////////////////////////////////////////////////////


module floppy_sound (
	input clk,
	input [3:0]phs,		// motor_phase
	input motor,		// D1_ACTIVE, D2_ACTIVE
	input speaker,		
	output reg pwm
);

// PWM
reg [7:0]counter=0;
wire tc= counter[7:1]==(7'b1111111);
always @(posedge clk) counter<= tc ? 0 : counter+1;

wire [7:0]mix = inte[7:1]+inte[7:2]+{pulse,4'b0000}+{mnoise,2'b00}+22;
reg [7:0]level; // buffered level
always @(posedge clk) if (tc) level<=mix;

//reg pwm;
always @(posedge clk) pwm<=(counter==level)? 0 : (tc ? 1: pwm);

// speaker (simple comb filter)
reg [7:0]inte;
always @(posedge clk) inte<= tc ? speaker : inte + speaker;

// motor noise (PRBS)
reg [2:0]decim=0;
wire dtc = (decim[2]&decim[0]);
always @(posedge clk) if (tc) decim <= dtc ? 0 : decim+1;

reg [12:0]lfsr=13'h1fff;
always @(posedge clk) if ((~dtc)&tc) lfsr<={lfsr[11:0],lfsr[12]^lfsr[11]^lfsr[10]^lfsr[7]};
wire mnoise=motor&lfsr[0];

// track noise (2ms pulses)
reg [3:0]oph;
always @(posedge clk) oph<=phs;
wire [3:0]rising = phs&(~oph);
wire clic=(rising!=0);

reg [3:0]cpulse=0;
wire pulse=(cpulse!=0);
always @(posedge clk) cpulse<= clic ? 4'hf : ((pulse&tc&dtc)? cpulse-1 : cpulse);

endmodule

