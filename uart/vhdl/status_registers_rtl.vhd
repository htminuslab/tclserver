--
-- VHDL Architecture UART_TXT.status_registers.symbol
--
-- Created:
--          by - user.group (host.domain)
--          at - 19:07:43 4 Feb 2002
--
-- Siemens HDL Designer(TM)
--

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;
USE ieee.numeric_std.all;

ENTITY status_registers IS
   PORT( 
      clear_flags   : IN     std_logic;
      clk           : IN     std_logic;
      done_rcving   : IN     std_logic;
      done_xmitting : IN     std_logic;
      rcving        : IN     std_logic;
      rst           : IN     std_logic;
      xmitting      : IN     std_logic;
      int           : OUT    std_logic;
      status        : OUT    std_logic_vector (7 DOWNTO 0)
   );

END status_registers ;

ARCHITECTURE rtl OF status_registers IS

   SIGNAL xmitting_reg, done_xmitting_reg : std_logic := '0';
   SIGNAL rcving_reg, done_rcving_reg     : std_logic := '0';

BEGIN
	
   status_registers_proc: PROCESS ( clk, rst)
   BEGIN
      IF (rst = '0') THEN
         -- Clear Registers
         xmitting_reg <= '0';
         done_xmitting_reg <= '0';
         rcving_reg <= '0';
         done_rcving_reg <= '0';
         
      ELSIF (clk'event AND clk = '1') THEN
         IF (clear_flags = '1') THEN
            -- Clear Status Flags
            xmitting_reg <= '0';
            done_xmitting_reg <= '0';
            rcving_reg <= '0';
            done_rcving_reg <= '0';
         ELSE
            -- Register signals
            xmitting_reg <= xmitting;
            rcving_reg <= rcving;
            IF  done_xmitting = '1' THEN
                done_xmitting_reg <= done_xmitting;
            END IF;
            IF done_rcving <= '1' THEN
                done_rcving_reg <= done_rcving;
            END IF;
         END IF;
      END IF;
   END PROCESS status_registers_proc;
   
   -- Assert interrupt if transmitting or receiving completed
   int <= done_xmitting_reg OR done_rcving_reg;
   -- Compose status register
   status <= "0000" & done_rcving_reg 
      & done_xmitting_reg & rcving_reg & xmitting_reg;
	
END rtl;

