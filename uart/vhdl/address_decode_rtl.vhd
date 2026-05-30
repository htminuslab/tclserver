--
-- VHDL Architecture UART_TXT.address_decode.symbol
--
-- Created:
--          by - user.group (host.domain)
--          at - 19:01:34 4 Feb 2002
--
-- Siemens HDL Designer(TM)
--

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;

ENTITY address_decode IS
   PORT( 
      addr          : IN     std_logic_vector (2 DOWNTO 0);
      clk_div_en    : OUT    std_logic;
      clr_int_en    : OUT    std_logic;
      ser_if_select : OUT    std_logic_vector (1 DOWNTO 0);
      xmitdt_en     : OUT    std_logic
   );

END address_decode ;

ARCHITECTURE rtl OF address_decode IS
BEGIN

   -----------------------------
   decode_proc: PROCESS(addr)
   -----------------------------
   BEGIN

      -- Defaults
      clk_div_en <= '0';
      xmitdt_en <= '0';
      clr_int_en <= '0';
      ser_if_select <= "11";

      CASE addr IS
      WHEN "000" =>
         clk_div_en <= '1';
      WHEN "001" =>
         clk_div_en <= '1';
      WHEN "100" =>
         xmitdt_en <= '1';
         ser_if_select <= addr(1 downto 0);
      WHEN "101" =>
         ser_if_select <= addr(1 downto 0);
      WHEN "110" =>
         ser_if_select <= addr(1 downto 0);
      WHEN "111" =>
         clr_int_en <= '1';
      WHEN OTHERS =>
         clk_div_en <= '0';
         xmitdt_en <= '0';
         ser_if_select <= "11";
         clr_int_en <= '0';
      END CASE;

   END PROCESS decode_proc;
   
END rtl;

