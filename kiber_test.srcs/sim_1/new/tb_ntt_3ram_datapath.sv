`timescale 1ns/1ps

module tb_ntt_3ram_datapath;

  localparam int Q = 3329;
  localparam int K2 = 169;
  localparam int AW = 8;
  localparam int DW = 12;

  localparam [1:0] RAM_A = 2'd0;
  localparam [1:0] RAM_B = 2'd1;
  localparam [1:0] RAM_C = 2'd2;

  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg              rst;
  reg              mode_in;
  reg              rd_en;
  reg [1:0]        rd_src_sel;
  reg [AW-1:0]     rd_addr0;
  reg [AW-1:0]     rd_addr1;
  reg              rd_capture_en;
  reg              rd_capture_sel;
  reg              wr_en;
  reg [1:0]        wr_dst_sel;
  reg [AW-1:0]     wr_addr0;
  reg [AW-1:0]     wr_addr1;
  reg              wr_result_sel;
  reg              wr_use_ext;
  reg [DW-1:0]     wr_ext0;
  reg [DW-1:0]     wr_ext1;
  reg              mul_rd_en;
  reg              mul_wr_en;
  reg [AW-1:0]     mul_addr0;
  reg [AW-1:0]     mul_addr1;
  wire             mul_valid;
  wire [DW-1:0]    mul_out0;
  wire [DW-1:0]    mul_out1;
  reg [6:0]        tw_addr_s0_b0;
  reg [6:0]        tw_addr_s0_b1;
  reg [6:0]        tw_addr_s1_b0;
  reg [6:0]        tw_addr_s1_b1;
  reg              tw_load;
  reg              bf_start;
  wire             bf_valid;
  wire [DW-1:0]    coeff0;
  wire [DW-1:0]    coeff1;
  wire [DW-1:0]    coeff2;
  wire [DW-1:0]    coeff3;
  wire [DW-1:0]    bf_out0;
  wire [DW-1:0]    bf_out1;
  wire [DW-1:0]    bf_out2;
  wire [DW-1:0]    bf_out3;
  wire [DW-1:0]    ram_rd0;
  wire [DW-1:0]    ram_rd1;
  wire             ram_conflict;

  ntt_3ram_datapath #(
    .AW(AW),
    .DW(DW),
    .TW_AW(7),
    .TW_MEMFILE("kiber_test.srcs/sources_1/imports/Desktop/twiddle_k2red.mem")
  ) dut (
    .clk(clk),
    .rst(rst),
    .mode_in(mode_in),
    .rd_en(rd_en),
    .rd_src_sel(rd_src_sel),
    .rd_addr0(rd_addr0),
    .rd_addr1(rd_addr1),
    .rd_capture_en(rd_capture_en),
    .rd_capture_sel(rd_capture_sel),
    .wr_en(wr_en),
    .wr_dst_sel(wr_dst_sel),
    .wr_addr0(wr_addr0),
    .wr_addr1(wr_addr1),
    .wr_result_sel(wr_result_sel),
    .wr_use_ext(wr_use_ext),
    .wr_ext0(wr_ext0),
    .wr_ext1(wr_ext1),
    .mul_rd_en(mul_rd_en),
    .mul_wr_en(mul_wr_en),
    .mul_addr0(mul_addr0),
    .mul_addr1(mul_addr1),
    .mul_valid(mul_valid),
    .mul_out0(mul_out0),
    .mul_out1(mul_out1),
    .tw_addr_s0_b0(tw_addr_s0_b0),
    .tw_addr_s0_b1(tw_addr_s0_b1),
    .tw_addr_s1_b0(tw_addr_s1_b0),
    .tw_addr_s1_b1(tw_addr_s1_b1),
    .tw_force_neg_s0_b0(1'b0),
    .tw_force_neg_s0_b1(1'b0),
    .tw_force_neg_s1_b0(1'b0),
    .tw_force_neg_s1_b1(1'b0),
    .tw_load(tw_load),
    .bf_start(bf_start),
    .bf_valid(bf_valid),
    .coeff0(coeff0),
    .coeff1(coeff1),
    .coeff2(coeff2),
    .coeff3(coeff3),
    .bf_out0(bf_out0),
    .bf_out1(bf_out1),
    .bf_out2(bf_out2),
    .bf_out3(bf_out3),
    .ram_rd0(ram_rd0),
    .ram_rd1(ram_rd1),
    .ram_conflict(ram_conflict)
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

  function automatic [11:0] mul_mod_q(input [11:0] a, input [11:0] b);
    int unsigned modv;
    begin
      modv = (int'(a) * int'(b)) % Q;
      mul_mod_q = modv[11:0];
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

  task automatic clear_controls;
    begin
      rd_en = 0;
      rd_src_sel = 0;
      rd_addr0 = 0;
      rd_addr1 = 0;
      rd_capture_en = 0;
      rd_capture_sel = 0;
      wr_en = 0;
      wr_dst_sel = 0;
      wr_addr0 = 0;
      wr_addr1 = 0;
      wr_result_sel = 0;
      wr_use_ext = 0;
      wr_ext0 = 0;
      wr_ext1 = 0;
      mul_rd_en = 0;
      mul_wr_en = 0;
      mul_addr0 = 0;
      mul_addr1 = 0;
      tw_addr_s0_b0 = 0;
      tw_addr_s0_b1 = 0;
      tw_addr_s1_b0 = 0;
      tw_addr_s1_b1 = 0;
      tw_load = 0;
      bf_start = 0;
    end
  endtask

  task automatic write_pair_ext(input [1:0] dst, input [7:0] addr0, input [7:0] addr1,
                                input [11:0] data0, input [11:0] data1);
    begin
      @(negedge clk);
      wr_en = 1;
      wr_dst_sel = dst;
      wr_addr0 = addr0;
      wr_addr1 = addr1;
      wr_use_ext = 1;
      wr_ext0 = data0;
      wr_ext1 = data1;
      @(posedge clk);
      #1;
      if (ram_conflict) begin
        $display("FAIL: unexpected ram_conflict during external write.");
        $stop;
      end
      @(negedge clk);
      wr_en = 0;
      wr_use_ext = 0;
    end
  endtask

  task automatic read_pair(input [1:0] src, input [7:0] addr0, input [7:0] addr1,
                           output [11:0] data0, output [11:0] data1);
    begin
      @(negedge clk);
      rd_en = 1;
      rd_src_sel = src;
      rd_addr0 = addr0;
      rd_addr1 = addr1;
      @(posedge clk);
      #1;
      data0 = ram_rd0;
      data1 = ram_rd1;
      @(negedge clk);
      rd_en = 0;
    end
  endtask

  task automatic capture_pair(input [1:0] src, input [7:0] addr0, input [7:0] addr1,
                              input bit high_pair);
    begin
      @(negedge clk);
      rd_en = 1;
      rd_src_sel = src;
      rd_addr0 = addr0;
      rd_addr1 = addr1;
      @(posedge clk);
      @(negedge clk);
      rd_en = 0;
      rd_capture_en = 1;
      rd_capture_sel = high_pair;
      @(posedge clk);
      @(negedge clk);
      rd_capture_en = 0;
    end
  endtask

  task automatic multiply_pair(input [7:0] addr0, input [7:0] addr1,
                               input [11:0] exp0, input [11:0] exp1);
    reg [11:0] c0, c1;
    begin
      @(negedge clk);
      mul_rd_en = 1;
      mul_addr0 = addr0;
      mul_addr1 = addr1;
      @(posedge clk);
      #1;
      if (!mul_valid) begin
        $display("FAIL: mul_valid did not assert after mul_rd_en.");
        $stop;
      end
      if (mul_out0 !== exp0 || mul_out1 !== exp1) begin
        $display("FAIL: mul_out mismatch at addrs %0d/%0d got=%0d,%0d exp=%0d,%0d",
                 addr0, addr1, mul_out0, mul_out1, exp0, exp1);
        $stop;
      end

      @(negedge clk);
      mul_rd_en = 0;
      mul_wr_en = 1;
      mul_addr0 = addr0;
      mul_addr1 = addr1;
      @(posedge clk);
      @(negedge clk);
      mul_wr_en = 0;

      read_pair(RAM_C, addr0, addr1, c0, c1);
      if (c0 !== exp0 || c1 !== exp1) begin
        $display("FAIL: RAM C multiply result mismatch at addrs %0d/%0d got=%0d,%0d exp=%0d,%0d",
                 addr0, addr1, c0, c1, exp0, exp1);
        $stop;
      end
    end
  endtask

  task automatic run_butterfly_writeback_ntt;
    reg [11:0] e0, e1, e2, e3;
    reg [11:0] r0, r1;
    begin
      capture_pair(RAM_A, 8'd0, 8'd1, 1'b0);
      capture_pair(RAM_A, 8'd2, 8'd3, 1'b1);

      // ROM entries 0..3 are 0x8ed, 0x8b2, 0x4c7, 0x331.
      @(negedge clk);
      tw_addr_s0_b0 = 7'd0;
      tw_addr_s0_b1 = 7'd1;
      tw_addr_s1_b0 = 7'd2;
      tw_addr_s1_b1 = 7'd3;
      @(posedge clk);
      @(negedge clk);
      tw_load = 1;
      @(posedge clk);
      @(negedge clk);
      tw_load = 0;

      block_ref(1'b0, 12'd1, 12'd2, 12'd3, 12'd4,
                12'h8ed, 12'h8b2, 12'h4c7, 12'h331,
                e0, e1, e2, e3);

      @(negedge clk);
      bf_start = 1;
      @(posedge clk);
      @(negedge clk);
      bf_start = 0;

      wait (bf_valid === 1'b1);
      #1;
      if (bf_out0 !== e0 || bf_out1 !== e1 || bf_out2 !== e2 || bf_out3 !== e3) begin
        $display("FAIL: butterfly datapath mismatch got=%0d,%0d,%0d,%0d exp=%0d,%0d,%0d,%0d",
                 bf_out0, bf_out1, bf_out2, bf_out3, e0, e1, e2, e3);
        $stop;
      end

      @(negedge clk);
      wr_en = 1;
      wr_dst_sel = RAM_C;
      wr_addr0 = 8'd10;
      wr_addr1 = 8'd11;
      wr_result_sel = 0;
      @(posedge clk);
      @(negedge clk);
      wr_result_sel = 1;
      wr_addr0 = 8'd12;
      wr_addr1 = 8'd13;
      @(posedge clk);
      @(negedge clk);
      wr_en = 0;

      read_pair(RAM_C, 8'd10, 8'd11, r0, r1);
      if (r0 !== e0 || r1 !== e1) begin
        $display("FAIL: butterfly writeback low pair got=%0d,%0d exp=%0d,%0d", r0, r1, e0, e1);
        $stop;
      end

      read_pair(RAM_C, 8'd12, 8'd13, r0, r1);
      if (r0 !== e2 || r1 !== e3) begin
        $display("FAIL: butterfly writeback high pair got=%0d,%0d exp=%0d,%0d", r0, r1, e2, e3);
        $stop;
      end
    end
  endtask

  reg [11:0] r0, r1;

  initial begin
    clear_controls();
    mode_in = 1'b0;
    rst = 1'b1;
    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    write_pair_ext(RAM_A, 8'd0, 8'd1, 12'd1,    12'd2);
    write_pair_ext(RAM_A, 8'd2, 8'd3, 12'd3,    12'd4);
    write_pair_ext(RAM_A, 8'd4, 8'd5, 12'd3328, 12'd1234);
    write_pair_ext(RAM_B, 8'd0, 8'd1, 12'd5,    12'd6);
    write_pair_ext(RAM_B, 8'd2, 8'd3, 12'd7,    12'd8);
    write_pair_ext(RAM_B, 8'd4, 8'd5, 12'd2222, 12'd3328);

    read_pair(RAM_A, 8'd0, 8'd1, r0, r1);
    if (r0 !== 12'd1 || r1 !== 12'd2) begin
      $display("FAIL: RAM A readback got=%0d,%0d", r0, r1);
      $stop;
    end

    read_pair(RAM_B, 8'd4, 8'd5, r0, r1);
    if (r0 !== 12'd2222 || r1 !== 12'd3328) begin
      $display("FAIL: RAM B readback got=%0d,%0d", r0, r1);
      $stop;
    end

    multiply_pair(8'd0, 8'd1, mul_mod_q(12'd1, 12'd5),       mul_mod_q(12'd2, 12'd6));
    multiply_pair(8'd2, 8'd3, mul_mod_q(12'd3, 12'd7),       mul_mod_q(12'd4, 12'd8));
    multiply_pair(8'd4, 8'd5, mul_mod_q(12'd3328, 12'd2222), mul_mod_q(12'd1234, 12'd3328));

    run_butterfly_writeback_ntt();

    @(negedge clk);
    rd_en = 1;
    wr_en = 1;
    rd_src_sel = RAM_C;
    wr_dst_sel = RAM_C;
    @(posedge clk);
    #1;
    if (!ram_conflict) begin
      $display("FAIL: ram_conflict did not assert for same-RAM read/write.");
      $stop;
    end
    @(negedge clk);
    rd_en = 0;
    wr_en = 0;

    $display("PASS: ntt_3ram_datapath tests passed.");
    $finish;
  end

  initial begin
    #500000;
    $display("TIMEOUT: simulation did not finish.");
    $finish;
  end

endmodule
