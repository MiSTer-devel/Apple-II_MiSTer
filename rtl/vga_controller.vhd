-------------------------------------------------------------------------------
--
-- A VGA line-doubler for an Apple ][
--
-- Stephen A. Edwards, sedwards@cs.columbia.edu
--
--
-- The Apple ][ uses a 14.31818 MHz master clock.  It outputs a new
-- horizontal line every 65 * 14 + 2 = 912 14M cycles.  The extra two
-- are from the "extended cycle" used to keep the 3.579545 MHz
-- colorburst signal in sync.  Of these, 40 * 14 = 560 are active video.
--
-- In graphics mode, the Apple effectively generates 140 four-bit pixels
-- output serially (i.e., with 3.579545 MHz pixel clock).  In text mode,
-- it generates 280 one-bit pixels (i.e., with a 7.15909 MHz pixel clock).
--
-- We capture 140 four-bit nibbles for each line and interpret them in
-- one of the two modes.  In graphics mode, each is displayed as a
-- single pixel of one of 16 colors.  In text mode, each is displayed
-- as two black or white pixels.
-- 
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga_controller is
	port (
		CLK_14M    : in  std_logic;	     -- 14.31818 MHz master clock

		VIDEO      : in std_logic;         -- from the Apple video generator
		COLOR_LINE : in std_logic;
		SCREEN_MODE: in std_logic_vector(1 downto 0);   -- 00: Color, 01: B&W, 10: Green, 11: Amber
		COLOR_PALETTE: in std_logic_vector(1 downto 0); -- 4 palette choices
		GRAY_SEAM_FIX: in std_logic;
		NTSC_VERTICAL_COMB: in std_logic;
		HBL        : in std_logic;
		VBL        : in std_logic;

		VGA_HS     : out std_logic;
		VGA_VS     : out std_logic;
		VGA_HBL    : out std_logic;
		VGA_VBL    : out std_logic;
		VGA_R      : out unsigned(7 downto 0);
		VGA_G      : out unsigned(7 downto 0);
		VGA_B      : out unsigned(7 downto 0);			
        -- load different palettes
	    ioctl_addr : in  std_logic_vector(24 downto 0);
        ioctl_data : in  std_logic_vector(7 downto 0);
		ioctl_index   : in  std_logic_vector(7 downto 0);
		ioctl_download: in  std_logic;
		ioctl_wr   :    in  std_logic;
		ioctl_wait :    out std_logic
	   
	);
end vga_controller;

architecture rtl of vga_controller is

	-- latest color derivation based on Linards' updated approach from:
	-- https://www.reddit.com/r/apple2/comments/1cido07/better_apple_ii_color_theory_and_results/	
	-- https://www.reddit.com/r/apple2/comments/1cisrjf/better_apple_ii_color_theory_and_results_images/

	-- original RGB values from Linards Ticmanis (posted on comp.sys.apple2 on 29-Sep-2005)
	-- https://groups.google.com/g/comp.sys.apple2/c/uILy74pRsrk/m/G9XDxQhWi1AJ

	-- for mpre detail on how the RGB values were determined,
	-- please refer to code and documents in https://github.com/Newsdee/apple2ntsc
		
	constant WHITE: unsigned(7 downto 0) := X"FF";
	constant WHITE_NTSC: unsigned(7 downto 0) := X"F1";
	
	signal shift_reg : unsigned(5 downto 0);  -- Last six pixels

	signal last_hbl : std_logic;
	signal hcount : unsigned(10 downto 0);
	signal vcount : unsigned(5 downto 0);

	constant VGA_HSYNC : integer := 68;
	constant VGA_ACTIVE : integer := 282 * 2;
	constant VGA_FRONT_PORCH : integer := 130;

	constant VBL_TO_VSYNC : integer := 33;
	constant VGA_VSYNC_LINES : integer := 3;

	signal vbl_delayed : std_logic;

	subtype rgb_component_t is unsigned(7 downto 0);
	type rgb_window_t is array (0 to 4) of unsigned(23 downto 0);
	type metric_window_t is array (0 to 4) of integer range 0 to 255;
	type hcount_window_t is array (0 to 4) of unsigned(10 downto 0);
	type rgb_line_ram_t is array (0 to 559) of unsigned(23 downto 0);
	signal previous_line_rgb : rgb_line_ram_t;
	signal previous_line_valid : std_logic := '0';
	signal seam_active_d : std_logic := '0';
	signal comb_hcount : unsigned(10 downto 0) := (others => '0');
	signal line_wr_addr : unsigned(10 downto 0) := (others => '0');
	signal line_wr_data : unsigned(23 downto 0) := (others => '0');
	signal line_wr_en : std_logic := '0';
	signal raw_rgb, seam_rgb, previous_rgb_q, current_rgb_q, filtered_rgb : unsigned(23 downto 0);
	signal raw_hcount : unsigned(10 downto 0);
	signal raw_active, raw_vbl, raw_color_mode, raw_color_line : std_logic;
	signal seam_hcount : unsigned(10 downto 0);
	signal seam_active, seam_timing_active, seam_vbl, seam_color_mode : std_logic;
	signal current_active_q, current_timing_active_q, filtered_timing_active, line_valid_q, color_mode_q : std_logic;
	signal timing_active_delay : std_logic_vector(0 to 13) := (others => '0');
	signal seam_rgb_window : rgb_window_t := (others => (others => '0'));
	signal seam_luma_window, seam_saturation_window : metric_window_t := (others => 0);
	signal seam_hcount_window : hcount_window_t := (others => (others => '0'));
	signal seam_valid_window : std_logic_vector(0 to 4) := (others => '0');
	signal seam_vbl_window : std_logic_vector(0 to 4) := (others => '0');
	signal seam_color_mode_window : std_logic_vector(0 to 4) := (others => '0');
	signal seam_color_line_window : std_logic_vector(0 to 4) := (others => '0');

	function clamp_rgb(value : integer) return rgb_component_t is
	begin
		if value < 0 then
			return X"00";
		elsif value > 255 then
			return X"FF";
		else
			return to_unsigned(value, 8);
		end if;
	end function;

	function rgb_luma(rgb : unsigned(23 downto 0)) return integer is
	begin
		return (306 * to_integer(rgb(23 downto 16)) +
			601 * to_integer(rgb(15 downto 8)) +
			117 * to_integer(rgb(7 downto 0)) + 512) / 1024;
	end function;

	function rgb_saturation(rgb : unsigned(23 downto 0)) return integer is
		variable red, green, blue, maximum, minimum : integer;
	begin
		red := to_integer(rgb(23 downto 16));
		green := to_integer(rgb(15 downto 8));
		blue := to_integer(rgb(7 downto 0));
		maximum := red;
		minimum := red;
		if green > maximum then maximum := green; end if;
		if blue > maximum then maximum := blue; end if;
		if green < minimum then minimum := green; end if;
		if blue < minimum then minimum := blue; end if;
		return maximum - minimum;
	end function;
			
  -- Palette signals
  signal color_addr    : unsigned(1 downto 0);
  signal palette_index : unsigned(3 downto 0);
  signal palette_rgb_in : unsigned(23 downto 0);
  
  -- temporary buffer used for downloads
  signal BUFFER_COL0 : unsigned(23 downto 0) := X"200820";
  signal BUFFER_COL1 : unsigned(23 downto 0) := X"802222";
  signal BUFFER_COL2 : unsigned(23 downto 0) := X"222280";
  signal BUFFER_COL3 : unsigned(23 downto 0) := X"490080";
  signal BUFFER_COL4 : unsigned(23 downto 0) := X"275412";  -- Dk Green
  signal BUFFER_COL5 : unsigned(23 downto 0) := X"636363";  -- gray 1
  signal BUFFER_COL6 : unsigned(23 downto 0) := X"4063ff";  -- Med Blue
  signal BUFFER_COL7 : unsigned(23 downto 0) := X"4adbff";  -- light blue
  signal BUFFER_COL8 : unsigned(23 downto 0) := X"7B4513";
  signal BUFFER_COL9 : unsigned(23 downto 0) := X"FF8C00";
  signal BUFFER_COL10 : unsigned(23 downto 0):= X"818181";
  signal BUFFER_COL11 : unsigned(23 downto 0):= X"f87efc"; -- pink
  signal BUFFER_COL12 : unsigned(23 downto 0):= X"22FF22";
  signal BUFFER_COL13 : unsigned(23 downto 0):= X"FFFF22";
  signal BUFFER_COL14 : unsigned(23 downto 0):= X"ADFFF1";
  signal BUFFER_COL15 : unsigned(23 downto 0):= X"F0F0F0";

  signal CURRENT_COL0 : unsigned(23 downto 0);
  signal CURRENT_COL1 : unsigned(23 downto 0);
  signal CURRENT_COL2 : unsigned(23 downto 0);
  signal CURRENT_COL3 : unsigned(23 downto 0);
  signal CURRENT_COL4 : unsigned(23 downto 0);
  signal CURRENT_COL5 : unsigned(23 downto 0);
  signal CURRENT_COL6 : unsigned(23 downto 0);
  signal CURRENT_COL7 : unsigned(23 downto 0);
  signal CURRENT_COL8 : unsigned(23 downto 0);
  signal CURRENT_COL9 : unsigned(23 downto 0);
  signal CURRENT_COL10 : unsigned(23 downto 0);
  signal CURRENT_COL11 : unsigned(23 downto 0);
  signal CURRENT_COL12 : unsigned(23 downto 0);
  signal CURRENT_COL13 : unsigned(23 downto 0);
  signal CURRENT_COL14 : unsigned(23 downto 0);
  signal CURRENT_COL15 : unsigned(23 downto 0);

begin

-- palette processing
process (CLK_14M)		
begin
    if rising_edge(CLK_14M) then
    
		-- whether to update palette RAM; ioctl_index must be consistent with declaration in MiSTer config string
		if ioctl_download = '1' and ioctl_index = "00000010"  then
			-- palette is downloading so preserve values of registers
			CURRENT_COL0 <= CURRENT_COL0;
			CURRENT_COL1 <= CURRENT_COL1;
			CURRENT_COL2 <= CURRENT_COL2;
			CURRENT_COL3 <= CURRENT_COL3;
			CURRENT_COL4 <= CURRENT_COL4;
			CURRENT_COL5 <= CURRENT_COL5;
			CURRENT_COL6 <= CURRENT_COL6;
			CURRENT_COL7 <= CURRENT_COL7;
			CURRENT_COL8 <= CURRENT_COL8;
			CURRENT_COL9 <= CURRENT_COL9;
			CURRENT_COL10 <= CURRENT_COL10;
			CURRENT_COL11 <= CURRENT_COL11;
			CURRENT_COL12 <= CURRENT_COL12;
			CURRENT_COL13 <= CURRENT_COL13;
			CURRENT_COL14 <= CURRENT_COL14;
			CURRENT_COL15 <= CURRENT_COL15;
			-- write to proper index with downloading palette
			-- but first check if the new data is ready
			if ioctl_wr = '1' then
				
				ioctl_wait <= '1';
				
				case color_addr is
					when "00" => palette_rgb_in <= unsigned(ioctl_data) & palette_rgb_in(15 downto 0) ;
					when "01" => palette_rgb_in <= palette_rgb_in(23 downto 16) & unsigned(ioctl_data) & palette_rgb_in(7 downto 0) ;
					when "10" => palette_rgb_in <= palette_rgb_in(23 downto 8) & unsigned(ioctl_data) ;
					when "11" => palette_rgb_in <= palette_rgb_in(23 downto 8) & unsigned(ioctl_data) ;
				end case;
				case palette_index is
					when "0000" => BUFFER_COL0 <= palette_rgb_in;
					when "0001" => BUFFER_COL1 <= palette_rgb_in;
					when "0010" => BUFFER_COL2 <= palette_rgb_in;
					when "0011" => BUFFER_COL3 <= palette_rgb_in;
					when "0100" => BUFFER_COL4 <= palette_rgb_in;
					when "0101" => BUFFER_COL5 <= palette_rgb_in;
					when "0110" => BUFFER_COL6 <= palette_rgb_in;
					when "0111" => BUFFER_COL7 <= palette_rgb_in;
					when "1000" => BUFFER_COL8 <= palette_rgb_in;
					when "1001" => BUFFER_COL9 <= palette_rgb_in;
					when "1010" => BUFFER_COL10 <= palette_rgb_in;
					when "1011" => BUFFER_COL11 <= palette_rgb_in;
					when "1100" => BUFFER_COL12 <= palette_rgb_in;
					when "1101" => BUFFER_COL13 <= palette_rgb_in;
					when "1110" => BUFFER_COL14 <= palette_rgb_in;
					when "1111" => BUFFER_COL15 <= palette_rgb_in;
				end case;
				if color_addr < "11" then
					color_addr <= color_addr + 1;
				else
					color_addr <= "00";
					palette_index <= palette_index + 1;					
				end if;
				ioctl_wait  <=  '0';
				
			end if;
			
		else
				-- palette is ready, reset vars and update registers
				palette_index <= "0000";
				color_addr <= "00";
				palette_rgb_in <= "000000000000000000000000";
				
				CURRENT_COL0 <= BUFFER_COL0;
				CURRENT_COL1 <= BUFFER_COL1;
				CURRENT_COL2 <= BUFFER_COL2;
				CURRENT_COL3 <= BUFFER_COL3;
				CURRENT_COL4 <= BUFFER_COL4;
				CURRENT_COL5 <= BUFFER_COL5;
				CURRENT_COL6 <= BUFFER_COL6;
				CURRENT_COL7 <= BUFFER_COL7;
				CURRENT_COL8 <= BUFFER_COL8;
				CURRENT_COL9 <= BUFFER_COL9;
				CURRENT_COL10 <= BUFFER_COL10;
				CURRENT_COL11 <= BUFFER_COL11;
				CURRENT_COL12 <= BUFFER_COL12;
				CURRENT_COL13 <= BUFFER_COL13;
				CURRENT_COL14 <= BUFFER_COL14;
				CURRENT_COL15 <= BUFFER_COL15;
		end if;
		
    
	 end if;
end process;



process (CLK_14M)
begin
    if rising_edge(CLK_14M) then
		if last_hbl = '1' and HBL = '0' then  -- Falling edge
			hcount <= (others => '0');
			vbl_delayed <= VBL;
			if VBL = '1' then
				vcount <= vcount + 1;
			else
				vcount <= (others => '0');
			end if;
		else
			hcount <= hcount + 1;
		end if;
		last_hbl <= HBL;
	end if;
end process;

process (CLK_14M)
begin
	if rising_edge(CLK_14M) then
		if hcount = VGA_ACTIVE + VGA_FRONT_PORCH then
			VGA_HS <= '1';
			if vcount = VBL_TO_VSYNC then
				VGA_VS <= '1';
			elsif vcount = VBL_TO_VSYNC + VGA_VSYNC_LINES then
				VGA_VS <= '0';
			end if;
		elsif hcount = VGA_ACTIVE + VGA_FRONT_PORCH + VGA_HSYNC then
			VGA_HS <= '0';
		end if;
	end if;
end process;

process (CLK_14M)
	variable r, g, b : unsigned(7 downto 0); 
	variable shift_color : unsigned(3 downto 0);  -- subset of shift register to determine color in LUT
begin
	if rising_edge(CLK_14M) then
		shift_reg <= VIDEO & shift_reg(5 downto 1);

		r := X"00";
		g := X"00"; 
		b := X"00"; 
		
		-- alternate background for monochrome modes
		case SCREEN_MODE is 
			when "00" => 
				-- color mode background
				if COLOR_PALETTE = "11" then
					-- use custom palette
					r := CURRENT_COL0(23 downto 16); g := CURRENT_COL0(15 downto 8); b := CURRENT_COL0(7 downto 0); -- black
				else
					-- or black for the rest
					r := X"00"; g := X"00"; b := X"00"; 
					
				end if;
			when "01" => r := X"00"; g := X"00"; b := X"00"; -- B&W mode background
			when "10" => r := X"00"; g := X"0F"; b := X"01"; -- green mode background color
			when "11" => r := X"20"; g := X"08"; b := X"01"; -- amber mode background color
		end case;
		
		if COLOR_LINE = '0' then  -- Monochrome mode
		 
			if shift_reg(2) = '1' then
				-- handle green/amber color modes
				case SCREEN_MODE is 
					when "00" => 
						-- white (color mode)
						if COLOR_PALETTE = "00" then
							-- NTSC palette
							r := WHITE_NTSC; g := WHITE_NTSC; b := WHITE_NTSC;
						elsif COLOR_PALETTE = "11" then
							-- custom palette
							r := CURRENT_COL15(23 downto 16); g := CURRENT_COL15(15 downto 8); b := CURRENT_COL15(7 downto 0); -- white
						else
							-- Apple IIgs and AppleWin palettes
							r := WHITE; g := WHITE; b := WHITE;
						end if;						
					when "01" => r := WHITE; g := WHITE; b := WHITE; -- white (B&W mode)
					when "10" => r := X"00"; g := X"C0"; b := X"01"; -- green
					when "11" => r := X"FF"; g := X"80"; b := X"01"; -- amber 
				end case;
			end if;
			
		-- Sharper mode also colorizes non-periodic transition dots through the
		-- LUT (AppleWin-style) instead of rendering them gray; lit dots always
		-- map to a non-black color, so the on/off silhouette is preserved.
		-- Plain white<->black edges are excluded and keep the left-side level.
		elsif (shift_reg(0) = shift_reg(4) and shift_reg(5) = shift_reg(1)) or
			(GRAY_SEAM_FIX = '1' and (shift_reg(3 downto 2) = "01" or shift_reg(3 downto 2) = "10") and
			not ((shift_reg(1 downto 0) = "11" and shift_reg(5 downto 4) = "00") or
			(shift_reg(1 downto 0) = "00" and shift_reg(5 downto 4) = "11"))) then
		 			
			-- rotate the 4-bit value based on contents of shift register
			-- then apply the color mapping
			shift_color := shift_reg(4 downto 1) rol to_integer(hcount);
			
			if COLOR_PALETTE = "00" then
				-- lticmanis 2024 (default)
				-- 'correct' palette derived by mathematical NTSC formulas, 
				-- calibrated to approximate GS colors as much NTSC can
				case shift_color is
					when "0000"      => r := X"00"; g := X"00"; b := X"00"; -- black   
					when "0010"      => r := X"9F"; g := X"1B"; b := X"48"; -- magenta 
					when "0100"      => r := X"48"; g := X"32"; b := X"EB"; -- dark blue
					when "0110"      => r := X"D6"; g := X"43"; b := X"EF"; -- purple
					when "1000"      => r := X"19"; g := X"75"; b := X"44"; -- dark green
					when "0101"      => r := X"81"; g := X"81"; b := X"81"; -- gray 1
					when "1100"      => r := X"36"; g := X"92"; b := X"FF"; -- med blue
					when "1110"      => r := X"D8"; g := X"9E"; b := X"FF"; -- light blue
					when "0001"      => r := X"49"; g := X"65"; b := X"00"; -- brown   
					when "0011"      => r := X"D8"; g := X"73"; b := X"00"; -- orange  
					when "1010"      => r := X"81"; g := X"81"; b := X"81"; -- gray 2
					when "0111"      => r := X"FB"; g := X"8F"; b := X"BC"; -- pink
					when "1001"      => r := X"3C"; g := X"CC"; b := X"00"; -- green
					when "1011"      => r := X"BC"; g := X"D6"; b := X"00"; -- yellow
					when "1101"      => r := X"6C"; g := X"E6"; b := X"B8"; -- aquamarine
					when "1111"      => r := WHITE_NTSC; g := WHITE_NTSC; b := WHITE_NTSC; -- white
				end case;
				
			elsif COLOR_PALETTE = "01" then
				-- Apple IIgs & LC (//e mode) palette 
				--   see "IIGS Technical Note #63" from Apple ,
				--   and the 'clut' resource "Apple IIe Colors" in the IIe card's "IIe Startup" 68K Mac executable version 2.2.1d.
				case shift_color is
					when "0000"      => r := X"00"; g := X"00"; b := X"00"; --  0 - black   
					when "0010"      => r := X"DB"; g := X"1F"; b := X"42"; --  1 - magenta 
					when "0100"      => r := X"0C"; g := X"11"; b := X"A4"; --  2 - dark blue
					when "0110"      => r := X"DC"; g := X"43"; b := X"E1"; --  3 - purple
					when "1000"      => r := X"1C"; g := X"82"; b := X"31"; --  4 - dark green
					when "0101"      => r := X"B3"; g := X"B3"; b := X"B3"; --  5 - gray 1
					when "1100"      => r := X"39"; g := X"3D"; b := X"FF"; --  6 - med blue
					when "1110"      => r := X"7A"; g := X"B3"; b := X"FF"; --  7 - light blue
					when "0001"      => r := X"91"; g := X"64"; b := X"00"; --  8 - brown   
					when "0011"      => r := X"FA"; g := X"77"; b := X"00"; --  9 - orange  
					when "1010"      => r := X"63"; g := X"63"; b := X"63"; -- 10 - gray 2
					when "0111"      => r := X"FB"; g := X"A5"; b := X"93"; -- 11 - pink
					when "1001"      => r := X"40"; g := X"DE"; b := X"00"; -- 12 - green
					when "1011"      => r := X"FE"; g := X"FE"; b := X"00"; -- 13 - yellow
					when "1101"      => r := X"67"; g := X"FC"; b := X"A4"; -- 14 - aquamarine
					when "1111"      => r := WHITE; g := WHITE; b := WHITE; -- 15 - white
				end case;
				
				elsif COLOR_PALETTE = "10" then
				-- AppleWin palette as of 1.13.18.0
				case shift_color is
					when "0000"      => r := X"00"; g := X"00"; b := X"00"; -- black   
					when "0010"      => r := X"93"; g := X"0B"; b := X"7C"; -- magenta 
					when "0100"      => r := X"1F"; g := X"35"; b := X"D3"; -- dark blue
					when "0110"      => r := X"BB"; g := X"36"; b := X"FF"; -- purple
					when "1000"      => r := X"00"; g := X"76"; b := X"0C"; -- dark green
					when "0101"      => r := X"7E"; g := X"7E"; b := X"7E"; -- gray 1
					when "1100"      => r := X"07"; g := X"A8"; b := X"E0"; -- med blue
					when "1110"      => r := X"9D"; g := X"AC"; b := X"FF"; -- light blue
					when "0001"      => r := X"62"; g := X"4C"; b := X"00"; -- brown   
					when "0011"      => r := X"F9"; g := X"56"; b := X"1D"; -- orange  
					when "1010"      => r := X"7E"; g := X"7E"; b := X"7E"; -- gray 2
					when "0111"      => r := X"FF"; g := X"81"; b := X"EC"; -- pink
					when "1001"      => r := X"43"; g := X"C8"; b := X"00"; -- green
					when "1011"      => r := X"DC"; g := X"CD"; b := X"16"; -- yellow
					when "1101"      => r := X"5D"; g := X"F7"; b := X"84"; -- aquamarine
					when "1111"      => r := WHITE; g := WHITE; b := WHITE; -- white
				end case;
			else
					
				-- Use custom palette
					case shift_color is
						when "0000"      =>  r := CURRENT_COL0(23 downto 16); g := CURRENT_COL0(15 downto 8); b := CURRENT_COL0(7 downto 0);  --black
						when "0010"      =>  r := CURRENT_COL1(23 downto 16); g := CURRENT_COL1(15 downto 8); b := CURRENT_COL1(7 downto 0);  --magenta
						when "0100"      =>  r := CURRENT_COL2(23 downto 16); g := CURRENT_COL2(15 downto 8); b := CURRENT_COL2(7 downto 0);  --purple
						when "0110"      =>  r := CURRENT_COL3(23 downto 16); g := CURRENT_COL3(15 downto 8); b := CURRENT_COL3(7 downto 0);  -- purple
						when "1000"      =>  r := CURRENT_COL4(23 downto 16); g := CURRENT_COL4(15 downto 8); b := CURRENT_COL4(7 downto 0);  -- dark green
						when "1010"      =>  r := CURRENT_COL5(23 downto 16); g := CURRENT_COL5(15 downto 8); b := CURRENT_COL5(7 downto 0); -- gray 1
						when "1100"      =>  r := CURRENT_COL6(23 downto 16); g := CURRENT_COL6(15 downto 8); b := CURRENT_COL6(7 downto 0);  -- med blue
						when "1110"      =>  r := CURRENT_COL7(23 downto 16); g := CURRENT_COL7(15 downto 8); b := CURRENT_COL7(7 downto 0);  -- light blue
						when "0001"      =>  r := CURRENT_COL8(23 downto 16); g := CURRENT_COL8(15 downto 8); b := CURRENT_COL8(7 downto 0);  -- brown   
						when "0011"      =>  r := CURRENT_COL9(23 downto 16); g := CURRENT_COL9(15 downto 8); b := CURRENT_COL9(7 downto 0);   -- orange  
						when "0101"      =>  r := CURRENT_COL10(23 downto 16); g := CURRENT_COL10(15 downto 8); b := CURRENT_COL10(7 downto 0);  -- gray 2
						when "0111"      =>  r := CURRENT_COL11(23 downto 16); g := CURRENT_COL11(15 downto 8); b := CURRENT_COL11(7 downto 0); -- pink
						when "1001"      =>  r := CURRENT_COL12(23 downto 16); g := CURRENT_COL12(15 downto 8); b := CURRENT_COL12(7 downto 0); -- green
						when "1011"      =>  r := CURRENT_COL13(23 downto 16); g := CURRENT_COL13(15 downto 8); b := CURRENT_COL13(7 downto 0); -- yellow
						when "1101"      =>  r := CURRENT_COL14(23 downto 16); g := CURRENT_COL14(15 downto 8); b := CURRENT_COL14(7 downto 0); -- aquamarine
						when "1111"      =>  r := CURRENT_COL15(23 downto 16); g := CURRENT_COL15(15 downto 8); b := CURRENT_COL15(7 downto 0); -- white
					end case;	
					
			end if;
		else
		 
			-- Tint is changing: display only black, gray, or white
			case shift_reg(3 downto 2) is
				when "11"        =>
				
					-- white
					if COLOR_PALETTE = "00" then
						r := WHITE_NTSC; g := WHITE_NTSC; b := WHITE_NTSC;
					elsif COLOR_PALETTE = "11" then
						-- custom palette
						r := CURRENT_COL15(23 downto 16); g := CURRENT_COL15(15 downto 8); b := CURRENT_COL15(7 downto 0); -- white
					else
						r := WHITE; g := WHITE; b := WHITE;
					end if;
				
				-- gray - we use the darkest gray of all the palettes to avoid it being too prominent
				when "01" | "10" => 
					if GRAY_SEAM_FIX = '1' then
						-- Only white<->black edges reach here in sharper mode.
						if shift_reg(1) = '1' then
							if COLOR_PALETTE = "00" then
								r := WHITE_NTSC; g := WHITE_NTSC; b := WHITE_NTSC;
							elsif COLOR_PALETTE = "11" then
								r := CURRENT_COL15(23 downto 16); g := CURRENT_COL15(15 downto 8); b := CURRENT_COL15(7 downto 0);
							else
								r := WHITE; g := WHITE; b := WHITE;
							end if;
						end if;
						-- left black keeps the background level already assigned
					elsif COLOR_PALETTE = "11" then
						 r := CURRENT_COL5(23 downto 16); g := CURRENT_COL5(15 downto 8); b := CURRENT_COL5(7 downto 0); -- gray 1 (darker)
					else
						r := X"63"; g := X"63"; b := X"63";
					end if;
				-- black
				when others      => r := X"00"; g := X"00"; b := X"00";
			end case;
		end if;
		  
		raw_rgb <= r & g & b;
		raw_hcount <= hcount;
		raw_vbl <= VBL;
		raw_color_line <= COLOR_LINE;
		if HBL = '0' and hcount < to_unsigned(560, hcount'length) then
			raw_active <= '1';
		else
			raw_active <= '0';
		end if;
		if SCREEN_MODE = "00" then
			raw_color_mode <= '1';
		else
			raw_color_mode <= '0';
		end if;
	end if;
end process pixel_generator;

process (CLK_14M)
	variable next_rgb : rgb_window_t;
	variable next_luma, next_saturation : metric_window_t;
	variable next_hcount : hcount_window_t;
	variable next_valid, next_vbl : std_logic_vector(0 to 4);
	variable next_color_mode, next_color_line : std_logic_vector(0 to 4);
	variable output_rgb : unsigned(23 downto 0);
begin
	if rising_edge(CLK_14M) then
		for index in 0 to 3 loop
			next_rgb(index) := seam_rgb_window(index + 1);
			next_luma(index) := seam_luma_window(index + 1);
			next_saturation(index) := seam_saturation_window(index + 1);
			next_hcount(index) := seam_hcount_window(index + 1);
			next_valid(index) := seam_valid_window(index + 1);
			next_vbl(index) := seam_vbl_window(index + 1);
			next_color_mode(index) := seam_color_mode_window(index + 1);
			next_color_line(index) := seam_color_line_window(index + 1);
		end loop;

		next_rgb(4) := raw_rgb;
		next_luma(4) := rgb_luma(raw_rgb);
		next_saturation(4) := rgb_saturation(raw_rgb);
		next_hcount(4) := raw_hcount;
		next_valid(4) := raw_active;
		next_vbl(4) := raw_vbl;
		next_color_mode(4) := raw_color_mode;
		next_color_line(4) := raw_color_line;

		-- Colorization happens in the pixel generator, so use the newest RGB
		-- sample while preserving the established active-window timing below.
		output_rgb := next_rgb(4);

		seam_rgb_window <= next_rgb;
		seam_luma_window <= next_luma;
		seam_saturation_window <= next_saturation;
		seam_hcount_window <= next_hcount;
		seam_valid_window <= next_valid;
		seam_vbl_window <= next_vbl;
		seam_color_mode_window <= next_color_mode;
		seam_color_line_window <= next_color_line;

		seam_rgb <= output_rgb;
		seam_hcount <= next_hcount(4);
		seam_active <= next_valid(4);
		timing_active_delay <= timing_active_delay(1 to 13) & next_valid(2);
		seam_timing_active <= timing_active_delay(0);
		seam_vbl <= next_vbl(4);
		seam_color_mode <= next_color_mode(4);
	end if;
end process seam_cleanup;

process (CLK_14M)
begin
	if rising_edge(CLK_14M) then
		current_rgb_q <= seam_rgb;
		current_active_q <= seam_active;
		current_timing_active_q <= seam_timing_active;
		line_valid_q <= previous_line_valid;
		color_mode_q <= seam_color_mode;

		-- Write is delayed one cycle so the read of address A always precedes
		-- the write of A; old-line data no longer depends on the RAM's
		-- read-during-write mode (M10K cannot return old data on one port).
		line_wr_en <= '0';
		seam_active_d <= seam_timing_active;
		if seam_vbl = '1' then
			previous_line_valid <= '0';
			comb_hcount <= (others => '0');
		elsif seam_timing_active = '1' then
			previous_rgb_q <= previous_line_rgb(to_integer(comb_hcount));
			line_wr_addr <= comb_hcount;
			line_wr_data <= seam_rgb;
			line_wr_en <= '1';
			comb_hcount <= comb_hcount + 1;
		elsif seam_active_d = '1' then
			previous_line_valid <= '1';
			comb_hcount <= (others => '0');
		end if;
		if line_wr_en = '1' then
			previous_line_rgb(to_integer(line_wr_addr)) <= line_wr_data;
		end if;
	end if;
end process vertical_line_buffer;

process (CLK_14M)
	variable output_rgb : unsigned(23 downto 0);
	variable current_luma, previous_luma : integer;
	variable red_chroma, green_chroma, blue_chroma : integer;
begin
	if rising_edge(CLK_14M) then
		output_rgb := current_rgb_q;
		filtered_timing_active <= current_timing_active_q;
		if NTSC_VERTICAL_COMB = '1' and current_timing_active_q = '1' and
			line_valid_q = '1' and color_mode_q = '1' then
			current_luma := (306 * to_integer(current_rgb_q(23 downto 16)) +
				601 * to_integer(current_rgb_q(15 downto 8)) +
				117 * to_integer(current_rgb_q(7 downto 0)) + 512) / 1024;
			previous_luma := (306 * to_integer(previous_rgb_q(23 downto 16)) +
				601 * to_integer(previous_rgb_q(15 downto 8)) +
				117 * to_integer(previous_rgb_q(7 downto 0)) + 512) / 1024;

			red_chroma := (to_integer(current_rgb_q(23 downto 16)) - current_luma +
				to_integer(previous_rgb_q(23 downto 16)) - previous_luma) / 2;
			green_chroma := (to_integer(current_rgb_q(15 downto 8)) - current_luma +
				to_integer(previous_rgb_q(15 downto 8)) - previous_luma) / 2;
			blue_chroma := (to_integer(current_rgb_q(7 downto 0)) - current_luma +
				to_integer(previous_rgb_q(7 downto 0)) - previous_luma) / 2;

			-- JS comb keeps each line's own luma and averages only chroma.
			output_rgb := clamp_rgb(current_luma + red_chroma) &
				clamp_rgb(current_luma + green_chroma) &
				clamp_rgb(current_luma + blue_chroma);
		end if;
		filtered_rgb <= output_rgb;
	end if;
end process vertical_comb_filter;

VGA_R <= filtered_rgb(23 downto 16);
VGA_G <= filtered_rgb(15 downto 8);
VGA_B <= filtered_rgb(7 downto 0);

VGA_VBL <= vbl_delayed;
VGA_HBL <= not filtered_timing_active;

end rtl;
