-------------------------------------------------------------------------------
--
-- Apple Mouse Card
--
-- (c)2025 Gyorgy Szombathelyi
--
-- jt6805 CPU by Jose Tejada
-- https://github.com/jotego/jtcores/tree/master/modules/jt680x
--
-- pia6821.vhd
-- Author : John E. Kent
--
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity applemouse is
  port (
    CLK_14M        : in  std_logic;
    CLK_2M         : in  std_logic;
    PHASE_ZERO     : in  std_logic;
    IO_SELECT      : in  std_logic;             -- e.g., C700 - C7FF ROM
    IO_STROBE      : in  std_logic;             -- e.g., C800 - CFFF I/O locations
    DEVICE_SELECT  : in  std_logic;
    RESET          : in  std_logic;
    A              : in  unsigned(15 downto 0);
    D_IN           : in  unsigned( 7 downto 0); -- From 6502
    D_OUT          : out unsigned( 7 downto 0); -- To 6502
    RNW            : in  std_logic;
    OE             : out std_logic;
    IRQ_N          : out std_logic;

    -- MOUSE
    STROBE         : in  std_logic;
    X              : in  signed(8 downto 0);
    Y              : in  signed(8 downto 0);
    BUTTON         : in  std_logic
    );
end applemouse;

architecture rtl of applemouse is

  component jtframe_6805mcu
  generic
  (
    ROMW   : integer := 11
  );
  port
  (
    rst    : in  std_logic;
    clk    : in  std_logic;
    cen    : in  std_logic;
    wr     : out std_logic;
    addr   : out std_logic_vector(12 downto 0);
    dout   : out std_logic_vector(7 downto 0);
    irq    : in  std_logic;
    timer  : in  std_logic;

    pa_in  : in  std_logic_vector(7 downto 0);
    pa_out : out std_logic_vector(7 downto 0);
    pb_in  : in  std_logic_vector(7 downto 0);
    pb_out : out std_logic_vector(7 downto 0);
    pc_in  : in  std_logic_vector(3 downto 0);
    pc_out : out std_logic_vector(3 downto 0);

    rom_addr : out std_logic_vector(ROMW-1 downto 0);
    rom_data : in  std_logic_vector(7 downto 0);
    rom_cs   : out std_logic
  );
  end component jtframe_6805mcu;

  signal rom_addr : std_logic_vector(10 downto 0);
  signal rom_dout : std_logic_vector(7 downto 0);

  signal mcu_rom_addr : std_logic_vector(10 downto 0);
  signal mcu_rom_dout : std_logic_vector(7 downto 0);

  signal pia_dout   : std_logic_vector(7 downto 0);
  signal pia_pa_in  : std_logic_vector(7 downto 0);
  signal pia_pa_out : std_logic_vector(7 downto 0);
  signal pia_pb_in  : std_logic_vector(7 downto 0);
  signal pia_pb_out : std_logic_vector(7 downto 0);

  signal mcu_pa_in  : std_logic_vector(7 downto 0);
  signal mcu_pa_out : std_logic_vector(7 downto 0);
  signal mcu_pb_in  : std_logic_vector(7 downto 0);
  signal mcu_pb_out : std_logic_vector(7 downto 0);
  signal mcu_pc_in  : std_logic_vector(3 downto 0);
  signal mcu_pc_out : std_logic_vector(3 downto 0);

  signal clk_2m_d   : std_logic;
  signal clk_2en    : std_logic;

  signal pressed    : std_logic;
  signal mx         : signed(8 downto 0);
  signal my         : signed(8 downto 0);
  signal enc_x      : std_logic_vector(1 downto 0);
  signal enc_y      : std_logic_vector(1 downto 0);
  signal div_cnt    : unsigned(10 downto 0);

