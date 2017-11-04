--
--
-- Apple II+ toplevel for the MiST board
-- https://github.com/wsoltys/mist_apple2
--
-- Copyright (c) 2014 W. Soltys <wsoltys@gmail.com>
--
-- This source file is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published
-- by the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This source file is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity apple2_top is port
(
	-- Clocks
	CLK_28M 			: in std_logic;
	CLK_14M 			: in std_logic;
	CPU_WAIT			: in std_logic;

	reset_in			: in std_logic;

	-- VGA output
	VGA_DE 			: out std_logic;
	VGA_CLK 			: out std_logic;
	VGA_HS 			: out std_logic;
	VGA_VS 			: out std_logic;
	VGA_R 			: out std_logic_vector(7 downto 0);
	VGA_G 			: out std_logic_vector(7 downto 0);
	VGA_B 			: out std_logic_vector(7 downto 0);
	SCREEN_MODE 	: in std_logic_vector(1 downto 0);  -- 00: Color, 01: B&W, 10:Green, 11: Amber

	-- Audio
	AUDIO_L 			: out std_logic_vector(7 downto 0);
	AUDIO_R 			: out std_logic_vector(7 downto 0);
	SPEAKER 			: out std_logic;

	ps2Clk     		: in std_logic;
	ps2Data    		: in std_logic;

	joy        		: in std_logic_vector(5 downto 0);
	joy_an     		: in std_logic_vector(15 downto 0);

	-- mocking board
	mb_enabled 		: in std_logic;

	-- disk control
	TRACK 			: out unsigned(5 downto 0);
	TRACK_RAM_ADDR : in unsigned(12 downto 0);
	TRACK_RAM_DI 	: in unsigned(7 downto 0);
	TRACK_RAM_WE 	: in std_logic;

	-- main RAM
	ram_addr 		: out std_logic_vector(17 downto 0);
	ram_dout 		: in std_logic_vector(7 downto 0);
	ram_din  		: out std_logic_vector(7 downto 0);
	ram_we 			: out std_logic;

	-- LEDG
	LED 				: out std_logic
);

end apple2_top;

architecture datapath of apple2_top is

  signal CLK_2M, PRE_PHASE_ZERO: std_logic;
  signal IO_SELECT, DEVICE_SELECT : std_logic_vector(7 downto 0);
  signal ADDR : unsigned(15 downto 0);
  signal D, PD: unsigned(7 downto 0);

  signal we_ram : std_logic;
  signal VIDEO, HBL, VBL, LD194 : std_logic;
  signal COLOR_LINE : std_logic;
  signal COLOR_LINE_CONTROL : std_logic;
  signal GAMEPORT : std_logic_vector(7 downto 0);
  signal cpu_pc : unsigned(15 downto 0);

  signal K : unsigned(7 downto 0);
  signal read_key : std_logic;

  signal flash_clk : unsigned(22 downto 0) := (others => '0');
  signal power_on_reset : std_logic := '1';
  signal reset : std_logic;

  signal a_ram: unsigned(17 downto 0);
  
  signal joyx       : std_logic;
  signal joyy       : std_logic;
  signal pdl_strobe : std_logic;

