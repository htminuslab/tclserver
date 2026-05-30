--
-- VHDL Architecture UART_TXT.uart_top.symbol
--
-- Created:
--          by - user.group (host.domain)
--          at - 19:09:51 4 Feb 2002
--
-- Siemens HDL Designer(TM)
--

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;

ENTITY uart_top IS
   PORT( 
      -- 3-bit address bus
      addr     : IN     std_logic_vector (2 DOWNTO 0);
      clk      : IN     std_logic;             -- 10 MHz clock
      cs       : IN     std_logic;             -- chip select
      -- 8-bit data in bus from cpu
      datin    : IN     std_logic_vector (7 DOWNTO 0);
      nrw      : IN     std_logic;             -- read(0), write(1)
      rst      : IN     std_logic;             -- reset(0)
      sin      : IN     std_logic;             -- serial input
      -- 8-bit data out bus to cpu
      datout   : OUT    std_logic_vector (7 DOWNTO 0);
      int      : OUT    std_logic;             -- interrupt (1)
      sout     : OUT    std_logic              -- serial output
   );

END uart_top ;

LIBRARY UART_TXT;

ARCHITECTURE rtl OF uart_top IS

   -- Internal signal declarations
   SIGNAL clear_flags     : std_logic;
   SIGNAL clk_div_en      : std_logic;
   SIGNAL clr_int_en      : std_logic;
   SIGNAL div_data        : std_logic_vector(7 DOWNTO 0);
   SIGNAL enable_rcv_clk  : std_logic;
   SIGNAL enable_write    : std_logic;
   SIGNAL enable_xmit_clk : std_logic;
   SIGNAL sample          : std_logic;
   SIGNAL ser_if_data     : std_logic_vector(7 DOWNTO 0);
   SIGNAL ser_if_select   : std_logic_vector(1 DOWNTO 0);
   SIGNAL start_xmit      : std_logic;
   SIGNAL xmitdt_en       : std_logic;

   -- Component Declarations
   COMPONENT address_decode
   PORT (
      addr          : IN     std_logic_vector (2 DOWNTO 0);
      clk_div_en    : OUT    std_logic ;
      clr_int_en    : OUT    std_logic ;
      ser_if_select : OUT    std_logic_vector (1 DOWNTO 0);
      xmitdt_en     : OUT    std_logic 
   );
   END COMPONENT;
   COMPONENT clock_divider
   PORT (
      addr            : IN     std_logic ;
      clk             : IN     std_logic ;
      clk_div_en      : IN     std_logic ;
      datin         : IN     std_logic_vector (7 DOWNTO 0);
      enable_rcv_clk  : IN     std_logic ;
      enable_write    : IN     std_logic ;
      enable_xmit_clk : IN     std_logic ;
      rst             : IN     std_logic ;
      div_data        : OUT    std_logic_vector (7 DOWNTO 0);
      sample          : OUT    std_logic 
   );
   END COMPONENT;
   COMPONENT cpu_interface
   PORT (
      clk          : IN     std_logic ;
      clk_div_en   : IN     std_logic ;
      clr_int_en   : IN     std_logic ;
      cs           : IN     std_logic ;
      div_data     : IN     std_logic_vector (7 DOWNTO 0);
      nrw          : IN     std_logic ;
      rst          : IN     std_logic ;
      ser_if_data  : IN     std_logic_vector (7 DOWNTO 0);
      xmitdt_en    : IN     std_logic ;
      clear_flags  : OUT    std_logic ;
      datout     : OUT    std_logic_vector (7 DOWNTO 0);
      enable_write : OUT    std_logic ;
      start_xmit   : OUT    std_logic 
   );
   END COMPONENT;
   COMPONENT serial_interface
   PORT (
      clear_flags     : IN     std_logic ;
      clk             : IN     std_logic ;
      datin         : IN     std_logic_vector (7 DOWNTO 0);
      enable_write    : IN     std_logic ;
      rst             : IN     std_logic ;
      sample          : IN     std_logic ;
      ser_if_select   : IN     std_logic_vector (1 DOWNTO 0);
      sin             : IN     std_logic ;
      start_xmit      : IN     std_logic ;
      xmitdt_en       : IN     std_logic ;
      enable_rcv_clk  : OUT    std_logic ;
      enable_xmit_clk : OUT    std_logic ;
      int             : OUT    std_logic ;
      ser_if_data     : OUT    std_logic_vector (7 DOWNTO 0);
      sout            : OUT    std_logic 
   );
   END COMPONENT;

   -- Optional embedded configurations
   -- pragma synthesis_off
   FOR ALL : address_decode USE ENTITY UART_TXT.address_decode;
   FOR ALL : cpu_interface USE ENTITY UART_TXT.cpu_interface;
   FOR ALL : serial_interface USE ENTITY UART_TXT.serial_interface;
   -- pragma synthesis_on


BEGIN
   -- Instance port mappings.
   U_3 : address_decode
      PORT MAP (
         addr          => addr,
         clk_div_en    => clk_div_en,
         clr_int_en    => clr_int_en,
         ser_if_select => ser_if_select,
         xmitdt_en     => xmitdt_en
      );
   U_2 : clock_divider
      PORT MAP (
         addr            => addr(0),
         clk             => clk,
         clk_div_en      => clk_div_en,
         datin         => datin,
         enable_rcv_clk  => enable_rcv_clk,
         enable_write    => enable_write,
         enable_xmit_clk => enable_xmit_clk,
         rst             => rst,
         div_data        => div_data,
         sample          => sample
      );
   U_1 : cpu_interface
      PORT MAP (
         clk          => clk,
         clk_div_en   => clk_div_en,
         clr_int_en   => clr_int_en,
         cs           => cs,
         div_data     => div_data,
         nrw          => nrw,
         rst          => rst,
         ser_if_data  => ser_if_data,
         xmitdt_en    => xmitdt_en,
         clear_flags  => clear_flags,
         datout     => datout,
         enable_write => enable_write,
         start_xmit   => start_xmit
      );
   U_4 : serial_interface
      PORT MAP (
         clear_flags     => clear_flags,
         clk             => clk,
         datin         => datin,
         enable_write    => enable_write,
         rst             => rst,
         sample          => sample,
         ser_if_select   => ser_if_select,
         sin             => sin,
         start_xmit      => start_xmit,
         xmitdt_en       => xmitdt_en,
         enable_rcv_clk  => enable_rcv_clk,
         enable_xmit_clk => enable_xmit_clk,
         int             => int,
         ser_if_data     => ser_if_data,
         sout            => sout
      );
      
END rtl;

