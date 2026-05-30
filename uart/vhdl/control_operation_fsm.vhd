--
-- VHDL Architecture UART_TXT.control_operation.symbol
--
-- Created:
--          by - user.group (host.domain)
--          at - 19:05:13 4 Feb 2002
--
-- Siemens HDL Designer(TM)
--

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;

ENTITY control_operation IS
   PORT( 
      clk          : IN     std_logic;
      clr_int_en   : IN     std_logic;
      cs           : IN     std_logic;
      nrw          : IN     std_logic;
      rst          : IN     std_logic;
      xmitdt_en    : IN     std_logic;
      clear_flags  : OUT    std_logic;
      enable_write : OUT    std_logic;
      start_xmit   : OUT    std_logic
   );

END control_operation ;

ARCHITECTURE fsm OF control_operation IS

   -- Architecture Declarations
   TYPE STATE_TYPE IS (
      idle,
      reading_from_reg,
      clearing_flags,
      writing_to_reg,
      xmitting
   );

   -- State vector declaration
   ATTRIBUTE state_vector : string;
   ATTRIBUTE state_vector OF fsm : ARCHITECTURE IS "current_state" ;

   -- Declare current and next state signals
   SIGNAL current_state : STATE_TYPE ;
   SIGNAL next_state : STATE_TYPE ;

BEGIN

   -------------------------------------------------------------------
   clocked_proc : PROCESS(
      clk,
      rst
   )
   -------------------------------------------------------------------
   BEGIN
      IF (rst = '0') THEN
         current_state <= idle;
      ELSIF (clk'EVENT AND clk = '1') THEN
         current_state <= next_state;

      END IF;

   END PROCESS clocked_proc;

   -------------------------------------------------------------------
   nextstate_proc : PROCESS (
      clr_int_en,
      cs,
      current_state,
      nrw,
      xmitdt_en
   )
   -------------------------------------------------------------------
   BEGIN
      -- Default Assignment
      clear_flags <= '0';
      enable_write <= '0';
      start_xmit <= '0';

      -- State Actions
      CASE current_state IS
      WHEN clearing_flags =>
         clear_flags <= '1';
      WHEN writing_to_reg =>
         enable_write <= '1';
      WHEN xmitting =>
         start_xmit <= '1';
      WHEN OTHERS =>
         NULL;
      END CASE;

      CASE current_state IS
      WHEN idle =>
         IF (nrw = '1' AND cs = '0') THEN
            next_state <= writing_to_reg;
         ELSIF (nrw = '0' AND cs = '0') THEN
            next_state <= reading_from_reg;
         ELSE
            next_state <= idle;
         END IF;
      WHEN reading_from_reg =>
         IF (cs = '1') THEN
            next_state <= idle;
         ELSIF (nrw = '0' AND clr_int_en = '1') THEN
            next_state <= clearing_flags;
         ELSE
            next_state <= reading_from_reg;
         END IF;
      WHEN clearing_flags =>
         IF (cs = '1') THEN
            next_state <= idle;
         ELSE
            next_state <= clearing_flags;
         END IF;
      WHEN writing_to_reg =>
         IF (cs = '1') THEN
            next_state <= idle;
         ELSIF (nrw = '1' AND xmitdt_en = '1') THEN
            next_state <= xmitting;
         ELSE
            next_state <= writing_to_reg;
         END IF;
      WHEN xmitting =>
         IF (cs = '1') THEN
            next_state <= idle;
         ELSE
            next_state <= xmitting;
         END IF;
      WHEN OTHERS =>
         next_state <= idle;
      END CASE;

   END PROCESS nextstate_proc;

END fsm;