begin

  reset <= power_on_reset;

  power_on : process(CLK_14M, reset_in)
  begin
    if reset_in = '1' then
       power_on_reset <= '1';
    elsif rising_edge(CLK_14M) then
      if flash_clk(22) = '1' then
        power_on_reset <= '0';
      end if;
    end if;
  end process;
  
  -- In the Apple ][, this was a 555 timer
  flash_clkgen : process (CLK_14M, reset_in)
  begin
    if reset_in = '1' then
       flash_clk <= (others=>'0');
    elsif rising_edge(CLK_14M) then
		flash_clk <= flash_clk + 1;
    end if;     
  end process;

  -- Paddle buttons
  -- GAMEPORT input bits:
  --  7    6    5    4    3   2   1    0
  -- pdl3 pdl2 pdl1 pdl0 pb3 pb2 pb1 casette
  GAMEPORT <=  "00" & joyy & joyx & "0" & joy(5) & joy(4) & "0";
  
  process(CLK_2M, pdl_strobe)
    variable cx, cy : integer range -100 to 5800 := 0;
  begin
    if rising_edge(CLK_2M) then
      if cx > 0 then
        cx := cx -1;
        joyx <= '1';
      else
        joyx <= '0';
      end if;
      if cy > 0 then
        cy := cy -1;
        joyy <= '1';
      else
        joyy <= '0';
      end if;
      if pdl_strobe = '1' then
        cx := 2800+(22*to_integer(signed(joy_an(7 downto 0))));
        cy := 2800+(22*to_integer(signed(joy_an(15 downto 8)))); -- max 5650
        if cx < 0 then
          cx := 0;
        elsif cx >= 5590 then
          cx := 5650;
        end if;
        if cy < 0 then
          cy := 0;
        elsif cy >= 5590 then
          cy := 5650;
        end if;
      end if;
    end if;
  end process;

  COLOR_LINE_CONTROL <= COLOR_LINE and not (SCREEN_MODE(0) or SCREEN_MODE(1));  -- Color or B&W mode
  
  -- Simulate power up on cold reset to go to the disk boot routine
  ram_we   <= we_ram; -- when reset_in = '0' else '1';
  ram_addr <= std_logic_vector(a_ram); -- when reset_in = '0' else std_logic_vector(to_unsigned(1012,ram_addr'length)); -- $3F4
  ram_din  <= std_logic_vector(D); -- when reset_in = '0' else "00000000";

  core : entity work.apple2 port map (
    CLK_14M        => CLK_14M,
    CLK_2M         => CLK_2M,
	 CPU_WAIT       => CPU_WAIT,
    PRE_PHASE_ZERO => PRE_PHASE_ZERO,
    FLASH_CLK      => flash_clk(22),
    reset          => reset,
    ADDR           => ADDR,
    ram_addr       => a_ram,
    D              => D,
    ram_do         => unsigned(ram_dout),
    PD             => PD,
    ram_we         => we_ram,
    VIDEO          => VIDEO,
    COLOR_LINE     => COLOR_LINE,
    HBL            => HBL,
    VBL            => VBL,
    LD194          => LD194,
    K              => K,
    read_key       => read_key,
    AN             => open,
    GAMEPORT       => GAMEPORT,
    PDL_strobe     => pdl_strobe,
    IO_SELECT      => IO_SELECT,
    DEVICE_SELECT  => DEVICE_SELECT,
    pcDebugOut     => cpu_pc,
    speaker        => SPEAKER,
    laudio         => AUDIO_L,
    raudio         => AUDIO_R,
    mb_enabled     => mb_enabled
    );

  vga : entity work.vga_controller port map (
    CLK_28M    => CLK_28M,
    VIDEO      => VIDEO,
    COLOR_LINE => COLOR_LINE_CONTROL,
	 SCREEN_MODE => SCREEN_MODE,
    HBL        => HBL,
    VBL        => VBL,
    LD194      => LD194,
    VGA_CLK    => VGA_CLK,
    VGA_HS     => VGA_HS,
    VGA_VS     => VGA_VS,
    VGA_DE     => VGA_DE,
    std_logic_vector(VGA_R) => VGA_R,
    std_logic_vector(VGA_G) => VGA_G,
    std_logic_vector(VGA_B) => VGA_B
    );

  keyboard : entity work.keyboard port map (
    PS2_Clk  => ps2Clk,
    PS2_Data => ps2Data,
    CLK_14M  => CLK_14M,
    reset    => reset,
    reads     => read_key,
    K        => K
    );

  disk : entity work.disk_ii port map (
    CLK_14M        => CLK_14M,
    CLK_2M         => CLK_2M,
    PRE_PHASE_ZERO => PRE_PHASE_ZERO,
    IO_SELECT      => IO_SELECT(6),
    DEVICE_SELECT  => DEVICE_SELECT(6),
    RESET          => reset,
    A              => ADDR,
    D_IN           => D,
    D_OUT          => PD,
    TRACK          => TRACK,
    TRACK_ADDR     => open,
    D1_ACTIVE      => LED,
    D2_ACTIVE      => open,
    ram_write_addr => TRACK_RAM_ADDR,
    ram_di         => TRACK_RAM_DI,
    ram_we         => TRACK_RAM_WE
    );

end datapath;