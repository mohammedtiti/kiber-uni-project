`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.01.2026 10:51:42
// Design Name: 
// Module Name: tb_twiddle_rom_k2red
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_twiddle_rom_k2red;

  localparam int AW = 7;
  localparam int DW = 12;
  localparam int DEPTH = 1 << AW;

  logic              clk;
  logic [AW-1:0]      addr;
  logic [DW-1:0]      tf;

  // DUT: use your ROM module name/ports here
  // This assumes you used the synchronous BRAM-style ROM I gave earlier:
  //   input clk, input [6:0] addr, output reg [11:0] tf
  twiddle_rom_k2red #(
      .AW(AW),
      .DW(DW),
      .MEMFILE("twiddle_k2red.mem")
  ) dut (
      .clk  (clk),
      .addr (addr),
      .tf   (tf)
  );

  // Clock
  initial clk = 0;
  always #5 clk = ~clk;

  // Expected values (decimal, index 0..127)
  int unsigned exp [0:127] = '{
    2285,2226,1223,817,573,3083,2476,2144,3158,422,516,2114,2648,1739,2931,3221,
    1493,2078,2036,1322,2500,2552,107,1819,962,3038,1711,2455,1787,418,448,958,
    2970,555,2777,603,264,1159,3058,2051,1577,177,3009,1218,732,2457,1821,996,
    287,1550,3047,1864,1727,2727,3082,2459,1855,1574,126,2142,3124,3173,677,1522,
    2571,430,652,1097,2004,778,3239,1799,622,587,3321,3193,1017,644,961,3021,
    1422,871,1491,2044,1458,1483,1908,2475,2127,2869,2167,220,411,329,2264,1869,
    1812,843,1015,610,383,3182,830,794,182,3094,2663,1994,608,349,2604,991,
    202,105,1785,384,3199,1119,2378,478,1468,1653,1469,1670,1758,3254,2054,1628
  };

  int errors = 0;

  initial begin
  errors = 0;
  addr   = '0;

  $display("=== tb_twiddle_rom_k2red: start ===");

  for (int i = 0; i < DEPTH; i++) begin
    addr = i[AW-1:0];        // drive address for this read (blocking is fine here)
    @(posedge clk);          // ROM updates tf here
    #1ps;                    // tiny delay to avoid sampling in same timestep

    if (tf !== exp[i][DW-1:0]) begin
      $display("MISMATCH @addr=%0d: got %0d (0x%0h), expected %0d (0x%0h)",
               i, tf, tf, exp[i], exp[i]);
      errors++;
    end else begin
      $display("OK @addr=%0d: tf=%0d (0x%0h)", i, tf, tf);
    end
  end

  if (errors == 0) $display("=== PASS: all %0d twiddles matched ===", DEPTH);
  else             $display("=== FAIL: %0d mismatches ===", errors);

  $finish;
end



endmodule