begin

  process(CLK_14M) begin
    if rising_edge(CLK_14M) then
      if RESET = '1' then
        pressed <= '0';
        mx <= (others => '0');
        my <= (others => '0');
        enc_x <= (others => '0');
        enc_y <= (others => '0');
        div_cnt <= (others => '0');
      else
        div_cnt <= div_cnt + 1;
        if div_cnt = 0 then

          if mx(8) = '1' then
            mx <= mx + 1;
            enc_x <= enc_x(0) & not enc_x(1);
            if enc_x(0) = '0' and enc_x(1) = '0' then -- ^x(0)
              mcu_pb_in(0) <= '0';
            end if;
            mcu_pb_in(1) <= not enc_x(1);
          elsif mx /= 0 then
            mx <= mx - 1;
            enc_x <= not enc_x(0) & enc_x(1);
            if enc_x(0) = '0' and enc_x(1) = '1' then -- ^x(0)
              mcu_pb_in(0) <= '1';
            end if;
            mcu_pb_in(1) <= enc_x(1);
          end if;

          if my(8) = '1' then
            my <= my + 1;
            enc_y <= enc_y(0) & not enc_y(1);
            if enc_y(0) = '0' and enc_y(1) = '0' then -- ^y(0)
              mcu_pb_in(2) <= '1';
            end if;
            mcu_pb_in(3) <= not enc_y(1);
          elsif my /= 0 then
            my <= my - 1;
            enc_y <= not enc_y(0) & enc_y(1);
            if enc_y(0) = '0' and enc_y(1) = '1' then -- ^y(0)
              mcu_pb_in(2) <= '0';
            end if;
            mcu_pb_in(3) <= enc_y(1);
          end if;

        end if;

        if STROBE = '1' then
          pressed <= BUTTON;
          mx <= X;
          my <= Y;
        end if;
      end if;
    end if;
  end process;

  D_OUT <= unsigned(pia_dout) when DEVICE_SELECT = '1' else unsigned(rom_dout);
  OE <= IO_SELECT or DEVICE_SELECT;
  IRQ_N <= mcu_pb_out(6);

  pia : entity work.pia6821 port map (
    clk      => CLK_14M,
    rst      => RESET,
    cs       => DEVICE_SELECT,
    rw       => RNW,
    addr     => std_logic_vector(A)(1 downto 0),
    data_in  => std_logic_vector(D_IN),
    data_out => pia_dout,
    irqa     => open,
    irqb     => open,
    pa_i     => pia_pa_in,
    pa_o     => pia_pa_out,
    pa_oe    => open,
    ca1      => '1',
    ca2_i    => '1',
    ca2_o    => open,
    ca2_oe   => open,
    pb_i     => pia_pb_in,
    pb_o     => pia_pb_out,
    pb_oe    => open,
    cb1      => '1',
    cb2_i    => '1',
    cb2_o    => open,
    cb2_oe   => open
  );

  process(CLK_14M) begin
    if rising_edge(CLK_14M) then
      clk_2m_d <= CLK_2M;
      if CLK_2M = '1' and clk_2m_d = '0' then
        clk_2en <= '1';
      else
        clk_2en <= '0';
      end if;
    end if;
  end process;

  mcu : jtframe_6805mcu port map (
    rst      => RESET,
    clk      => CLK_14M,
    cen      => clk_2en,
    wr       => open,
    addr     => open,
    dout     => open,
    irq      => '0',
    timer    => '1',

    pa_in    => mcu_pa_in,
    pa_out   => mcu_pa_out,
    pb_in    => mcu_pb_in,
    pb_out   => mcu_pb_out,
    pc_in    => mcu_pc_in,
    pc_out   => mcu_pc_out,

    rom_addr => mcu_rom_addr,
    rom_data => mcu_rom_dout,
    rom_cs   => open
  );

  mcu_pa_in <= pia_pa_out;
  pia_pa_in <= mcu_pa_out;

  mcu_pc_in <= pia_pb_out(7 downto 4);
  pia_pb_in(7 downto 4) <= mcu_pc_out;
  pia_pb_in(0) <= D_IN(0);

  mcu_pb_in(7) <= not pressed;
  mcu_pb_in(5 downto 4) <= "11";

  -- 341-0270-C
  rom_addr <= pia_pb_out(3 downto 1) & std_logic_vector(A)(7 downto 0);
  rom : entity work.applemouse_rom port map (
    addr => rom_addr,
    clk  => CLK_14M,
    data => rom_dout);

  -- 341-0269
  mcu_rom : entity work.applemouse_mcu_rom port map (
    addr => mcu_rom_addr,
    clk  => CLK_14M,
    data => mcu_rom_dout);

end rtl;
