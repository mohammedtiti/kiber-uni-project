`timescale 1ns/1ps

module tb_twiddle_rom_k2red;
  localparam int Q = 3329;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic [6:0] addr;
  logic negate;
  wire [11:0] zeta, zeta_scaled;
  wire [11:0] registered_scaled;

  kyber_twiddle_rom dut (
    .addr(addr), .negate(negate),
    .zeta(zeta), .zeta_scaled(zeta_scaled)
  );
  twiddle_rom_k2red compatibility (
    .clk(clk), .addr(addr), .tf(registered_scaled)
  );

  function automatic int bitreverse7(input int value);
    integer i;
    begin
      bitreverse7 = 0;
      for (i = 0; i < 7; i = i + 1)
        bitreverse7 = (bitreverse7 << 1) | ((value >> i) & 1);
    end
  endfunction

  function automatic int pow_mod(input int base, input int exponent);
    integer result;
    begin
      result = 1;
      while (exponent > 0) begin
        if (exponent & 1)
          result = (result * base) % Q;
        base = (base * base) % Q;
        exponent = exponent >> 1;
      end
      pow_mod = result;
    end
  endfunction

  initial begin
    integer i;
    integer expected_zeta, expected_scaled;
    addr = 0;
    negate = 0;
    for (i = 0; i < 128; i = i + 1) begin
      expected_zeta = pow_mod(17, bitreverse7(i));
      expected_scaled = (expected_zeta * 2285) % Q;
      addr = i[6:0];
      negate = 0;
      #1;
      if (zeta !== expected_zeta[11:0] || zeta_scaled !== expected_scaled[11:0])
        $fatal(1, "FAIL zeta[%0d] got=(%0d,%0d) expected=(%0d,%0d)",
               i, zeta, zeta_scaled, expected_zeta, expected_scaled);

      @(posedge clk);
      #1;
      if (registered_scaled !== expected_scaled[11:0])
        $fatal(1, "FAIL compatibility ROM at %0d", i);

      negate = 1;
      #1;
      if (zeta !== (Q-expected_zeta) || zeta_scaled !== (Q-expected_scaled))
        $fatal(1, "FAIL negated zeta[%0d]", i);
    end
    $display("PASS: all 128 Kyber zetas, scaled values, and negations matched");
    $finish;
  end
endmodule
