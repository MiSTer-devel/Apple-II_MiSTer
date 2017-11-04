--
-- Mockingboard clone for the Apple II
-- Model A: two AY-3-8913 chips for six audio channels
--
-- Top file by W. Soltys <wsoltys@gmail.com>
-- 
-- loosely based on:
-- http://www.downloads.reactivemicro.com/Public/Apple%20II%20Items/Hardware/Mockingboard_v1/Mockingboard-v1a-Docs.pdf
-- http://www.applelogic.org/CarteBlancheIIProj6.html
--

library ieee ;
  use ieee.std_logic_1164.all ;
  use ieee.std_logic_unsigned.all;
  use ieee.numeric_std.all;
  
  
entity MOCKINGBOARD is
  port (
  
    I_ADDR            : in std_logic_vector(7 downto 0);
    I_DATA            : in std_logic_vector(7 downto 0);
    O_DATA            : out std_logic_vector(7 downto 0);
    
    I_RW_L            : in std_logic;
    O_IRQ_L           : out std_logic;
    I_IOSEL_L         : in std_logic;
    I_RESET_L         : in std_logic;
    I_ENA_H           : in std_logic;     
    
    O_AUDIO_L         : out std_logic_vector(7 downto 0);
    O_AUDIO_R         : out std_logic_vector(7 downto 0);
    CLK_VIA           : in std_logic;
    CLK_PSG           : in std_logic;
    I_P2_H            : in std_logic
    );
 end;
 
 
 architecture RTL of MOCKINGBOARD is
 
  signal o_pb_l           : std_logic_vector(7 downto 0);
  signal o_pb_r           : std_logic_vector(7 downto 0);
  
  signal i_psg_r          : std_logic_vector(7 downto 0);
  signal i_psg_l          : std_logic_vector(7 downto 0);
  
  signal o_data_l          : std_logic_vector(7 downto 0);
  signal o_data_r          : std_logic_vector(7 downto 0);
  
  signal lvia_read        : std_logic;
  signal rvia_read        : std_logic;
  
  signal lirq_l           : std_logic;
  signal rirq_l           : std_logic;

  
begin

  O_DATA <= o_data_l when lvia_read = '1' else o_data_r when rvia_read = '1' else (others=>'Z');
  
  lvia_read <= I_RW_L and not I_ADDR(7);
  rvia_read <= I_RW_L and I_ADDR(7);
  
  O_IRQ_L <= lirq_l and rirq_l;

-- Left Channel Combo

  m6522_left : work.M6522
    port map (
      I_RS        => I_ADDR(3 downto 0),
      I_DATA      => I_DATA,
      O_DATA      => o_data_l,
      O_DATA_OE_L => open,
  
      I_RW_L      => I_RW_L,
      I_CS1       => not I_ADDR(7),
      I_CS2_L     => I_IOSEL_L,
  
      O_IRQ_L     => lirq_l,
      -- port a
      I_CA1       => '0',
      I_CA2       => '0',
      O_CA2       => open,
      O_CA2_OE_L  => open,
  
      I_PA        => (others => '0'),
      O_PA        => i_psg_l,
      O_PA_OE_L   => open,
  
      -- port b
      I_CB1       => '0',
      O_CB1       => open,
      O_CB1_OE_L  => open,
  
      I_CB2       => '0',
      O_CB2       => open,
      O_CB2_OE_L  => open,
  
      I_PB        => (others => '0'),
      O_PB        => o_pb_l,
      O_PB_OE_L   => open,
  
      I_P2_H      => I_P2_H,
      RESET_L     => I_RESET_L,
      ENA_4       => '1',
      CLK         => CLK_VIA and I_ENA_H
      );
      
      
  psg_left : work.YM2149
    port map (
      -- data bus
      I_DA        => i_psg_l,
      O_DA        => open,
      O_DA_OE_L   => open,
      -- control
      I_A9_L      => '0', -- /A9 pulled down internally
      I_A8        => '1',
      I_BDIR      => o_pb_l(1),
      I_BC2       => '1',
      I_BC1       => o_pb_l(0),
      I_SEL_L     => '1', -- /SEL is high for AY-3-8912 compatibility
    
      O_AUDIO     => O_AUDIO_L,
      -- port a
      I_IOA       => (others => '0'), -- port A unused
      O_IOA       => open,
      O_IOA_OE_L  => open,
      -- port b
      I_IOB       => (others => '0'), -- port B unused
      O_IOB       => open,
      O_IOB_OE_L  => open,
      --
      ENA         => '1',
      RESET_L     => o_pb_l(2),
      CLK         => CLK_PSG and I_ENA_H
      );


-- Right Channel Combo

  m6522_right : work.M6522
    port map (
      I_RS        => I_ADDR(3 downto 0),
      I_DATA      => I_DATA,
      O_DATA      => o_data_r,
      O_DATA_OE_L => open,
  
      I_RW_L      => I_RW_L,
      I_CS1       => I_ADDR(7),
      I_CS2_L     => I_IOSEL_L,
  
      O_IRQ_L     => rirq_l,
      -- port a
      I_CA1       => '0',
      I_CA2       => '0',
      O_CA2       => open,
      O_CA2_OE_L  => open,
  
      I_PA        => (others => '0'),
      O_PA        => i_psg_r,
      O_PA_OE_L   => open,
  
      -- port b
      I_CB1       => '0',
      O_CB1       => open,
      O_CB1_OE_L  => open,
  
      I_CB2       => '0',
      O_CB2       => open,
      O_CB2_OE_L  => open,
  
      I_PB        => (others => '0'),
      O_PB        => o_pb_r,
      O_PB_OE_L   => open,
  
      I_P2_H      => I_P2_H,
      RESET_L     => I_RESET_L,
      ENA_4       => '1',
      CLK         => CLK_VIA and I_ENA_H
      );
      
      
  psg_right : work.YM2149
    port map (
      -- data bus
      I_DA        => i_psg_r,
      O_DA        => open,
      O_DA_OE_L   => open,
      -- control
      I_A9_L      => '0', -- /A9 pulled down internally
      I_A8        => '1',
      I_BDIR      => o_pb_r(1),
      I_BC2       => '1',
      I_BC1       => o_pb_r(0),
      I_SEL_L     => '1', -- /SEL is high for AY-3-8912 compatibility
    
      O_AUDIO     => O_AUDIO_R,
      -- port a
      I_IOA       => (others => '0'), -- port A unused
      O_IOA       => open,
      O_IOA_OE_L  => open,
      -- port b
      I_IOB       => (others => '0'), -- port B unused
      O_IOB       => open,
      O_IOB_OE_L  => open,
      --
      ENA         => '1',
      RESET_L     => o_pb_r(2),
      CLK         => CLK_PSG and I_ENA_H
      );

end architecture RTL;