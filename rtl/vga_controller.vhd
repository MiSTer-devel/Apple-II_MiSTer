-------------------------------------------------------------------------------
--
-- A VGA line-doubler for an Apple ][
--
-- Stephen A. Edwards, sedwards@cs.columbia.edu
--
--
-- FIXME: This is all wrong
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
		HBL        : in std_logic;
		VBL        : in std_logic;

		VGA_HS     : out std_logic;
		VGA_VS     : out std_logic;
		VGA_HBL    : out std_logic;
		VGA_VBL    : out std_logic;
		VGA_R      : out unsigned(7 downto 0);
		VGA_G      : out unsigned(7 downto 0);
		VGA_B      : out unsigned(7 downto 0)
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
	
	type basis_color is array(0 to 3) of unsigned(7 downto 0);
		
	-- old FPGA core palette (sedwards 2009)
	constant basis_r : basis_color := ( X"88", X"38", X"07", X"38" );
	constant basis_g : basis_color := ( X"22", X"24", X"67", X"52" );
	constant basis_b : basis_color := ( X"2C", X"A0", X"2C", X"07" );

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
	signal de_delayed : std_logic_vector(17 downto 0);

begin

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
			when "00" => r := X"00"; g := X"00"; b := X"00"; -- color mode background
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
							r := WHITE_NTSC; g := WHITE_NTSC; b := WHITE_NTSC;
						else
							r := WHITE; g := WHITE; b := WHITE;
						end if;						
					when "01" => r := WHITE; g := WHITE; b := WHITE; -- white (B&W mode)
					when "10" => r := X"00"; g := X"C0"; b := X"01"; -- green
					when "11" => r := X"FF"; g := X"80"; b := X"01"; -- amber 
				end case;
			end if;
			
		elsif shift_reg(0) = shift_reg(4) and shift_reg(5) = shift_reg(1) then
		 			
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
			
				-- Handpicked colors by visual comparison of all palettes vs. a //c PAL display
				-- PAL //c displays do not have artifacto color and produce B&W images,
				-- so this is an attempt to make color work with composite video-out on such displays
				-- (NOTE: commented-out values will fallback to the apple2fpga method)
				case shift_color is
					when "0000"      => r := X"00"; g := X"00"; b := X"00";    --  0 - black   
					-- when "0010"      => r := X"93"; g := X"0B"; b := X"7C"; --  1 - magenta    (apple2fpga)
					-- when "0100"      => r := X"1F"; g := X"35"; b := X"D3"; --  2 - dark blue  (apple2fpga)
					when "0110"      => r := X"DC"; g := X"43"; b := X"E1";    --  3 - purple     (Apple IIgs)
					--when "1000"      => r := X"00"; g := X"76"; b := X"0C";  --  4 - dark green (apple2fpga)
					when "0101"      => r := X"7E"; g := X"7E"; b := X"7E";    --  5 - gray 1     (AppleWin)
					when "1100"      => r := X"36"; g := X"92"; b := X"FF";    --  6 - med blue   (IIe)
					when "1110"      => r := X"7A"; g := X"B3"; b := X"FF";    --  7 - light blue (Apple IIgs)
					-- when "0001"      => r := X"62"; g := X"4C"; b := X"00"; --  8 - brown      (apple2fpga)
					when "0011"      => r := X"F9"; g := X"56"; b := X"1D";    --  9 - orange     (Apple IIgs)
					when "1010"      => r := X"7E"; g := X"7E"; b := X"7E";    -- 10 - gray 2     (AppleWin)
					when "0111"      => r := X"FB"; g := X"A5"; b := X"93";    -- 11 - pink       (Apple IIgs)
					when "1001"      => r := X"40"; g := X"DE"; b := X"00";    -- 12 - green      (Apple IIgs)
					when "1011"      => r := X"DC"; g := X"CD"; b := X"16";    -- 13 - Yellow     (AppleWin)
					when "1101"      => r := X"67"; g := X"FC"; b := X"A4";    -- 14 - aquamarine (Apple IIgs)
					when "1111"      => r := WHITE; g := WHITE; b := WHITE;    -- 15 - white
					
					when "0010"|"0100"|"1000"|"0001" =>
								
						-- original implementaiton of Apple II FPGA core (sedwards, 2009)
						-- Tint of adjacent pixels is consistent : display the color
						if shift_reg(3) = '1' then
							r := r + basis_r(to_integer(hcount + 1));
							g := g + basis_g(to_integer(hcount + 1));
							b := b + basis_b(to_integer(hcount + 1));
						end if;
						if shift_reg(4) = '1' then
							r := r + basis_r(to_integer(hcount + 2));
							g := g + basis_g(to_integer(hcount + 2));
							b := b + basis_b(to_integer(hcount + 2));
						end if;
						if shift_reg(1) = '1' then
							r := r + basis_r(to_integer(hcount + 3));
							g := g + basis_g(to_integer(hcount + 3));
							b := b + basis_b(to_integer(hcount + 3));
						end if;
						if shift_reg(2) = '1' then
							r := r + basis_r(to_integer(hcount));
							g := g + basis_g(to_integer(hcount));
							b := b + basis_b(to_integer(hcount));
						end if;
					
				end case;
			end if;
		else
		 
			-- Tint is changing: display only black, gray, or white
			case shift_reg(3 downto 2) is
				when "11"        =>
				
					-- white
					if COLOR_PALETTE = "00" then
						r := WHITE_NTSC; g := WHITE_NTSC; b := WHITE_NTSC;
					else
						r := WHITE; g := WHITE; b := WHITE;
					end if;
				
				-- gray - we use the darkest gray of all the palettes to avoid it being too prominent
				when "01" | "10" => r := X"63"; g := X"63"; b := X"63";
					
				-- black
				when others      => r := X"00"; g := X"00"; b := X"00";
			end case;
		end if;
		  
		VGA_R <= r;
		VGA_G <= g;
		VGA_B <= b;
		
		de_delayed <= de_delayed(16 downto 0) & last_hbl;
	end if;
end process pixel_generator;

VGA_VBL <= vbl_delayed;
VGA_HBL <= de_delayed(9) and de_delayed(17);

end rtl;
