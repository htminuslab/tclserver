//
// Module UART_TXT.tester.rtl
//
// Created:
//          by - user.group (host.domain)
//          at - 19:23:16 4 Feb 2002
//
// Siemens HDL Designer(TM)
//

`resetall
`timescale 1ns/10ps

module tester( 
   datout, 
   int, 
   sout, 
   addr, 
   clk, 
   cs, 
   datin, 
   nrw, 
   rst, 
   sin
);


// Internal Declarations

input  [7:0] datout;
input        int;
input        sout;
output [2:0] addr;
output       clk;
output       cs;
output [7:0] datin;
output       nrw;
output       rst;
output       sin;


wire [7:0] datout;
wire int;
wire sout;
reg [2:0] addr;
reg clk;
reg cs;
reg [7:0] datin;
reg nrw;
reg rst;
reg sin;

// Module declarations
parameter clk_prd = 100 ;
parameter rcv_clk_prd = (clk_prd * 6);

reg [7:0] div_lsb, div_msb, ser_data, xmit_data;
reg int_clk;

reg [7:0] read_data;
integer i;

// ---------------------
//    UART_WRITE
// ---------------------
task uart_write;
   input [7:0] bit_data;
   input [2:0] addr_w;
begin
   addr = addr_w;
   nrw = # (clk_prd) 1;
   datin = bit_data;
   cs = #(clk_prd) 0;
   cs = #(5*clk_prd) 1;
   nrw = #(clk_prd) 0;
   # clk_prd;
end
endtask

// ---------------------
//    UART_READ
// ---------------------
task uart_read ;
input [2:0] addr_r;
begin
    addr = addr_r;
    nrw = #( 2*clk_prd) 0 ;
    cs = #(clk_prd) 0;
    #(9*clk_prd);
    read_data = datout;
    cs = #(2*clk_prd) 1 ; 
    #clk_prd;
 end
endtask

////////////////////////
initial 
begin : tester_top_proc
   int_clk = 0;
   div_lsb = 8'b00000110;
   div_msb = 8'b0;
   ser_data = 8'b11001110;
   xmit_data = 8'b01011010;
   cs = 1;
   nrw = 0;
   addr = "000";
   sin = 1;
   rst = 0;
   datin = # clk_prd 8'b00000000;
   rst = # (clk_prd) 1 ;
   # (3*clk_prd);
   uart_write(div_lsb,0);
   # (7*clk_prd);
   uart_write(div_msb,1);
   # (7*clk_prd);

   uart_write(xmit_data,4);
   for (i=0;i<60;i=i+1) begin
      if (int==1) begin
         i = 60;
      end
      else begin
         #clk_prd;
      end
   end
   if (int==1 && i != 60) begin
      wait (int_clk == 0 || int_clk);
      uart_read(7);
   end
   else begin
      wait (int_clk == 0 || int_clk);
      $display("Test bench failure : interrupt did not occur");
   end

   sin = 0;
   # (3*clk_prd);
   for (i=0;i<8;i=i+1) begin
      sin <= ser_data[i];
      # (6*clk_prd);
   end
   sin = 1;
   # (10*clk_prd);
   uart_read(7);
   uart_read(5);
   if (!(read_data == ser_data)) begin
      $display( 
         "Test bench failure : Read Data did NOT equal Serial Data");
   end


   uart_read(6);
   if (!(read_data == 8'b0)) begin
      $display("Status NOT zero");
   end

   $display("Uart Testing Complete");
   $stop;
end

// Clock Generator
initial
   begin : clock_gen_proc
      int_clk = 0;
      forever #(clk_prd/2) int_clk = ~int_clk;
   end

always @(int_clk)
   begin : assign_clk_proc
      clk = int_clk;
   end

endmodule // tester

