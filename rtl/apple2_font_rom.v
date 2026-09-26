module apple2_font_rom (
	input  wire        CLK_14M,
	input  wire        ROMSWITCH,
	input  wire        alternate_character,
	input  wire        lowercase_character,
	input  wire [6:0]  character_code,
	input  wire [2:0]  glyph_row,
	input  wire [24:0] ioctl_addr,
	input  wire [7:0]  ioctl_data,
	input  wire        ioctl_wr,
	output reg  [7:0]  glyph_data
);

wire [12:0] rom_addr = ioctl_wr ? ioctl_addr[12:0] :
	{ROMSWITCH, 2'b00, alternate_character | lowercase_character,
	 character_code[5:0], glyph_row};
reg [7:0] font_rom [0:8191];

initial $readmemh("rtl/roms/video2.hex", font_rom);

always @(posedge CLK_14M) begin
	if(ioctl_wr) font_rom[rom_addr] <= ioctl_data;
	glyph_data <= ioctl_wr ? ioctl_data : font_rom[rom_addr];
end

endmodule