--
-- VHDL Architecture UART_TXT.cpu_interface.symbol
--
-- Created:
--          by - user.group (host.domain)
--          at - 19:05:45 4 Feb 2002
--
-- Siemens HDL Designer(TM)
--

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;

ENTITY cpu_interface IS
   PORT( 
      clk          : IN     std_logic;
      clk_div_en   : IN     std_logic;
      clr_int_en   : IN     std_logic;
      cs           : IN     std_logic;
      div_data     : IN     std_logic_vector (7 DOWNTO 0);
      nrw          : IN     std_logic;
      rst          : IN     std_logic;
      ser_if_data  : IN     std_logic_vector (7 DOWNTO 0);
      xmitdt_en    : IN     std_logic;
      clear_flags  : OUT    std_logic;
      datout       : OUT    std_logic_vector (7 DOWNTO 0);
      enable_write : OUT    std_logic;
      start_xmit   : OUT    std_logic
   );

END cpu_interface ;

ARCHITECTURE rtl OF cpu_interface IS

   -- Component Declarations
   COMPONENT control_operation
   PORT (
      clk          : IN     std_logic ;
      clr_int_en   : IN     std_logic ;
      cs           : IN     std_logic ;
      nrw          : IN     std_logic ;
      rst          : IN     std_logic ;
      xmitdt_en    : IN     std_logic ;
      clear_flags  : OUT    std_logic ;
      enable_write : OUT    std_logic ;
      start_xmit   : OUT    std_logic 
   );
   END COMPONENT;

BEGIN
   -- Architecture concurrent statements
   datout <= div_data WHEN clk_div_en = '1' ELSE
                      ser_if_data;

   -- Instance port mappings.
   U_0 : control_operation
      PORT MAP (
         clk          => clk,
         clr_int_en   => clr_int_en,
         cs           => cs,
         nrw          => nrw,
         rst          => rst,
         xmitdt_en    => xmitdt_en,
         clear_flags  => clear_flags,
         enable_write => enable_write,
         start_xmit   => start_xmit
      );

END rtl;

