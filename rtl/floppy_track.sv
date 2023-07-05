// 
// Apple ][ track read/write interface to MiST
//
// Based on the work of
// Copyright (c) 2016 Sorgelig
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the Lesser GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//
/////////////////////////////////////////////////////////////////////////

module floppy_track
(
	input         clk,
	input         reset,

	output [31:0] sd_lba,
	output reg    sd_rd,
	output reg    sd_wr,
	input         sd_ack,

	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	input         change,
	input         mount,
	input   [5:0] track,
	output reg    ready = 0,
	input         active,

	input  [12:0] ram_addr,
	output  [7:0] ram_do,
	input   [7:0] ram_di,
	input         ram_we,
	output reg    busy
);

assign sd_lba = lba;

reg  [31:0] lba;
reg   [3:0] rel_lba;

always @(posedge clk) begin
	reg old_ack;
	reg [5:0] cur_track = 0;
	reg old_change;
	reg saving = 0;
	reg dirty = 0;

	old_change <= change;
	old_ack <= sd_ack;

	if(sd_ack) {sd_rd,sd_wr} <= 0;

	if(ready && ram_we) dirty <= 1;

	if(~old_change & change) begin
		ready <= mount;
		cur_track <= 'b111111;
		busy  <= 0;
		sd_rd <= 0;
		sd_wr <= 0;
		saving<= 0;
		dirty <= 0;
	end
	else
	if(reset) begin
		cur_track <= 'b111111;
		busy  <= 0;
		sd_rd <= 0;
		sd_wr <= 0;
		saving<= 0;
		dirty <= 0;
	end
	else

	if(busy) begin
		if(old_ack && ~sd_ack) begin
			if(rel_lba != 4'd12) begin
				lba <= lba + 1'd1;
				rel_lba <= rel_lba + 1'd1;
				if(saving) sd_wr <= 1;
					else sd_rd <= 1;
			end
			else
			if(saving && (cur_track != track)) begin
				saving <= 0;
				cur_track <= track;
				rel_lba <= 0;
                lba <= track * 8'd13; //track size = 1a00h = 13*512
				sd_rd <= 1;
			end
			else
			begin
				busy <= 0;
				dirty <= 0;
			end
		end
	end
	else
	if(ready && ((cur_track != track) || (old_change && ~change) || (dirty && ~active)))
		if (dirty && cur_track != 'b111111) begin
			saving <= 1;
			lba <= cur_track * 8'd13;
			rel_lba <= 0;
			sd_wr <= 1;
			busy <= 1;
		end
		else
		begin
			saving <= 0;
			cur_track <= track;
			rel_lba <= 0;
			lba <= track * 8'd13; //track size = 1a00h
			sd_rd <= 1;
			busy <= 1;
			dirty <= 0;
		end
end


dpram #(13,8) floppy_dpram
(
        .clock_a(clk),
        .address_a({rel_lba, sd_buff_addr}),
        .wren_a(sd_buff_wr & sd_ack),
        .data_a(sd_buff_dout),
        .q_a(sd_buff_din),

        .clock_b(clk),
        .address_b(ram_addr),
        .wren_b(ram_we),
        .data_b(ram_di),
        .q_b(ram_do)

);

/*
// Dual port track buffer
reg   [7:0] track_ram[13*512];

// IO controller side
always @(posedge clk) begin
	sd_buff_din <= track_ram[{rel_lba, sd_buff_addr}];
	if (sd_buff_wr & sd_ack) track_ram[{rel_lba, sd_buff_addr}] <= sd_buff_dout;
end

// Disk controller side
always @(posedge clk) begin
	ram_do <= track_ram[ram_addr];
	if (ram_we) track_ram[ram_addr] <= ram_di;
end
*/
endmodule
