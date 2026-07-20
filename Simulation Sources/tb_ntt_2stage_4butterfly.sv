`timescale 1ns/1ps

module tb_ntt_2stage_4butterfly;

  localparam int Q = 3329;
  localparam int K2 = 169;

  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg        mode_in;
  reg [11:0] in0, in1, in2, in3;
  reg [11:0] tw_s0_b0, tw_s0_b1, tw_s1_b0, tw_s1_b1;
  wire [11:0] out0, out1, out2, out3;

  ntt_2stage_4butterfly dut (
    .clk(clk),
    .mode_in(mode_in),
    .in0(in0),
    .in1(in1),
    .in2(in2),
    .in3(in3),
    .tw_s0_b0(tw_s0_b0),
    .tw_s0_b1(tw_s0_b1),
    .tw_s1_b0(tw_s1_b0),
    .tw_s1_b1(tw_s1_b1),
    .out0(out0),
    .out1(out1),
    .out2(out2),
    .out3(out3)
  );

  function automatic [11:0] add_mod_q(input [11:0] a, input [11:0] b);
    int unsigned s;
    begin
      s = a + b;
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

  function automatic [11:0] k2red_model_from_prod(input int unsigned prod);
    int unsigned modv;
    begin
      modv = (K2 * prod) % Q;
      k2red_model_from_prod = modv[11:0];
    end
  endfunction

  task automatic butterfly_ref(
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
      d_gs = sub_mod_q(v_i, u_i);
      mult_in = (mode_i == 1'b0) ? v_i : d_gs;
      prod = int'(mult_in) * int'(tw_i);
      t_red = k2red_model_from_prod(prod);

      if (mode_i == 1'b0) begin
        e0 = add_mod_q(u_i, t_red);
        e1 = sub_mod_q(u_i, t_red);
      end else begin
        e0 = add_mod_q(u_i, v_i);
        e1 = t_red;
      end
    end
  endtask

  task automatic block_ref(
      input  bit        mode_i,
      input  [11:0]     a0,
      input  [11:0]     a1,
      input  [11:0]     a2,
      input  [11:0]     a3,
      input  [11:0]     tw0,
      input  [11:0]     tw1,
      input  [11:0]     tw2,
      input  [11:0]     tw3,
      output [11:0]     e0,
      output [11:0]     e1,
      output [11:0]     e2,
      output [11:0]     e3
  );
    reg [11:0] b0_0, b0_1, b1_0, b1_1;
    reg [11:0] m0, m1, m2, m3;
    reg [11:0] c0_0, c0_1, c1_0, c1_1;
    begin
      if (mode_i) begin
        butterfly_ref(mode_i, a0, a1, tw0, b0_0, b0_1);
        butterfly_ref(mode_i, a2, a3, tw1, b1_0, b1_1);
        m0 = b0_0; m1 = b0_1; m2 = b1_0; m3 = b1_1;
        butterfly_ref(mode_i, m0, m2, tw2, c0_0, c0_1);
        butterfly_ref(mode_i, m1, m3, tw3, c1_0, c1_1);
        e0 = c0_0; e1 = c1_0; e2 = c0_1; e3 = c1_1;
      end else begin
        butterfly_ref(mode_i, a0, a2, tw0, b0_0, b0_1);
        butterfly_ref(mode_i, a1, a3, tw1, b1_0, b1_1);
        m0 = b0_0; m1 = b1_0; m2 = b0_1; m3 = b1_1;
        butterfly_ref(mode_i, m0, m1, tw2, c0_0, c0_1);
        butterfly_ref(mode_i, m2, m3, tw3, c1_0, c1_1);
        e0 = c0_0; e1 = c0_1; e2 = c1_0; e3 = c1_1;
      end
    end
  endtask

  task automatic check_one(
      input bit mode_i,
      input [11:0] a0,
      input [11:0] a1,
      input [11:0] a2,
      input [11:0] a3,
      input [11:0] tw0,
      input [11:0] tw1,
      input [11:0] tw2,
      input [11:0] tw3
  );
    reg [11:0] e0, e1, e2, e3;
    begin
      block_ref(mode_i, a0, a1, a2, a3, tw0, tw1, tw2, tw3, e0, e1, e2, e3);

      @(negedge clk);
      mode_in = mode_i;
      in0 = a0; in1 = a1; in2 = a2; in3 = a3;
      tw_s0_b0 = tw0; tw_s0_b1 = tw1; tw_s1_b0 = tw2; tw_s1_b1 = tw3;

      repeat (3) @(posedge clk);
      #1;

      if (out0 !== e0 || out1 !== e1 || out2 !== e2 || out3 !== e3) begin
        $display("FAIL mode=%0d in=%0d,%0d,%0d,%0d tw=%0d,%0d,%0d,%0d",
                 mode_i, a0, a1, a2, a3, tw0, tw1, tw2, tw3);
        $display(" got=%0d,%0d,%0d,%0d exp=%0d,%0d,%0d,%0d",
                 out0, out1, out2, out3, e0, e1, e2, e3);
        $stop;
      end
    end
  endtask

  integer i;

  initial begin
    mode_in = 0;
    in0 = 0; in1 = 0; in2 = 0; in3 = 0;
    tw_s0_b0 = 0; tw_s0_b1 = 0; tw_s1_b0 = 0; tw_s1_b1 = 0;

    repeat (4) @(posedge clk);

    check_one(0, 12'd0, 12'd1, 12'd2, 12'd3, 12'd4, 12'd5, 12'd6, 12'd7);
    check_one(1, 12'd0, 12'd1, 12'd2, 12'd3, 12'd4, 12'd5, 12'd6, 12'd7);
    check_one(0, 12'd3328, 12'd3327, 12'd3, 12'd2, 12'd3328, 12'd8, 12'd100, 12'd55);
    check_one(1, 12'd3328, 12'd3327, 12'd3, 12'd2, 12'd3328, 12'd8, 12'd100, 12'd55);

    for (i = 0; i < 500; i = i + 1) begin
      check_one(0, $urandom % Q, $urandom % Q, $urandom % Q, $urandom % Q,
                   $urandom % Q, $urandom % Q, $urandom % Q, $urandom % Q);
      check_one(1, $urandom % Q, $urandom % Q, $urandom % Q, $urandom % Q,
                   $urandom % Q, $urandom % Q, $urandom % Q, $urandom % Q);
    end

    $display("PASS: ntt_2stage_4butterfly tests passed.");
    $finish;
  end

  initial begin
    #200000;
    $display("TIMEOUT: simulation did not finish.");
    $finish;
  end

endmodule
