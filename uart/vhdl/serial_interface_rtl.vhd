--
-- VHDL Architecture UART_TXT.serial_interface.symbol
--
-- Created:
--          by - user.group (host.domain)
--          at - 19:06:17 4 Feb 2002
--
-- Siemens HDL Designer(TM)
--

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;

ENTITY serial_interface IS
   PORT( 
      clear_flags     : IN     std_logic;
      clk             : IN     std_logic;
      datin           : IN     std_logic_vector (7 DOWNTO 0);
      enable_write    : IN     std_logic;
      rst             : IN     std_logic;
      sample          : IN     std_logic;
      ser_if_select   : IN     std_logic_vector (1 DOWNTO 0);
      sin             : IN     std_logic;
      start_xmit      : IN     std_logic;
      xmitdt_en       : IN     std_logic;
      enable_rcv_clk  : OUT    std_logic;
      enable_xmit_clk : OUT    std_logic;
      int             : OUT    std_logic;
      ser_if_data     : OUT    std_logic_vector (7 DOWNTO 0);
      sout            : OUT    std_logic
   );

END serial_interface ;

ARCHITECTURE rtl OF serial_interface IS

   -- Internal signal declarations
   SIGNAL done_rcving   : std_logic;
   SIGNAL done_xmitting : std_logic;
   SIGNAL rcv_bit_cnt   : std_logic_vector(2 DOWNTO 0);
   SIGNAL rcving        : std_logic;
   SIGNAL read_bit      : std_logic;
   SIGNAL recvdt        : std_logic_vector(7 DOWNTO 0);
   SIGNAL status        : std_logic_vector(7 DOWNTO 0);
   SIGNAL xmitdt        : std_logic_vector(7 DOWNTO 0);
   SIGNAL xmitting      : std_logic;
   SIGNAL zeros         : std_logic_vector(7 DOWNTO 0);

   -- Signal declarations for instance 'ser_out_mux' of 'mux4'
   SIGNAL mw_ser_out_muxdin0l : std_logic_vector(7 DOWNTO 0);
   SIGNAL mw_ser_out_muxdin1l : std_logic_vector(7 DOWNTO 0);
   SIGNAL mw_ser_out_muxdin2l : std_logic_vector(7 DOWNTO 0);
   SIGNAL mw_ser_out_muxdin3l : std_logic_vector(7 DOWNTO 0);
   SIGNAL mw_ser_out_muxdtemp : std_logic_vector(7 DOWNTO 0);

   -- Component Declarations
   COMPONENT status_registers
   PORT (
      clear_flags   : IN     std_logic ;
      clk           : IN     std_logic ;
      done_rcving   : IN     std_logic ;
      done_xmitting : IN     std_logic ;
      rcving        : IN     std_logic ;
      rst           : IN     std_logic ;
      xmitting      : IN     std_logic ;
      int           : OUT    std_logic ;
      status        : OUT    std_logic_vector (7 DOWNTO 0)
   );
   END COMPONENT;
   COMPONENT xmit_rcv_control
   PORT (
      clk             : IN     std_logic ;
      rst             : IN     std_logic ;
      sample          : IN     std_logic ;
      sin             : IN     std_logic ;
      start_xmit      : IN     std_logic ;
      xmitdt          : IN     std_logic_vector (7 DOWNTO 0);
      done_rcving     : OUT    std_logic ;
      done_xmitting   : OUT    std_logic ;
      enable_rcv_clk  : OUT    std_logic ;
      enable_xmit_clk : OUT    std_logic ;
      rcv_bit_cnt     : OUT    std_logic_vector (2 DOWNTO 0);
      rcving          : OUT    std_logic ;
      read_bit        : OUT    std_logic ;
      sout            : OUT    std_logic ;
      xmitting        : OUT    std_logic 
   );
   END COMPONENT;

BEGIN
   -- Architecture concurrent statements
   -------------------------------------------------------------------
   conv_proc : PROCESS (clk, rst)
   -------------------------------------------------------------------
   BEGIN
      -- Asynchronous Reset
      IF (rst = '0') THEN
         -- Reset Actions
         xmitdt <= "00000000";
         recvdt <= "00000000";

      ELSIF (clk'EVENT AND clk = '1') THEN
         IF xmitdt_en = '1' AND enable_write = '1' THEN
            xmitdt <= datin;
         ELSIF read_bit = '1' THEN
            recvdt(CONV_INTEGER(unsigned(rcv_bit_cnt))) <= sin;
         END IF;
      END IF;
   END PROCESS conv_proc;
  
   ser_out_muxcombo_proc: PROCESS (
      mw_ser_out_muxdin0l, mw_ser_out_muxdin1l, mw_ser_out_muxdin2l, 
      mw_ser_out_muxdin3l, mw_ser_out_muxdtemp, ser_if_select)
   BEGIN
      CASE ser_if_select IS
      WHEN "00" => mw_ser_out_muxdtemp <= mw_ser_out_muxdin0l;
      WHEN "01" => mw_ser_out_muxdtemp <= mw_ser_out_muxdin1l;
      WHEN "10" => mw_ser_out_muxdtemp <= mw_ser_out_muxdin2l;
      WHEN "11" => mw_ser_out_muxdtemp <= mw_ser_out_muxdin3l;
      WHEN OTHERS => mw_ser_out_muxdtemp <= (OTHERS => 'X');
      END CASE;
      ser_if_data <= mw_ser_out_muxdtemp;
   END PROCESS ser_out_muxcombo_proc;
   mw_ser_out_muxdin0l <= xmitdt;
   mw_ser_out_muxdin1l <= recvdt;
   mw_ser_out_muxdin2l <= status;
   mw_ser_out_muxdin3l <= "00000000";
      
   -- Instance port mappings.
   U_1 : status_registers
      PORT MAP (
         clear_flags   => clear_flags,
         clk           => clk,
         done_rcving   => done_rcving,
         done_xmitting => done_xmitting,
         rcving        => rcving,
         rst           => rst,
         xmitting      => xmitting,
         int           => int,
         status        => status
      );
   U_0 : xmit_rcv_control
      PORT MAP (
         clk             => clk,
         rst             => rst,
         sample          => sample,
         sin             => sin,
         start_xmit      => start_xmit,
         xmitdt          => xmitdt,
         done_rcving     => done_rcving,
         done_xmitting   => done_xmitting,
         enable_rcv_clk  => enable_rcv_clk,
         enable_xmit_clk => enable_xmit_clk,
         rcv_bit_cnt     => rcv_bit_cnt,
         rcving          => rcving,
         read_bit        => read_bit,
         sout            => sout,
         xmitting        => xmitting
      );

      
END rtl;

