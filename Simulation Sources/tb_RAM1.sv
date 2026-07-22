`timescale 1ns/1ps

module tb_RAM1;

  localparam int AW = 8;
  localparam int DW = 12;

  logic clk;

  // Port A
  logic              we_a;
  logic [AW-1:0]     addr_a;
  logic [DW-1:0]     din_a;
  logic [DW-1:0]     dout_a;

  // Port B
  logic              we_b;
  logic [AW-1:0]     addr_b;
  logic [DW-1:0]     din_b;
  logic [DW-1:0]     dout_b;

  // DUT
  RAM1 #(
    .AW(AW),
    .DW(DW),
    .MEMFILE("")   // disable init for deterministic tests
  ) dut (
    .clk(clk),
    .we_a(we_a), .addr_a(addr_a), .din_a(din_a), .dout_a(dout_a),
    .we_b(we_b), .addr_b(addr_b), .din_b(din_b), .dout_b(dout_b)
  );

  // Clock: 100 MHz
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // ----------------------------
  // Helper tasks
  // ----------------------------
  task automatic set_idle();
    we_a   = 0; addr_a = '0; din_a = '0;
    we_b   = 0; addr_b = '0; din_b = '0;
  endtask

  task automatic writeA(input [AW-1:0] a, input [DW-1:0] d);
    @(negedge clk);
    we_a   = 1;
    addr_a = a;
    din_a  = d;
    @(negedge clk);
    we_a   = 0;
  endtask

  task automatic writeB(input [AW-1:0] a, input [DW-1:0] d);
    @(negedge clk);
    we_b   = 1;
    addr_b = a;
    din_b  = d;
    @(negedge clk);
    we_b   = 0;
  endtask

  // For sync-read RAM: if you set addr at negedge,
  // the read value appears after the *next* posedge.
  task automatic readA_check(input [AW-1:0] a, input [DW-1:0] expected);
    @(negedge clk);
    addr_a = a;
    @(posedge clk); #1;
    if (dout_a !== expected) begin
      $display("[%0t] ERROR readA addr=%0d got=%0d exp=%0d",
               $time, a, dout_a, expected);
      $fatal;
    end
  endtask

  task automatic readB_check(input [AW-1:0] a, input [DW-1:0] expected);
    @(negedge clk);
    addr_b = a;
    @(posedge clk); #1;
    if (dout_b !== expected) begin
      $display("[%0t] ERROR readB addr=%0d got=%0d exp=%0d",
               $time, a, dout_b, expected);
      $fatal;
    end
  endtask

  // ----------------------------
  // Main test
  // ----------------------------
  initial begin
    set_idle();

    // Give a couple clocks
    repeat (2) @(posedge clk);

    // 1) Basic write/read Port A
    writeA(8'd10, 12'd1234);
    readA_check(8'd10, 12'd1234);

    // 2) Basic write/read Port B
    writeB(8'd20, 12'd2222);
    readB_check(8'd20, 12'd2222);

    // 3) Parallel writes (different addresses) same cycle
    @(negedge clk);
    we_a   = 1; addr_a = 8'd30; din_a = 12'd3000;
    we_b   = 1; addr_b = 8'd31; din_b = 12'd3100;
    @(negedge clk);
    we_a   = 0;
    we_b   = 0;

    readA_check(8'd30, 12'd3000);
    readB_check(8'd31, 12'd3100);

    // 4) Parallel read (different addresses) in same cycle
    // Set addresses together, both should update after next posedge
    @(negedge clk);
    addr_a = 8'd10;
    addr_b = 8'd20;
    @(posedge clk); #1;
    if (dout_a !== 12'd1234) $fatal(1, "Parallel read A mismatch");
    if (dout_b !== 12'd2222) $fatal(1, "Parallel read B mismatch");

    // 5) Read-first check (same port reads+write same addr in same cycle)
    // Put known value first
    writeA(8'd40, 12'd111);
    // Now do a read+write same cycle: expect old value at output (read-first)
    @(negedge clk);
    addr_a = 8'd40;
    we_a   = 1;
    din_a  = 12'd999;
    @(posedge clk); #1;
    // Because your code does dout_a <= ram[addr_a] before updating ram[addr_a],
    // dout_a should still show the OLD value (111) on this clock.
    if (dout_a !== 12'd111) begin
      $display("[%0t] ERROR read-first violated: got %0d exp %0d", $time, dout_a, 12'd111);
      $fatal;
    end
    @(negedge clk);
    we_a = 0;

    // And next read should show new value
    readA_check(8'd40, 12'd999);

    // 6) Same-address write collision (A and B write same addr same cycle)
    // Expect Port B wins (as documented)
    @(negedge clk);
    we_a   = 1; addr_a = 8'd50; din_a = 12'd555;
    we_b   = 1; addr_b = 8'd50; din_b = 12'd777;
    @(negedge clk);
    we_a   = 0;
    we_b   = 0;

    // Read back via both ports
    readA_check(8'd50, 12'd777);
    readB_check(8'd50, 12'd777);

    $display("ALL TESTS PASSED !!!");
    $finish;
  end

endmodule
