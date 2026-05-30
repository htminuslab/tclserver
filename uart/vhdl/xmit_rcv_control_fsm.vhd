--
-- VHDL Architecture UART_TXT.xmit_rcv_control.symbol
--
-- Created:
--          by - user.group (host.domain)
--          at - 19:10:38 4 Feb 2002
--
-- Siemens HDL Designer(TM)
--

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;

ENTITY xmit_rcv_control IS
   PORT( 
      clk             : IN     std_logic;
      rst             : IN     std_logic;
      sample          : IN     std_logic;
      sin             : IN     std_logic;
      start_xmit      : IN     std_logic;
      xmitdt          : IN     std_logic_vector (7 DOWNTO 0);
      done_rcving     : OUT    std_logic;
      done_xmitting   : OUT    std_logic;
      enable_rcv_clk  : OUT    std_logic;
      enable_xmit_clk : OUT    std_logic;
      rcv_bit_cnt     : OUT    std_logic_vector (2 DOWNTO 0);
      rcving          : OUT    std_logic;
      read_bit        : OUT    std_logic;
      sout            : OUT    std_logic;
      xmitting        : OUT    std_logic
   );

END xmit_rcv_control ;

ARCHITECTURE fsm OF xmit_rcv_control IS

   -- Architecture Declarations
   SIGNAL xmit_bit_cnt : std_logic_vector(2 downto 0) := "000";

   TYPE RCV_STATE_TYPE IS (
      waiting,
      check_lock,
      rcv_locked,
      read_data,
      incr_count2,
      done_read,
      read_stop_bit,
      finish_rcv
   );
   TYPE XMIT_STATE_TYPE IS (
      waiting_to_xmit,
      send_start,
      send_data,
      incr_count,
      done_xmit,
      send_stop_bit,
      finish_xmit
   );

   -- Declare current and next state signals
   SIGNAL rcv_current_state : RCV_STATE_TYPE ;
   SIGNAL rcv_next_state : RCV_STATE_TYPE ;
   SIGNAL xmit_current_state : XMIT_STATE_TYPE ;
   SIGNAL xmit_next_state : XMIT_STATE_TYPE ;

   -- Declare any pre-registered internal signals
   SIGNAL enable_xmit_clk_cld : std_logic  ;
   SIGNAL rcv_bit_cnt_cld : std_logic_vector (2 DOWNTO 0) ;
   SIGNAL sout_cld : std_logic  ;
   SIGNAL xmitting_cld : std_logic  ;

