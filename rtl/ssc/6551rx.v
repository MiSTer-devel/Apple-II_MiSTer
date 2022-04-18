////////////////////////////////////////////////////////////////////////////////
// Project Name:	CoCo3FPGA Version 1.0
// File Name:		6551rx.v
//
// CoCo3 in an FPGA
// Based on the Spartan 3 Starter board by Digilent Inc.
// with the 1000K gate upgrade
//
// Revision: 1.0 08/31/08
////////////////////////////////////////////////////////////////////////////////
//
// CPU section copyrighted by John Kent
//
////////////////////////////////////////////////////////////////////////////////
//
// Color Computer 3 compatible system on a chip
//
// Version : 1.0
//
// Copyright (c) 2008 Gary Becker (gary_l_becker@yahoo.com)
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Please report bugs to the author, but before you do so, please
// make sure that this is not a derivative work and that
// you have the latest version of this file.
//
// The latest version of this file can be found at:
//      http://groups.yahoo.com/group/CoCo3FPGA
//
// File history :
//
//  1.0		Full release
//
////////////////////////////////////////////////////////////////////////////////
// Gary Becker
// gary_L_becker@yahoo.com
////////////////////////////////////////////////////////////////////////////////

module uart51_rx(
RESET_N,
BAUD_CLK,
RX_DATA,
RX_BUFFER,
RX_WORD,
RX_PAR_DIS,
RX_PARITY,
PARITY_ERR,
FRAME,
READY
);
input					RESET_N;
input					BAUD_CLK;
input					RX_DATA;
output	[7:0]		RX_BUFFER;
reg		[7:0]		RX_BUFFER;
input		[1:0]		RX_WORD;
input					RX_PAR_DIS;
input		[1:0]		RX_PARITY;
output				PARITY_ERR;
reg					PARITY_ERR;
output				FRAME;
reg					FRAME;
output				READY;
reg					READY;
reg		[5:0]		STATE;
reg		[2:0]		BIT;

always @ (posedge BAUD_CLK or negedge RESET_N)
begin
	if(!RESET_N)
	begin
		RX_BUFFER <= 8'h00;
		STATE <= 6'b000000;
		FRAME <= 1'b0;
		BIT <= 3'b000;
		READY <= 1'b0;
	end
	else
	begin
		case (STATE)
		6'b000000:										// States 0-15 will be start bit
		begin
			BIT <= 3'b000;
			if(~RX_DATA)
				STATE <= 6'b000001;
		end
		6'b001111:										// End of the Start bit, clear buffer
		begin
				STATE <= 6'b010000;
				RX_BUFFER <= 8'h00;
				READY <= 1'b0;
		end
		6'b010111:										// Each data bit is states 16-31, the middle is 23
		begin
			RX_BUFFER[BIT] <= RX_DATA;
			STATE <= 6'b011000;
		end
		6'b011111:										// End of the data bits
		begin
			if(BIT == 3'b111)							// We cannot get more than 8 bits
			begin
				STATE <= 6'b100000;
			end
			else
			begin
				if((RX_WORD == 2'b01) && (BIT == 3'b110))		// 7 data bits
				begin
					STATE <= 6'b100000;
				end
				else
				begin
					if((RX_WORD == 2'b10) && (BIT == 3'b101)) 	// 6 data bits
					begin
						STATE <= 6'b100000;
					end
					else
					begin
						if((RX_WORD == 2'b11) && (BIT == 3'b100))	// 5 data bits
						begin
							STATE <= 6'b100000;
						end
						else
						begin
							BIT <= BIT + 1;
							STATE <= 6'b010000;
						end
					end
				end
			end
		end
		6'b100000:										// First tick of Stop or Parity, Parity is 32 - 47
		begin
			if(RX_PAR_DIS)
				STATE <= 6'b110001;		// get stop
			else
				STATE <= 6'b100001;		// get parity
		end
		6'b100111:										// Middle of Parity is 39
		begin
			PARITY_ERR <= ~RX_PARITY[1] &											// Get but do not check Parity if 1 is set
							 (((RX_BUFFER[0] ^ RX_BUFFER[1])
							 ^ (RX_BUFFER[2] ^ RX_BUFFER[3]))

							 ^((RX_BUFFER[4] ^ RX_BUFFER[5])
							 ^ (RX_BUFFER[6] ^ RX_BUFFER[7]))	// clear bit #8 if only 7 bits

							 ^ (~RX_PARITY[0] ^ RX_DATA));
			STATE <= 6'b101000;
		end
		6'b110111:										// first stop bit should start at 48 and ends at 63
		begin
			FRAME <= !RX_DATA;			// if data != 1 then not stop bit
			STATE <= 6'b111000;
			READY <= 1'b1;
		end

// at step 55, we have all the data needed for this transfer
// at 56 we flag we have data and the latch read data state
// machine has at least until the end of the next start bit
// to latch the data, then it will be gone. After that, the
// CPU has until 55 to read the data.

// In case of a framing error, wait until data is 1 then start over
		6'b111000:
		begin
			if(RX_DATA)
				STATE <= 6'b000000;
		end
		default: STATE <= STATE + 1;
		endcase
	end
end
endmodule
