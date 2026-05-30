//
// Module UART_TXT.uart_tb.rtl
//
// Created:
//          by - user.group (host.domain)
//          at - 18:51:35 4 Feb 2002
//
// Siemens HDL Designer(TM)
//

`resetall
`timescale 1ns/10ps

module uart_tb;

wire [2:0] addr;      // 3-bit address bus
wire       clk;       // 10 MHz clock
wire       cs;        // chip select
wire [7:0] datin;     // 8-bit data in bus from cpu
wire [7:0] datout;    // 8-bit data out bus to cpu
wire       int;       // interrupt(1)
wire       nrw;       // read(0), write(1)
wire       rst;       // reset(0)
wire       sin;       // serial input
wire       sout;      // serial output


// Instances 
tester U_0( 
   .datout (datout), 
   .int      (int), 
   .sout     (sout), 
   .addr     (addr), 
   .clk      (clk), 
   .cs       (cs), 
   .datin  (datin), 
   .nrw      (nrw), 
   .rst      (rst), 
   .sin      (sin)
); 

uart_top U_1( 
   .addr     (addr), 
   .clk      (clk), 
   .cs       (cs), 
   .datin  (datin), 
   .nrw      (nrw), 
   .rst      (rst), 
   .sin      (sin), 
   .datout (datout), 
   .int      (int), 
   .sout     (sout)
); 

endmodule

