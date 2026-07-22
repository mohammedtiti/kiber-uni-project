`timescale 1ns/1ps

module tb_kyber_modmul;
  localparam int Q = 3329;
  logic [11:0] a, b;
  wire [11:0] r;
  integer checks;
  int unsigned seed;

  kyber_modmul dut (.a(a), .b(b), .r(r));

  task automatic check(input int unsigned av, input int unsigned bv);
    int unsigned expected;
    begin
      a = av[11:0];
      b = bv[11:0];
      #1;
      expected = (av * bv) % Q;
      if (r !== expected[11:0]) begin
        $display("FAIL a=%0d b=%0d got=%0d expected=%0d", av, bv, r, expected);
        $fatal(1);
      end
      if (r >= Q)
        $fatal(1, "FAIL non-canonical result %0d", r);
      checks = checks + 1;
    end
  endtask

  initial begin
    integer i, j;
    static int unsigned edges [0:11] = '{0,1,2,12,13,16,17,127,128,169,3328,3327};
    checks = 0;
    for (i = 0; i < 12; i = i + 1)
      for (j = 0; j < 12; j = j + 1)
        check(edges[i], edges[j]);

    seed = 32'h4b796265;
    for (i = 0; i < 512; i = i + 1) begin
      seed = seed * 32'd1664525 + 32'd1013904223;
      a = seed % Q;
      seed = seed * 32'd1664525 + 32'd1013904223;
      b = seed % Q;
      #1;
      if (r !== ((int'(a) * int'(b)) % Q))
        $fatal(1, "FAIL random a=%0d b=%0d got=%0d", a, b, r);
      checks = checks + 1;
    end
    $display("PASS: kyber_modmul %0d directed/random checks", checks);
    $finish;
  end
endmodule
