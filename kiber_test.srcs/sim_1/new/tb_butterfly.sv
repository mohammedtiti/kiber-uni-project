`timescale 1ns/1ps

module tb_butterfly;

  localparam int Q = 3329;
  localparam int K2 = 169; // 13^2

  // DUT inputs/outputs
  reg        mode;
  reg [11:0] u_in;
  reg [11:0] v_in;
  reg [11:0] tw_scaled;
  wire [11:0] out0;
  wire [11:0] out1;

  // Instantiate DUT
  butterfly_k2red_kyber dut (
    .mode(mode),
    .u_in(u_in),
    .v_in(v_in),
    .tw_scaled(tw_scaled),
    .out0(out0),
    .out1(out1)
  );

  // ---------------- Reference helpers (match RTL intent) ----------------

  function automatic [11:0] add_mod_q(input [11:0] a, input [11:0] b);
    int unsigned s;
    begin
      s = a + b;            // <= 6656
      if (s >= Q) s = s - Q;
      add_mod_q = s[11:0];
    end
  endfunction

  function automatic [11:0] sub_mod_q(input [11:0] a, input [11:0] b);
    int signed d;
    begin
      d = int'(a) - int'(b);
      if (d < 0) d = d + Q;
      sub_mod_q = d[11:0];
    end
  endfunction

  // Model what K2RED does to a 24-bit product:
  // t_red = (K2 * prod) mod Q
  function automatic [11:0] k2red_model_from_prod(input int unsigned prod);
    int unsigned modv;
    begin
      modv = (K2 * prod) % Q;
      k2red_model_from_prod = modv[11:0];
    end
  endfunction

  // Compute expected (out0,out1) for given inputs, matching your RTL behavior
  task automatic compute_expected(
      input  bit        mode_i,
      input  [11:0]     u_i,
      input  [11:0]     v_i,
      input  [11:0]     tw_i,
      output [11:0]     e0,
      output [11:0]     e1
  );
    int unsigned prod;
    reg [11:0] mult_in;
    reg [11:0] t_red;
    reg [11:0] d_gs;
    begin
      // RTL uses: d_gs = sub_mod_q(v_in, u_in)  (v - u mod q)
      d_gs = sub_mod_q(v_i, u_i);

      mult_in = (mode_i == 1'b0) ? v_i : d_gs;

      prod  = int'(mult_in) * int'(tw_i);       // fits 24-bit for Kyber (<= ~11M)
      t_red = k2red_model_from_prod(prod);

      if (mode_i == 1'b0) begin
        // CT
        e0 = add_mod_q(u_i, t_red);
        e1 = sub_mod_q(u_i, t_red);
      end else begin
        // GS
        e0 = add_mod_q(u_i, v_i);
        e1 = t_red;
      end
    end
  endtask

  // Compare DUT vs expected
  task automatic check_one(input bit mode_i, input [11:0] u_i, input [11:0] v_i, input [11:0] tw_i);
    reg [11:0] e0, e1;
    begin
      compute_expected(mode_i, u_i, v_i, tw_i, e0, e1);

      mode      = mode_i;
      u_in      = u_i;
      v_in      = v_i;
      tw_scaled = tw_i;
      #1; // combinational settle

      if (out0 !== e0 || out1 !== e1) begin
        $display("FAIL time=%0t mode=%0d u=%0d v=%0d tw=%0d | out0=%0d exp0=%0d | out1=%0d exp1=%0d",
                 $time, mode_i, u_i, v_i, tw_i, out0, e0, out1, e1);
        $stop;
      end
    end
  endtask

  integer i;

  initial begin
    $display("Starting BUTTERFLY tests...");

    // Directed tests
    check_one(0, 12'd0,    12'd0,    12'd0);
    check_one(0, 12'd1,    12'd2,    12'd3);
    check_one(0, 12'd3328, 12'd3328, 12'd3328);

    check_one(1, 12'd0,    12'd0,    12'd0);
    check_one(1, 12'd1,    12'd2,    12'd3);
    check_one(1, 12'd3328, 12'd1,    12'd100);

    // Random tests (both modes)
    for (i = 0; i < 5000; i = i + 1) begin
      check_one(0,
        $urandom % Q,
        $urandom % Q,
        $urandom % Q
      );

      check_one(1,
        $urandom % Q,
        $urandom % Q,
        $urandom % Q
      );
    end

    $display("PASS: butterfly tests passed.");
    $finish;
  end

  // Hard timeout to avoid “runs forever” issues
  initial begin
    #100000; // 100us
    $display("TIMEOUT: simulation did not finish.");
    $finish;
  end

endmodule