BEGIN

   -------------------------------------------------------------------
   rcv_clocked_proc : PROCESS(
      clk,
      rst
   )
   -------------------------------------------------------------------
   BEGIN
      IF (rst = '0') THEN
         rcv_current_state <= waiting;
         -- Reset Values
         rcv_bit_cnt_cld <= (others=>'0');
      ELSIF (clk'EVENT AND clk = '1') THEN
         rcv_current_state <= rcv_next_state;

         -- State Actions for internal signals only
         CASE rcv_current_state IS
         WHEN waiting =>
            rcv_bit_cnt_cld <= "000";
         WHEN OTHERS =>
            NULL;
         END CASE;

         -- Transition Actions for internal signals only
         CASE rcv_current_state IS
         WHEN waiting =>
            IF (sin='0') THEN
               rcv_bit_cnt_cld <= "000";
            END IF;
         WHEN incr_count2 =>
            IF (sample='1' AND rcv_bit_cnt_cld /= "111") THEN
               rcv_bit_cnt_cld <= unsigned(rcv_bit_cnt_cld) + 1;
            END IF;
         WHEN OTHERS =>
            NULL;
         END CASE;

      END IF;

   END PROCESS rcv_clocked_proc;

   -------------------------------------------------------------------
   rcv_nextstate_proc : PROCESS (
      rcv_current_state,
      rcv_bit_cnt_cld,
      sample,
      sin
   )
   -------------------------------------------------------------------
   BEGIN
      -- Default Assignment
      done_rcving <= '0';
      enable_rcv_clk <= '0';
      rcving <= '0';
      read_bit <= '0';

      -- State Actions
      CASE rcv_current_state IS
      WHEN check_lock =>
         enable_rcv_clk <= '1';
      WHEN rcv_locked =>
         rcving <= '1';
         enable_rcv_clk <= '1';
      WHEN read_data =>
         rcving <= '1';
         enable_rcv_clk <= '1';
      WHEN incr_count2 =>
         rcving <= '1';
         enable_rcv_clk <= '1';
      WHEN done_read =>
         rcving <= '1';
         enable_rcv_clk <= '1';
      WHEN read_stop_bit =>
         rcving <= '1';
         enable_rcv_clk <= '1';
      WHEN finish_rcv =>
         enable_rcv_clk <= '0';
         rcving <= '0';
         done_rcving <= '1';
      WHEN OTHERS =>
         NULL;
      END CASE;

      CASE rcv_current_state IS
      WHEN waiting =>
         IF (sin='0') THEN
            enable_rcv_clk <= '1';
            rcv_next_state <= check_lock;
         ELSE
            rcv_next_state <= waiting;
         END IF;
      WHEN check_lock =>
         IF (sin='1') THEN
            enable_rcv_clk <= '0';
            rcv_next_state <= waiting;
         ELSIF (sin='0') THEN
            rcv_next_state <= rcv_locked;
         ELSE
            rcv_next_state <= check_lock;
         END IF;
      WHEN rcv_locked =>
         IF (sample='1') THEN
            rcv_next_state <= read_data;
         ELSE
            rcv_next_state <= rcv_locked;
         END IF;
      WHEN read_data =>
         IF (sample='0') THEN
            rcv_next_state <= incr_count2;
         ELSE
            rcv_next_state <= read_data;
         END IF;
      WHEN incr_count2 =>
         IF (sample='1' AND rcv_bit_cnt_cld /= "111") THEN
            read_bit <= '1';
            rcv_next_state <= read_data;
         ELSIF (sample='1' AND rcv_bit_cnt_cld = "111") THEN
            read_bit <= '1';
            rcv_next_state <= done_read;
         ELSE
            rcv_next_state <= incr_count2;
         END IF;
      WHEN done_read =>
         IF (sample='0') THEN
            rcv_next_state <= read_stop_bit;
         ELSE
            rcv_next_state <= done_read;
         END IF;
      WHEN read_stop_bit =>
         IF (sample='1') THEN
            rcv_next_state <= finish_rcv;
         ELSE
            rcv_next_state <= read_stop_bit;
         END IF;
      WHEN finish_rcv =>
            rcv_next_state <= waiting;
      WHEN OTHERS =>
         rcv_next_state <= waiting;
      END CASE;

   END PROCESS rcv_nextstate_proc;

   -------------------------------------------------------------------
   xmit_clocked_proc : PROCESS(
      clk,
      rst
   )
   -------------------------------------------------------------------
   BEGIN
      IF (rst = '0') THEN
         xmit_current_state <= waiting_to_xmit;
         -- Reset Values
         enable_xmit_clk_cld <= '0';
         sout_cld <= '1';
         xmitting_cld <= '0';
         xmit_bit_cnt <= (others=>'0');
      ELSIF (clk'EVENT AND clk = '1') THEN
         xmit_current_state <= xmit_next_state;
         -- Default Assignment To Internals
         sout_cld <= '1';

         -- State Actions for internal signals only
         CASE xmit_current_state IS
         WHEN waiting_to_xmit =>
            xmit_bit_cnt <= "000";
         WHEN send_start =>
            sout_cld <= '0';
            enable_xmit_clk_cld <= '1';
            xmitting_cld <= '1';
         WHEN send_data =>
            sout_cld <= xmitdt(CONV_INTEGER(unsigned(xmit_bit_cnt)));
         WHEN incr_count =>
            sout_cld <= xmitdt(CONV_INTEGER(unsigned(xmit_bit_cnt)));
         WHEN finish_xmit =>
            enable_xmit_clk_cld <= '0';
            xmitting_cld <= '0';
         WHEN OTHERS =>
            NULL;
         END CASE;

         -- Transition Actions for internal signals only
         CASE xmit_current_state IS
         WHEN send_data =>
            IF (sample='0') THEN
               xmit_bit_cnt <= unsigned(xmit_bit_cnt) + 1;
            END IF;
         WHEN OTHERS =>
            NULL;
         END CASE;

      END IF;

   END PROCESS xmit_clocked_proc;

   -------------------------------------------------------------------
   xmit_nextstate_proc : PROCESS (
      xmit_current_state,
      sample,
      start_xmit,
      xmit_bit_cnt
   )
   -------------------------------------------------------------------
   BEGIN
      -- Default Assignment
      done_xmitting <= '0';

      -- State Actions
      CASE xmit_current_state IS
      WHEN send_stop_bit =>
         done_xmitting <= '1';
      WHEN OTHERS =>
         NULL;
      END CASE;

      CASE xmit_current_state IS
      WHEN waiting_to_xmit =>
         IF (start_xmit='1') THEN
            xmit_next_state <= send_start;
         ELSE
            xmit_next_state <= waiting_to_xmit;
         END IF;
      WHEN send_start =>
         IF (sample='1') THEN
            xmit_next_state <= send_data;
         ELSE
            xmit_next_state <= send_start;
         END IF;
      WHEN send_data =>
         IF (sample='0') THEN
            xmit_next_state <= incr_count;
         ELSE
            xmit_next_state <= send_data;
         END IF;
      WHEN incr_count =>
         IF (sample='1' AND xmit_bit_cnt /= "000") THEN
            xmit_next_state <= send_data;
         ELSIF (sample='1' AND xmit_bit_cnt = "000") THEN
            xmit_next_state <= done_xmit;
         ELSE
            xmit_next_state <= incr_count;
         END IF;
      WHEN done_xmit =>
         IF (sample='0') THEN
            xmit_next_state <= send_stop_bit;
         ELSE
            xmit_next_state <= done_xmit;
         END IF;
      WHEN send_stop_bit =>
            xmit_next_state <= finish_xmit;
      WHEN finish_xmit =>
            xmit_next_state <= waiting_to_xmit;
      WHEN OTHERS =>
         xmit_next_state <= waiting_to_xmit;
      END CASE;

   END PROCESS xmit_nextstate_proc;

   -- Clocked output assignments
   enable_xmit_clk <= enable_xmit_clk_cld;
   rcv_bit_cnt <= rcv_bit_cnt_cld;
   sout <= sout_cld;
   xmitting <= xmitting_cld;


END fsm;

