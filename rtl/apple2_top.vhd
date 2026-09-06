--
-- Apple II+ toplevel abstract
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

entity apple2_top is
port (
	CLK_14M        : in std_logic;
	CLK_50M        : in std_logic;


	reset_cold     : in std_logic;
	reset_warm     : in std_logic;
	soft_reset     : buffer std_logic;
	cpu_type       : in std_logic;
	CPU_WAIT       : in std_logic;
	cpu_stall      : in std_logic;

	-- main RAM
	ram_we         : out std_logic;
	ram_di         : out std_logic_vector(7 downto 0);
	ram_do         : in  std_logic_vector(15 downto 0);
	ram_addr       : out std_logic_vector(17 downto 0);
	ram_aux        : out std_logic;

	-- load replacement rom files	
	ioctl_addr    : in  std_logic_vector(24 downto 0);
	ioctl_data    : in  std_logic_vector(7 downto 0);
	ioctl_index   : in  std_logic_vector(7 downto 0);
	ioctl_download: in  std_logic;
	ioctl_wr      : in  std_logic;
	ioctl_wait	  : out std_logic;

	-- video output
	hsync          : out std_logic;
	vsync          : out std_logic;
	hblank         : out std_logic;
	vblank         : out std_logic;
	r              : out std_logic_vector(7 downto 0);
	g              : out std_logic_vector(7 downto 0);
	b              : out std_logic_vector(7 downto 0);
	SCREEN_MODE    : in  std_logic_vector(1 downto 0); -- 00: Color, 01: B&W, 10:Green, 11: Amber
	TEXT_COLOR     : in  std_logic; -- 1 = color processing for
	                                -- text lines in mixed modes
	
	video_switch   : out std_logic;
	palette_switch : out std_logic;
	COLOR_PALETTE  :  in std_logic_vector(1 downto 0); -- 00: Original (//e NTSC), 01: //gs, 02: AppleWin, 03: //c PAL
	GRAY_SEAM_FIX  : in std_logic;
	SEAM_RUN_FILL  : in std_logic;
  SEAM_RUN_WIDE  : in std_logic;
	NTSC_VERTICAL_COMB : in std_logic;
	
    PALMODE        : in  std_logic := '0';       -- PAL/NTSC selection
    ROMSWITCH      : in std_logic;

	PS2_Key        : in  std_logic_vector(10 downto 0);
  virtual_keyboard_active : in std_logic;
  virtual_keyboard_event : in std_logic;
  virtual_keyboard_pressed : in std_logic;
  virtual_keyboard_code : in std_logic_vector(6 downto 0);
  virtual_control : in std_logic;
  virtual_open_apple : in std_logic;
  virtual_closed_apple : in std_logic;
	joy            : in  std_logic_vector(7 downto 0);
	joy_an         : in  std_logic_vector(15 downto 0);
	JOY_TO_KEY_EN  : in  std_logic;  -- OSD: joystick-to-keys enable (P3oB)


	-- disk control
	TRACK1         : out unsigned( 5 downto 0); -- Current track (0-34)
	TRACK1_ADDR    : out unsigned(12 downto 0);
	TRACK1_DI      : out unsigned( 7 downto 0);
	TRACK1_DO      : in  unsigned( 7 downto 0);
	TRACK1_WE      : out std_logic;
	TRACK1_BUSY    : in  std_logic;
	-- Track buffer interface disk 2
	TRACK2         : out unsigned( 5 downto 0); -- Current track (0-34)
	TRACK2_ADDR    : out unsigned(12 downto 0);
	TRACK2_DI      : out unsigned( 7 downto 0);
	TRACK2_DO      : in  unsigned( 7 downto 0);
	TRACK2_WE      : out std_logic;
	TRACK2_BUSY    : in  std_logic;
	 
	D1_ACTIVE      : buffer std_logic;             -- Disk 1 motor on
	D2_ACTIVE      : buffer std_logic;             -- Disk 2 motor on
  D1_MOTOR_ON    : out std_logic;
  D2_MOTOR_ON    : out std_logic;
  D1_IO_ACTIVE   : out std_logic;
  D2_IO_ACTIVE   : out std_logic;
	D1_STEP_ACTIVE : out std_logic;
	D2_STEP_ACTIVE : out std_logic;
  D1_TRACK_ZERO_STEP : out std_logic;
  D2_TRACK_ZERO_STEP : out std_logic;
	
	D1_WP          : in std_logic;
	D2_WP          : in std_logic;

	DISK_ACT       : out std_logic;

	DISK_READY     : in  std_logic_vector(1 downto 0);


	 
	-- HDD control
	HDD_SECTOR     : out unsigned(15 downto 0);
	HDD_READ       : out std_logic;
	HDD_WRITE      : out std_logic;
	HDD_MOUNTED    : in  std_logic;
	HDD_PROTECT    : in  std_logic;
	HDD_RAM_ADDR   : in  unsigned(8 downto 0);
	HDD_RAM_DI     : in  unsigned(7 downto 0);
	HDD_RAM_DO     : out unsigned(7 downto 0);
	HDD_RAM_WE     : in  std_logic;

	AUDIO_L        : out std_logic_vector(9 downto 0);
	AUDIO_R        : out std_logic_vector(9 downto 0);
	TAPE_IN        : in  std_logic;

	UART_TXD       :out  std_logic;
	UART_RXD       :in  std_logic;
	UART_RTS       :out  std_logic;
	UART_CTS       :in  std_logic;
	UART_DTR       :out  std_logic;
	UART_DSR       :in  std_logic;
	RTC            :in  std_logic_vector(64 downto 0);
	
	
	mouse_strobe : in std_logic;
	mouse_x      : in signed(8 downto 0);
	mouse_y      : in signed(8 downto 0);
	mouse_button  : in std_logic;
	
	
	mouse_4_inslot  : in std_logic;
	mouse_5_inslot  : in std_logic;
	-- mocking board
	mb_4_inslot     : in std_logic;
	mb_5_inslot     : in std_logic;
	saturn_5_inslot : in std_logic	
);
end apple2_top;

architecture arch of apple2_top is
  component superserial is
    port (
	CLK_14M  	: in std_logic;
	CLK_2M  	: in std_logic;
	CLK_50M		: in std_logic;
	PH_2    	: in std_logic;
	IO_SELECT_N	: in std_logic;
	DEVICE_SELECT_N : in std_logic;
	IO_STROBE_N  	: in std_logic;
	ADDRESS     	: std_logic_vector(15 downto 0);
	RW_N        	: in std_logic;
	RESET      	: in std_logic;
	DATA_IN    	: in std_logic_vector(7 downto 0);
	DATA_OUT   	: out std_logic_vector(7 downto 0);
	ROM_EN 		: out std_logic;
	UART_CTS 	: in std_logic;
	UART_RTS 	: out std_logic;
	UART_RXD 	: in std_logic;
	UART_TXD 	: out std_logic;
	UART_DTR 	: out std_logic;
	UART_DSR 	: in std_logic;
	IRQ_N 		: out std_logic);


  end component;
  
  -- No Slot Clock (NSC) — replaces the old clock_card. Verilog modules;
-- see NSC_PORT_NOTES.md in Apple-II-Verilog_MiSTer for protocol notes.
component nsc_ticker is
    port (
      clk      : in  std_logic;
      rst      : in  std_logic;
      rtc      : in  std_logic_vector(64 downto 0);
      time_bcd : out std_logic_vector(63 downto 0);
      time_en  : out std_logic
    );
end component;

component no_slot_clock is
    port (
      clk           : in  std_logic;
      rst           : in  std_logic;
      strobe        : in  std_logic;
      addr          : in  std_logic_vector(15 downto 0);
      rw            : in  std_logic;
      slot_sel      : in  std_logic;
      input_time    : in  std_logic_vector(83 downto 0);
      input_time_en : in  std_logic;
      wr_data       : out std_logic_vector(7 downto 0);
      wr_data_en    : out std_logic
    );
end component;

  -- Joy-to-key (rtl/joy_to_key.v): maps digital joystick bits to Apple II
  -- keystrokes. NOTE: the keyboard component ports below and the joy_to_key
  -- instantiation are unconditional here because Quartus 17.0.2 does not
  -- process Verilog-style ifdef directives in VHDL; the Verilog side is
  -- gated by the JOY_TO_KEY macro, so the macro must stay defined for this
  -- design.
  component joy_to_key is
    port (
      clk            : in  std_logic;
      reset          : in  std_logic;
      enable         : in  std_logic;
      joy            : in  std_logic_vector(7 downto 0);
      ioctl_download : in  std_logic;
      ioctl_wr       : in  std_logic;
      ioctl_addr     : in  std_logic_vector(24 downto 0);
      ioctl_data     : in  std_logic_vector(7 downto 0);
      ioctl_index    : in  std_logic_vector(7 downto 0);
      joy_key_press  : out std_logic;
      joy_key_code   : out std_logic_vector(6 downto 0)
    );
  end component;

  component keyboard is
    port (
      CLK_14M  : in std_logic;
      PS2_Key  : in std_logic_vector(10 downto 0);
      virtual_active       : in std_logic;
      virtual_event        : in std_logic;
      virtual_pressed      : in std_logic;
      virtual_code         : in std_logic_vector(6 downto 0);
      virtual_control      : in std_logic;
      virtual_open_apple   : in std_logic;
      virtual_closed_apple : in std_logic;
      joy_key_code   : in std_logic_vector(6 downto 0);
      joy_key_press  : in std_logic;
      reads    : in std_logic;
      reset    : in std_logic;
      akd      : buffer std_logic;
      K        : out unsigned(7 downto 0);
      open_apple:    out std_logic;
      closed_apple:  out std_logic;
      soft_reset:    out std_logic;
      video_toggle:  out std_logic;
      palette_toggle:out std_logic
    );
  end component;

  component disk_ii is
    port (
      CLK_14M        : in  std_logic;
      CLK_2M         : in  std_logic;
      PHASE_ZERO     : in  std_logic;
      IO_SELECT      : in  std_logic;
      DEVICE_SELECT  : in  std_logic;
      RESET          : in  std_logic;
      DISK_READY     : in  std_logic_vector(1 downto 0);
      A              : in  unsigned(15 downto 0);
      D_IN           : in  unsigned(7 downto 0);
      D_OUT          : out unsigned(7 downto 0);
      D1_ACTIVE      : out std_logic;
      D2_ACTIVE      : out std_logic;
      D1_MOTOR_ON    : out std_logic;
      D2_MOTOR_ON    : out std_logic;
      D1_IO_ACTIVE   : out std_logic;
      D2_IO_ACTIVE   : out std_logic;
      D1_STEP_ACTIVE : out std_logic;
      D2_STEP_ACTIVE : out std_logic;
      D1_TRACK_ZERO_STEP : out std_logic;
      D2_TRACK_ZERO_STEP : out std_logic;
      D1_WP          : in  std_logic;
      D2_WP          : in  std_logic;
      TRACK1         : out unsigned(5 downto 0);
      TRACK1_ADDR    : out unsigned(12 downto 0);
      TRACK1_DI      : out unsigned(7 downto 0);
      TRACK1_DO      : in  unsigned(7 downto 0);
      TRACK1_WE      : out std_logic;
      TRACK1_BUSY    : in  std_logic;
      TRACK2         : out unsigned(5 downto 0);
      TRACK2_ADDR    : out unsigned(12 downto 0);
      TRACK2_DI      : out unsigned(7 downto 0);
      TRACK2_DO      : in  unsigned(7 downto 0);
      TRACK2_WE      : out std_logic;
      TRACK2_BUSY    : in  std_logic
    );
  end component;

  component vga_controller is
    port (
      CLK_14M            : in  std_logic;
      VIDEO              : in  std_logic;
      COLOR_LINE         : in  std_logic;
      SCREEN_MODE        : in  std_logic_vector(1 downto 0);
      COLOR_PALETTE      : in  std_logic_vector(1 downto 0);
      GRAY_SEAM_FIX      : in  std_logic;
      SEAM_RUN_FILL      : in  std_logic;
      SEAM_RUN_WIDE      : in  std_logic;
      RUN_FILL_OK        : in  std_logic;
      NTSC_VERTICAL_COMB : in  std_logic;
      HBL                : in  std_logic;
      VBL                : in  std_logic;
      VGA_HS             : out std_logic;
      VGA_VS             : out std_logic;
      VGA_HBL            : out std_logic;
      VGA_VBL            : out std_logic;
      VGA_R              : out unsigned(7 downto 0);
      VGA_G              : out unsigned(7 downto 0);
      VGA_B              : out unsigned(7 downto 0);
      ioctl_addr         : in  std_logic_vector(24 downto 0);
      ioctl_data         : in  std_logic_vector(7 downto 0);
      ioctl_index        : in  std_logic_vector(7 downto 0);
      ioctl_download     : in  std_logic;
      ioctl_wr           : in  std_logic;
      ioctl_wait         : out std_logic
    );
  end component;

  component mockingboard is
    port (
      CLK_14M      : in  std_logic;
      PHASE_ZERO   : in  std_logic;
      PHASE_ZERO_R : in  std_logic;
      PHASE_ZERO_F : in  std_logic;
      I_ADDR       : in  std_logic_vector(7 downto 0);
      I_DATA       : in  std_logic_vector(7 downto 0);
      O_DATA       : out std_logic_vector(7 downto 0);
      OE           : out std_logic;
      I_RW_L       : in  std_logic;
      O_IRQ_L      : out std_logic;
      O_NMI_L      : out std_logic;
      I_IOSEL_L    : in  std_logic;
      I_RESET_L    : in  std_logic;
      I_ENA_H      : in  std_logic;
      O_AUDIO_L    : out std_logic_vector(9 downto 0);
      O_AUDIO_R    : out std_logic_vector(9 downto 0)
    );
  end component;


  signal CLK_2M, CLK_2M_D, PHASE_ZERO, PHASE_ZERO_R, PHASE_ZERO_F : std_logic;
  signal IO_SELECT, DEVICE_SELECT : std_logic_vector(7 downto 0);
  signal IO_STROBE : std_logic;

  signal ADDR : unsigned(15 downto 0);
  signal D, PD: unsigned(7 downto 0);
  signal DISK_DO, HDD_DO : unsigned(7 downto 0);
  signal PSG_4_DO, PSG_5_DO : unsigned(7 downto 0);
  signal cpu_we : std_logic;
  signal psg_4_irq_n, psg_4_nmi_n , psg_4_oe: std_logic;
  signal psg_5_irq_n, psg_5_nmi_n , psg_5_oe: std_logic;
  signal ssc_irq_n: std_logic;

  signal SSC_ROM_EN : std_logic;
  signal SSC_DO     : unsigned(7 downto 0);

  signal CLOCK_DO   : std_logic_vector(7 downto 0);
  signal CLOCK_OE   : std_logic;
  signal nsc_time_bcd : std_logic_vector(63 downto 0);
  signal nsc_time_en  : std_logic;

  signal MOUSE_4_DO:  unsigned(7 downto 0);
  signal MOUSE_4_OE: std_logic;
  signal mouse_4_irq_n: std_logic;
  signal MOUSE_5_DO:  unsigned(7 downto 0);
  signal MOUSE_5_OE: std_logic;
  signal mouse_5_irq_n: std_logic;
  
  signal we_ram : std_logic;
  signal VIDEO, HBL, VBL : std_logic;
  signal COLOR_LINE : std_logic;
  signal RUN_FILL_OK : std_logic;
  signal COLOR_LINE_CONTROL : std_logic;
  signal TEXT_MODE : std_logic;
  signal GAMEPORT : std_logic_vector(7 downto 0);

  signal K : unsigned(7 downto 0);
  signal read_key : std_logic;
  signal akd : std_logic;

  signal flash_clk : unsigned(22 downto 0) := (others => '0');
  signal power_on_reset : std_logic := '1';
  signal reset : std_logic;


  signal a_ram: unsigned(17 downto 0);
  
  signal psg_4_audio_l : unsigned(9 downto 0);
  signal psg_4_audio_r : unsigned(9 downto 0);

  signal psg_5_audio_l : unsigned(9 downto 0);
  signal psg_5_audio_r : unsigned(9 downto 0);

  
  signal audio       : unsigned(9 downto 0);
  -- 3x 10-bit sum needs 11 bits (765+765+512=2042); saturate instead of
  -- truncating. Single-MB usage is bit-identical to the old wrap.
  signal audio_sum_l : unsigned(10 downto 0);
  signal audio_sum_r : unsigned(10 downto 0);
  -- TODO item 3.2/3.3: box-average the $C030 speaker bit at 14.318 MHz into
  -- ~48 kHz samples (298 clocks = 20.8 us) so fast toggles average out
  -- instead of aliasing from point sampling. Duty maps to 0..512 (half-
  -- scale, 4x the old 0..128 level); the framework DC blocker centers it.
  signal spk_bit : std_logic := '0';
  signal spk_cnt : unsigned(8 downto 0) := (others => '0');
  signal spk_sum : unsigned(8 downto 0) := (others => '0');
  signal spk_avg : std_logic_vector(9 downto 0) := (others => '0');

  signal joyx       : std_logic;
  signal joyy       : std_logic;
  signal joy_key_press : std_logic;
  signal joy_key_code  : std_logic_vector(6 downto 0);
  signal pdl_strobe : std_logic;
  signal open_apple : std_logic;
  signal closed_apple : std_logic;
begin


  -- In the Apple ][, this was a 555 timer
  power_on : process(CLK_14M)
  begin
    if rising_edge(CLK_14M) then
      reset <= reset_warm or power_on_reset;

      if reset_cold = '1' or soft_reset ='1'then
        power_on_reset <= '1';
        flash_clk <= (others=>'0');
      else
		  if flash_clk(22) = '1' then
          power_on_reset <= '0';
			end if;
			 
        flash_clk <= flash_clk + 1;
      end if;
    end if;
  end process;		
  
  
  -- Paddle buttons
  -- GAMEPORT input bits:
  --  7    6    5    4    3   2   1    0
  -- pdl3 pdl2 pdl1 pdlCLOCK_OE0 pb3 pb2 pb1 casette
  GAMEPORT <=  "00" & joyy & joyx & "0" & (joy(5) or closed_apple)& (joy(4) or open_apple) & TAPE_IN;

  process(CLK_14M, pdl_strobe)
    variable cx, cy : integer range -100 to 5800 := 0;
  begin
    if rising_edge(CLK_14M) then
     CLK_2M_D <= CLK_2M;
     if CLK_2M_D = '0' and CLK_2M = '1' then
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
        cx := 2800+(22*to_integer(signed(joy_an(15 downto 8))));
        cy := 2800+(22*to_integer(signed(joy_an(7 downto 0)))); -- max 5650
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
    end if;
  end process;

  COLOR_LINE_CONTROL <= (COLOR_LINE or (TEXT_COLOR and not TEXT_MODE)) and not (SCREEN_MODE(1) or SCREEN_MODE(0));  -- Color or B&W mode

  -- Simulate power up on cold reset to go to the disk boot routine
  ram_we   <= we_ram when reset_cold = '0' else '1';
  ram_addr <= std_logic_vector(a_ram) when reset_cold = '0' else std_logic_vector(to_unsigned(1012,ram_addr'length)); -- $3F4
  ram_di   <= std_logic_vector(D) when reset_cold = '0' else "00000000";

  PD <= PSG_4_DO when psg_4_oe = '1'  else
        PSG_5_DO when psg_5_oe = '1'  else
        MOUSE_4_DO when MOUSE_4_OE = '1' else
        MOUSE_5_DO when MOUSE_5_OE = '1' else
        unsigned(CLOCK_DO) when CLOCK_OE = '1' else
        HDD_DO when IO_SELECT(7) = '1' or DEVICE_SELECT(7) = '1' else
        SSC_DO when IO_SELECT(2) = '1' or DEVICE_SELECT(2) = '1' or SSC_ROM_EN ='1' else 
        DISK_DO;

  core : entity work.apple2 port map (
    CLK_14M        => CLK_14M,
    CLK_2M         => CLK_2M,
    CPU_WAIT       => CPU_WAIT,
    PHASE_ZERO     => PHASE_ZERO,
    PHASE_ZERO_R   => PHASE_ZERO_R,
    PHASE_ZERO_F   => PHASE_ZERO_F,
    FLASH_CLK      => flash_clk(22),
    reset          => reset,
    cpu            => cpu_type,
    STALL          => cpu_stall,
    ADDR           => ADDR,
    ram_addr       => a_ram,
    D              => D,
    ram_do         => unsigned(ram_do),
    aux            => ram_aux,
    PD             => PD,
    CPU_WE         => cpu_we,
    IRQ_N          => psg_4_irq_n and psg_5_irq_n and ssc_irq_n and mouse_4_irq_n and mouse_5_irq_n,
    NMI_N          => psg_4_nmi_n and psg_5_nmi_n,
    ram_we         => we_ram,
    VIDEO          => VIDEO,
    PALMODE        => PALMODE,
    ROMSWITCH      => ROMSWITCH,
    COLOR_LINE     => COLOR_LINE,
    RUN_FILL_OK    => RUN_FILL_OK,
    TEXT_MODE      => TEXT_MODE,
    HBL            => HBL,
    VBL            => VBL,
    K              => K,
    read_key       => read_key,
    AKD            => akd,
    AN             => open,
    GAMEPORT       => GAMEPORT,
    PDL_strobe     => pdl_strobe,
    IO_SELECT      => IO_SELECT,
    DEVICE_SELECT  => DEVICE_SELECT,
    IO_STROBE      => IO_STROBE,

    ioctl_addr     => ioctl_addr,
    ioctl_data     => ioctl_data,
    ioctl_index    => ioctl_index,
    ioctl_download => ioctl_download,
    ioctl_wr       => ioctl_wr,
	 
    saturn_5_inslot=> saturn_5_inslot,
	 
    speaker        => spk_bit
    );

  tv : component vga_controller port map (
    CLK_14M    => CLK_14M,
    VIDEO      => VIDEO,
    COLOR_LINE => COLOR_LINE_CONTROL,
    SCREEN_MODE => SCREEN_MODE,
    COLOR_PALETTE => COLOR_PALETTE,
    GRAY_SEAM_FIX => GRAY_SEAM_FIX,
    SEAM_RUN_FILL => SEAM_RUN_FILL,
    SEAM_RUN_WIDE => SEAM_RUN_WIDE,
    RUN_FILL_OK   => RUN_FILL_OK,
    NTSC_VERTICAL_COMB => NTSC_VERTICAL_COMB,
    HBL        => HBL,
    VBL        => VBL,
    VGA_HS     => hsync,
    VGA_VS     => vsync,
    VGA_HBL    => hblank,
    VGA_VBL    => vblank,
    std_logic_vector(VGA_R) => r,
    std_logic_vector(VGA_G) => g,
    std_logic_vector(VGA_B) => b,
    -- for custom palette loader
    ioctl_addr     => ioctl_addr,
    ioctl_data     => ioctl_data,
    ioctl_wr       => ioctl_wr,
	 ioctl_index    => ioctl_index,
	 ioctl_download => ioctl_download,
	 ioctl_wait => ioctl_wait
    );

  -- Joy-to-key: map the digital joystick to Apple II keystrokes. Sits next
  -- to the keyboard (CLK_14M domain) and injects one-shot key presses
  -- independently of the OSK virtual path, so PS/2 and the raw joystick are
  -- both untouched. Runtime enable from the OSD (P3oB, "Joystick to keys").
  joy_to_key_inst : joy_to_key port map (
    clk            => CLK_14M,
    reset          => reset_cold,
    enable         => JOY_TO_KEY_EN,
    joy            => joy,
    ioctl_download => ioctl_download,
    ioctl_wr       => ioctl_wr,
    ioctl_addr     => ioctl_addr,
    ioctl_data     => ioctl_data,
    ioctl_index    => ioctl_index,
    joy_key_press  => joy_key_press,
    joy_key_code   => joy_key_code
  );

  kbd : keyboard port map (
    PS2_Key  => PS2_Key,
    virtual_active => virtual_keyboard_active,
    virtual_event => virtual_keyboard_event,
    virtual_pressed => virtual_keyboard_pressed,
    virtual_code => virtual_keyboard_code,
    virtual_control => virtual_control,
    virtual_open_apple => virtual_open_apple,
    virtual_closed_apple => virtual_closed_apple,
    CLK_14M  => CLK_14M,
	 reset    => reset_cold, -- use reset_cold, not reset so we keep the
	                         -- keyboard state machine running for key up 
									 -- events during / after reset
    reads    => read_key,
    K        => K,
    akd      => akd,
    open_apple => open_apple,
    closed_apple => closed_apple,
    soft_reset => soft_reset,
    video_toggle => video_switch,
	palette_toggle => palette_switch,
    joy_key_code  => joy_key_code,
    joy_key_press => joy_key_press
    );

	 
  DISK_ACT <= not (D1_ACTIVE or D2_ACTIVE);

  disk : component disk_ii port map (
    CLK_14M        => CLK_14M,
    CLK_2M         => CLK_2M,
    PHASE_ZERO     => PHASE_ZERO,
    IO_SELECT      => IO_SELECT(6),
    DEVICE_SELECT  => DEVICE_SELECT(6),
    RESET          => reset,
    DISK_READY     => DISK_READY,  -- TODO
    A              => ADDR,
    D_IN           => D,
    D_OUT          => DISK_DO,
    D1_ACTIVE      => D1_ACTIVE, 
    D2_ACTIVE      => D2_ACTIVE,
    D1_MOTOR_ON    => D1_MOTOR_ON,
    D2_MOTOR_ON    => D2_MOTOR_ON,
    D1_IO_ACTIVE   => D1_IO_ACTIVE,
    D2_IO_ACTIVE   => D2_IO_ACTIVE,
    D1_STEP_ACTIVE => D1_STEP_ACTIVE,
    D2_STEP_ACTIVE => D2_STEP_ACTIVE,
    D1_TRACK_ZERO_STEP => D1_TRACK_ZERO_STEP,
    D2_TRACK_ZERO_STEP => D2_TRACK_ZERO_STEP,
    D1_WP          => D1_WP,
    D2_WP          => D2_WP, 
	 
    -- track buffer interface for disk 1  -- TODO
    TRACK1         => TRACK1,
    TRACK1_ADDR    => TRACK1_ADDR,
    TRACK1_DO      => TRACK1_DO,
    TRACK1_DI      => TRACK1_DI,
    TRACK1_WE      => TRACK1_WE,
    TRACK1_BUSY    => TRACK1_BUSY,
    -- track buffer interface for disk 2  -- TODO
    TRACK2         => TRACK2,
    TRACK2_ADDR    => TRACK2_ADDR,
    TRACK2_DO      => TRACK2_DO,
    TRACK2_DI      => TRACK2_DI,
    TRACK2_WE      => TRACK2_WE,
    TRACK2_BUSY    => TRACK2_BUSY
    );
	 
  hdd : entity work.hdd port map (
    CLK_14M        => CLK_14M,
    IO_SELECT      => IO_SELECT(7),
    DEVICE_SELECT  => DEVICE_SELECT(7),
    RESET          => reset,
    A              => ADDR,
    RD             => not cpu_we,
    D_IN           => D,
    D_OUT          => HDD_DO,
    sector         => HDD_SECTOR,
    hdd_read       => HDD_READ,
    hdd_write      => HDD_WRITE,
    hdd_mounted    => HDD_MOUNTED,
    hdd_protect    => HDD_PROTECT,
    ram_addr       => HDD_RAM_ADDR,
    ram_di         => HDD_RAM_DI,
    ram_do         => HDD_RAM_DO,
    ram_we         => HDD_RAM_WE
    );

  mb_4 : component mockingboard
    port map (
      CLK_14M    => CLK_14M,
      PHASE_ZERO => PHASE_ZERO,
      PHASE_ZERO_R => PHASE_ZERO_R,
      PHASE_ZERO_F => PHASE_ZERO_F,
      I_RESET_L => not reset,
      I_ENA_H   => mb_4_inslot,

      I_ADDR    => std_logic_vector(ADDR)(7 downto 0),
      I_DATA    => std_logic_vector(D),
      unsigned(O_DATA) => PSG_4_DO,
      I_RW_L    => not cpu_we,
      I_IOSEL_L => not IO_SELECT(4) or NOT mb_4_inslot,
		OE        => psg_4_oe,
		
      O_IRQ_L   => psg_4_irq_n,
      O_NMI_L   => psg_4_nmi_n,
      unsigned(O_AUDIO_L) => psg_4_audio_l,
      unsigned(O_AUDIO_R) => psg_4_audio_r
      );
  mb_5 : component mockingboard
    port map (
      CLK_14M    => CLK_14M,
      PHASE_ZERO => PHASE_ZERO,
      PHASE_ZERO_R => PHASE_ZERO_R,
      PHASE_ZERO_F => PHASE_ZERO_F,
      I_RESET_L => not reset,
      I_ENA_H   => mb_5_inslot,

      I_ADDR    => std_logic_vector(ADDR)(7 downto 0),
      I_DATA    => std_logic_vector(D),
      unsigned(O_DATA) => PSG_5_DO,
      I_RW_L    => not cpu_we,
      I_IOSEL_L => not IO_SELECT(5) or NOT mb_5_inslot,
		OE        => psg_5_oe,
		
      O_IRQ_L   => psg_5_irq_n,
      O_NMI_L   => psg_5_nmi_n,
      unsigned(O_AUDIO_L) => psg_5_audio_l,
      unsigned(O_AUDIO_R) => psg_5_audio_r
      );

   ssc : component superserial
     port map (
	CLK_50M 	=> CLK_50M,
	CLK_14M     	=> CLK_14M,
	CLK_2M      	=> CLK_2M,
	PH_2        	=> PHASE_ZERO,
	IO_SELECT_N 	=> not IO_SELECT(2),
	DEVICE_SELECT_N => not DEVICE_SELECT(2),
	IO_STROBE_N  	=> NOT IO_STROBE,
	ADDRESS     	=> std_logic_vector(ADDR),
	RW_N        	=> not cpu_we,
	RESET       	=> reset,
	DATA_IN     	=> std_logic_vector(D),
	unsigned(DATA_OUT) => SSC_DO,
	ROM_EN 		=> SSC_ROM_EN,
	UART_CTS 	=> UART_CTS,
	UART_RTS 	=> UART_RTS,
	UART_RXD 	=> UART_RXD,
	UART_TXD 	=> UART_TXD,
	UART_DTR 	=> UART_DTR,
	UART_DSR 	=> UART_DSR,
	IRQ_N 		=> ssc_irq_n
	);

	


 mouse_4 : entity work.applemouse 
 port map (
    CLK_14M        => CLK_14M,
    CLK_2M         => CLK_2M,
    PHASE_ZERO     => PHASE_ZERO,
    IO_SELECT      => IO_SELECT(4) and mouse_4_inslot,
    IO_STROBE      => IO_STROBE,
    DEVICE_SELECT  => DEVICE_SELECT(4) and mouse_4_inslot,
    RESET          => reset,
    A              => ADDR,
    RNW            => not cpu_we,
    D_IN           => D,
    D_OUT          => MOUSE_4_DO,
    OE             => MOUSE_4_OE,
    IRQ_N          => MOUSE_4_IRQ_N,

    STROBE         => mouse_strobe,
    X              => mouse_x,
    Y              => mouse_y,
    BUTTON         => mouse_button
  );
 mouse_5 : entity work.applemouse 
 port map (
    CLK_14M        => CLK_14M,
    CLK_2M         => CLK_2M,
    PHASE_ZERO     => PHASE_ZERO,
    IO_SELECT      => IO_SELECT(5) and mouse_5_inslot,
    IO_STROBE      => IO_STROBE,
    DEVICE_SELECT  => DEVICE_SELECT(5) and mouse_5_inslot,
    RESET          => reset,
    A              => ADDR,
    RNW            => not cpu_we,
    D_IN           => D,
    D_OUT          => MOUSE_5_DO,
    OE             => MOUSE_5_OE,
    IRQ_N          => MOUSE_5_IRQ_N,

    STROBE         => mouse_strobe,
    X              => mouse_x,
    Y              => mouse_y,
    BUTTON         => mouse_button
  );
	
	
	-- No Slot Clock (NSC): DS1216E-style software time interface hiding under
	-- each slot's ROM page at offsets $00-$07 (replaces the old clock_card;
	-- see NSC_PORT_NOTES.md in Apple-II-Verilog_MiSTer). nsc_ticker supplies
	-- BCD time/date (HPS RTC reload + free-running calendar); no_slot_clock
	-- (BSD port of jtflanagan/AppleTini's module) implements the 64-write
	-- unlock / 64-bit readout protocol on the bus.
	nsc_tkr : component nsc_ticker
	port map (
	  clk      => CLK_14M,
	  rst      => reset,
	  rtc      => RTC,
	  time_bcd => nsc_time_bcd,
	  time_en  => nsc_time_en
	  );

	-- Reachable from any slot 1-6 wide window ($C1xx-$C7xx; $C3xx only when
	-- C3ROM is set) or the $C8xx-$CFFF slot-ROM window (IO_STROBE decode).
	-- The stock driver probes slots 3,1,2,4-7 then internal, so with the
	-- default C3ROM=0 it finds the NSC at $C1xx. The module itself restricts
	-- to offsets $00-$07.
	nsc : component no_slot_clock
	port map (
	  clk           => CLK_14M,
	  rst           => reset,
	  strobe        => PHASE_ZERO_R,
	  addr          => std_logic_vector(ADDR),
	  rw            => not cpu_we,
	  slot_sel      => IO_SELECT(6) or IO_SELECT(5) or IO_SELECT(4) or
	                   IO_SELECT(3) or IO_SELECT(2) or IO_SELECT(1) or
	                   IO_STROBE,
	  input_time    => "00000000000000000000" & nsc_time_bcd,
	  input_time_en => nsc_time_en,
	  wr_data       => CLOCK_DO,
	  wr_data_en    => CLOCK_OE
	  );



  speaker_average: process (CLK_14M) is
    variable v_sum  : unsigned(8 downto 0);
    variable v_prod : unsigned(17 downto 0);
    variable v_avg  : unsigned(17 downto 0);
  begin
    if rising_edge(CLK_14M) then
      v_sum := spk_sum;
      if spk_bit = '1' then
        v_sum := v_sum + 1;
      end if;
      if spk_cnt = 297 then
        v_prod := v_sum & "000000000";   -- *512, max 298*512=152576 < 2^18
        v_avg  := v_prod / 298;          -- max 512
        spk_avg <= std_logic_vector(v_avg(9 downto 0));
        spk_sum <= (others => '0');
        spk_cnt <= (others => '0');
      else
        spk_sum <= v_sum;
        spk_cnt <= spk_cnt + 1;
      end if;
    end if;
  end process speaker_average;

  audio <= unsigned(spk_avg);
  audio_sum_l <= ("0" & psg_4_audio_l) + ("0" & psg_5_audio_l) + ("0" & audio);
  audio_sum_r <= ("0" & psg_4_audio_r) + ("0" & psg_5_audio_r) + ("0" & audio);
  AUDIO_L <= (others => '1') when audio_sum_l(10) = '1' else std_logic_vector(audio_sum_l(9 downto 0));
  AUDIO_R <= (others => '1') when audio_sum_r(10) = '1' else std_logic_vector(audio_sum_r(9 downto 0));

end arch;
