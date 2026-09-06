library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity apple2_font_rom is
  port (
    CLK_14M       : in std_logic;
    ROMSWITCH     : in std_logic;
    alternate_character: in std_logic;
    lowercase_character: in std_logic;
    character_code: in std_logic_vector(6 downto 0);
    glyph_row     : in std_logic_vector(2 downto 0);
    ioctl_addr    : in std_logic_vector(24 downto 0);
    ioctl_data    : in std_logic_vector(7 downto 0);
    ioctl_wr      : in std_logic;
    glyph_data    : out std_logic_vector(7 downto 0)
  );
end apple2_font_rom;

architecture rtl of apple2_font_rom is
  signal rom_addr : std_logic_vector(12 downto 0);
  signal rom_out  : unsigned(7 downto 0);
begin
  rom_addr <= ioctl_addr(12 downto 0) when ioctl_wr = '1' else
              ROMSWITCH & "00" & (alternate_character or lowercase_character) & character_code(5 downto 0) & glyph_row;

  font_rom : work.spram
  generic map (13, 8, "rtl/roms/video2.mif")
  port map (
    address => rom_addr,
    clock => CLK_14M,
    data => ioctl_data,
    wren => ioctl_wr,
    unsigned(q) => rom_out
  );

  glyph_data <= std_logic_vector(rom_out);
end rtl;