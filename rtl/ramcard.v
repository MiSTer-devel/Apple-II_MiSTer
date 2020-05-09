// taken from the Apple II project by Alex Freed
// and modified for own use

module ramcard
(
	input         clk,
	input         reset_in,
	input  [15:0] addr,
	output [17:0] ram_addr,
	output        card_ram_we,
	output        card_ram_rd
);

reg        bankB, sat_read_en, sat_write_en, sat_pre_wr_en, sat_en;
reg  [2:0] bank16k = 0;
reg [15:0] addr2;
wire       Dxxx,DEF;

always @(posedge clk) begin
 addr2 <= addr;
 if(reset_in) begin
	bankB <= 0;
	sat_read_en <= 0;
	sat_write_en <= 0;
	sat_pre_wr_en <= 0;
 end 
 else begin
	if((addr[15:4] == 'hC0D) & (addr2 != addr)) begin
	  // Looks like Saturn128 Card in slot 5
	  if(addr[2] == 0) begin
		 // State selection
		 bankB <= addr[3];
		 sat_pre_wr_en <= addr[0];
		 sat_write_en <= addr[0] & sat_pre_wr_en;
		 sat_read_en <= ~(addr[0] ^ addr[1]);
	  end
	  else
	  begin
		 // 16K bank selection
		 bank16k <= {addr[3], addr[1], addr[0]};
	  end
	end
 end
end

assign Dxxx = (addr[15:12] == 4'b1101);
assign DEF  = ((addr[15:14] == 2'b11) & (addr[13:12] != 2'b00));
assign ram_addr = {bank16k[2], ~bank16k[2], bank16k[1:0], addr[13], addr[12] & ~(bankB & Dxxx), addr[11:0]};
assign card_ram_we = sat_write_en & DEF;
assign card_ram_rd = sat_read_en  & DEF;

endmodule
