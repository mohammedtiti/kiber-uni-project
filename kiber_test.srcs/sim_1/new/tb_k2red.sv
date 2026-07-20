`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 22.01.2026 11:07:43
// Design Name: 
// Module Name: tb_k2red
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


`timescale 1ns/1ps

module tb_k2red;

  // DUT ports
  reg  [23:0] C;
  wire [11:0] R;

  // Instantiate DUT (must match the module name in K2RED.v)
  k2red_kyber dut (
    .C(C),
    .R(R)
  );

  // Reference model: expected = (169 * C) mod 3329
  function automatic [11:0] k2red_ref(input [23:0] c_in);
    longint unsigned prod;
    longint unsigned modv;
    begin
      prod = 169 * longint'(c_in);
      modv = prod % 3329;
      k2red_ref = modv[11:0];
    end
  endfunction

  task automatic check(input [23:0] c_in);
    reg [11:0] exp;
    begin
      C = c_in;
      #1; // combinational settle
      exp = k2red_ref(c_in);

      if (R !== exp) begin
        $display("FAIL: time=%0t  C=%0d (0x%06h)  R=%0d (0x%03h)  exp=%0d (0x%03h)",
                 $time, c_in, c_in, R, R, exp, exp);
        $stop;
      end
    end
  endtask

  integer i;

  initial begin
    $display("Starting K2RED tests...");

    // Some directed edge-ish tests
    check(24'd0);
    check(24'd1);
    check(24'd2);
    check(24'd3328);     // q-1
    check(24'd3329);     // q
    check(24'd3330);
    check(24'd65535);
    check(24'd1000000);
    check(24'hFFFFFF);   // max 24-bit

    // Random tests
    for (i = 0; i < 5000; i = i + 1) begin
      check($urandom & 24'hFFFFFF);
    end

    $display("PASS: all tests passed.");
    $finish;
  end

endmodule

