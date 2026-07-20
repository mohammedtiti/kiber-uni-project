`timescale 1ns/1ps

module tb_ntt_3ram_core_signoff;

  localparam int Q = 3329;
  localparam int K2 = 169;
  localparam int AW = 8;
  localparam int DW = 12;
  localparam int N = 256;
  localparam int CASE_COUNT = 10;
  localparam int EXPECTED_CORE_CYCLES = 10394;
  localparam int EXPECTED_A_WRITE_CYCLES = 512;
  localparam int EXPECTED_B_WRITE_CYCLES = 256;
  localparam int EXPECTED_C_WRITE_CYCLES = 896;
  localparam int EXPECTED_C_BF_WRITE_CYCLES = 768;
  localparam int EXPECTED_MUL_WRITE_CYCLES = 128;

  localparam [1:0] RAM_A = 2'd0;
  localparam [1:0] RAM_B = 2'd1;
  localparam [1:0] RAM_C = 2'd2;

  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg              rst;
  reg              start;
  reg              load_en;
  reg [1:0]        load_ram_sel;
  reg [AW-1:0]     load_addr0;
  reg [AW-1:0]     load_addr1;
  reg [DW-1:0]     load_data0;
  reg [DW-1:0]     load_data1;
  reg              host_rd_en;
  reg [1:0]        host_rd_ram_sel;
  reg [AW-1:0]     host_rd_addr0;
  reg [AW-1:0]     host_rd_addr1;
  wire             busy;
  wire             done;
  wire             error;
  wire [2:0]       phase_dbg;
  wire [1:0]       pass_dbg;
  wire [6:0]       op_dbg;
  wire [DW-1:0]    ram_rd0;
  wire [DW-1:0]    ram_rd1;
  wire [DW-1:0]    mul_out0;
  wire [DW-1:0]    mul_out1;

  reg [11:0] rom [0:127];
  reg [11:0] input_a [0:N-1];
  reg [11:0] input_b [0:N-1];
  reg [11:0] ref_a [0:N-1];
  reg [11:0] ref_b [0:N-1];
  reg [11:0] ref_c [0:N-1];
  reg [11:0] tmp_a [0:N-1];
  reg [11:0] tmp_b [0:N-1];
  reg [11:0] tmp_c [0:N-1];

  integer current_case;
  integer total_cases_passed;
  integer monitor_core;
  integer done_pulse_count;
  integer conflict_count;
  integer x_write_count;
  integer range_write_count;
  integer core_a_write_cycles;
  integer core_b_write_cycles;
  integer core_c_write_cycles;
  integer core_c_bf_write_cycles;
  integer core_mul_write_cycles;
  integer actual_force_neg_count;
  integer phase_seen [0:4];

  ntt_3ram_core #(
    .AW(AW),
    .DW(DW),
    .TW_AW(7),
    .TW_MEMFILE("kiber_test.srcs/sources_1/imports/Desktop/twiddle_k2red.mem")
  ) dut (
    .clk(clk),
    .rst(rst),
    .start(start),
    .load_en(load_en),
    .load_ram_sel(load_ram_sel),
    .load_addr0(load_addr0),
    .load_addr1(load_addr1),
    .load_data0(load_data0),
    .load_data1(load_data1),
    .host_rd_en(host_rd_en),
    .host_rd_ram_sel(host_rd_ram_sel),
    .host_rd_addr0(host_rd_addr0),
    .host_rd_addr1(host_rd_addr1),
    .busy(busy),
    .done(done),
    .error(error),
    .phase_dbg(phase_dbg),
    .pass_dbg(pass_dbg),
    .op_dbg(op_dbg),
    .ram_rd0(ram_rd0),
    .ram_rd1(ram_rd1),
    .mul_out0(mul_out0),
    .mul_out1(mul_out1)
  );

  task automatic fail(input string msg);
    begin
      $display("FAIL: case=%0d (%s) phase=%0d pass=%0d op=%0d time=%0t : %s",
               current_case, case_name(current_case), phase_dbg, pass_dbg, op_dbg, $time, msg);
      $fatal(1);
    end
  endtask

  task automatic fail_value(input string msg, input int idx, input int got, input int exp);
    begin
      $display("FAIL: case=%0d (%s) idx=%0d got=%0d exp=%0d phase=%0d pass=%0d op=%0d time=%0t : %s",
               current_case, case_name(current_case), idx, got, exp,
               phase_dbg, pass_dbg, op_dbg, $time, msg);
      $fatal(1);
    end
  endtask

  function automatic string case_name(input integer case_i);
    begin
      case (case_i)
        0: case_name = "zero_zero";
        1: case_name = "impulse_impulse";
        2: case_name = "ones_and_qminus1";
        3: case_name = "alternating_edges";
        4: case_name = "ramp_quadratic";
        5: case_name = "sparse_mixed";
        6: case_name = "high_product_stress";
        7: case_name = "lcg_seed_1";
        8: case_name = "lcg_seed_2";
        default: case_name = "lcg_seed_3";
      endcase
    end
  endfunction

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

  function automatic [11:0] lcg_coeff(input integer case_i, input integer idx, input bit is_b);
    int unsigned x;
    integer k;
    begin
      x = 32'h9e3779b9 ^ (case_i * 32'h45d9f3b) ^ (idx * 32'h119de1f3);
      if (is_b) x = x ^ 32'h7f4a7c15;
      for (k = 0; k < 4; k = k + 1) begin
        x = (x * 32'd1664525) + 32'd1013904223;
      end
      lcg_coeff = x % Q;
    end
  endfunction

  function automatic [11:0] coeff_pattern(input integer case_i, input integer idx, input bit is_b);
    int unsigned v;
    begin
      case (case_i)
        0: v = 0;
        1: v = (idx == 0) ? 1 : 0;
        2: v = is_b ? (Q - 1) : 1;
        3: v = is_b ? ((idx[0]) ? (Q - 1) : 0) :
                       ((idx[0]) ? 0 : (Q - 1));
        4: v = is_b ? ((idx * idx) + (5 * idx) + 11) % Q :
                       ((idx * 17) + 9) % Q;
        5: begin
          if (is_b)
            v = ((idx == 3) || (idx == 64) || (idx == 129) || (idx == 250)) ?
                ((idx * 37) + 19) % Q : 0;
          else
            v = ((idx == 0) || (idx == 1) || (idx == 2) ||
                 (idx == 127) || (idx == 128) || (idx == 255)) ?
                ((idx * 91) + 7) % Q : 0;
        end
        6: v = is_b ? ((Q - 1) - ((idx * 29) % Q)) :
                       ((Q - 1) - ((idx * idx + 13) % Q));
        default: v = lcg_coeff(case_i, idx, is_b);
      endcase
      coeff_pattern = v % Q;
    end
  endfunction

  function automatic [11:0] c_sentinel(input integer case_i, input integer idx);
    int unsigned v;
    begin
      v = (case_i * 257 + idx * 31 + 123) % Q;
      c_sentinel = v[11:0];
    end
  endfunction

  function automatic [7:0] calc_addr(input [1:0] pass_i, input [5:0] op_i,
                                     input [1:0] lane_i, input bit intt_i);
    reg [1:0] eff_pass;
    reg [7:0] base;
    begin
      eff_pass = intt_i ? (2'd3 - pass_i) : pass_i;
      case (eff_pass)
        2'd0: base = {2'b00, op_i};
        2'd1: base = {op_i[5:4], 6'b000000} + {4'b0000, op_i[3:0]};
        2'd2: base = {op_i[5:2], 4'b0000} + {6'b000000, op_i[1:0]};
        default: base = {op_i, 2'b00};
      endcase

      case (eff_pass)
        2'd0: calc_addr = base + ({6'b000000, lane_i} << 6);
        2'd1: calc_addr = base + ({6'b000000, lane_i} << 4);
        2'd2: calc_addr = base + ({6'b000000, lane_i} << 2);
        default: calc_addr = base + {6'b000000, lane_i};
      endcase
    end
  endfunction

  function automatic [6:0] tw_addr(input bit intt_i, input [1:0] pass_i,
                                   input [5:0] op_i, input [4:0] offset_i);
    reg [7:0] addr;
    reg [1:0] eff_pass;
    reg [7:0] len;
    reg [7:0] j;
    reg [7:0] exp;
    begin
      eff_pass = intt_i ? (2'd3 - pass_i) : pass_i;

      if (offset_i == 5'd0 || offset_i == 5'd1) begin
        addr = (offset_i == 5'd0) ? calc_addr(pass_i, op_i, 2'd0, intt_i) :
                                    calc_addr(pass_i, op_i, intt_i ? 2'd2 : 2'd1, intt_i);
        case (eff_pass)
          2'd0: len = 8'd128;
          2'd1: len = 8'd32;
          2'd2: len = 8'd8;
          default: len = 8'd2;
        endcase
        j = addr & (len - 1);
        exp = j << (2*eff_pass);
      end else begin
        addr = (offset_i == 5'd16) ? calc_addr(pass_i, op_i, 2'd0, intt_i) :
                                     calc_addr(pass_i, op_i, intt_i ? 2'd1 : 2'd2, intt_i);
        case (eff_pass)
          2'd0: len = 8'd64;
          2'd1: len = 8'd16;
          2'd2: len = 8'd4;
          default: len = 8'd1;
        endcase
        j = (len == 1) ? 8'd0 : (addr & (len - 1));
        exp = j << ((2*eff_pass) + 1);
      end

      if (intt_i && exp != 0)
        tw_addr = 8'd128 - exp;
      else
        tw_addr = exp[6:0];
    end
  endfunction

  function automatic tw_force_neg_one(input bit intt_i, input [1:0] pass_i,
                                      input [5:0] op_i, input [4:0] offset_i);
    reg [7:0] addr;
    reg [1:0] eff_pass;
    reg [7:0] len;
    reg [7:0] j;
    reg [7:0] exp;
    begin
      eff_pass = intt_i ? (2'd3 - pass_i) : pass_i;

      if (offset_i == 5'd0 || offset_i == 5'd1) begin
        addr = (offset_i == 5'd0) ? calc_addr(pass_i, op_i, 2'd0, intt_i) :
                                    calc_addr(pass_i, op_i, intt_i ? 2'd2 : 2'd1, intt_i);
        case (eff_pass)
          2'd0: len = 8'd128;
          2'd1: len = 8'd32;
          2'd2: len = 8'd8;
          default: len = 8'd2;
        endcase
        j = addr & (len - 1);
        exp = j << (2*eff_pass);
      end else begin
        addr = (offset_i == 5'd16) ? calc_addr(pass_i, op_i, 2'd0, intt_i) :
                                     calc_addr(pass_i, op_i, intt_i ? 2'd1 : 2'd2, intt_i);
        case (eff_pass)
          2'd0: len = 8'd64;
          2'd1: len = 8'd16;
          2'd2: len = 8'd4;
          default: len = 8'd1;
        endcase
        j = (len == 1) ? 8'd0 : (addr & (len - 1));
        exp = j << ((2*eff_pass) + 1);
      end

      tw_force_neg_one = intt_i && (exp == 0);
    end
  endfunction

  function automatic [11:0] tw_value(input bit intt_i, input [1:0] pass_i,
                                     input [5:0] op_i, input [4:0] offset_i);
    begin
      tw_value = tw_force_neg_one(intt_i, pass_i, op_i, offset_i) ?
                 12'd1044 : rom[tw_addr(intt_i, pass_i, op_i, offset_i)];
    end
  endfunction

  function automatic integer expected_force_neg_count;
    integer pass;
    integer op;
    integer total;
    begin
      total = 0;
      for (pass = 0; pass < 4; pass = pass + 1) begin
        for (op = 0; op < 64; op = op + 1) begin
          total = total + tw_force_neg_one(1'b1, pass[1:0], op[5:0], 5'd0);
          total = total + tw_force_neg_one(1'b1, pass[1:0], op[5:0], 5'd1);
          total = total + tw_force_neg_one(1'b1, pass[1:0], op[5:0], 5'd16);
          total = total + tw_force_neg_one(1'b1, pass[1:0], op[5:0], 5'd17);
        end
      end
      expected_force_neg_count = total;
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

  task automatic run_reference_transform(input bit intt_i, input integer phase_i);
    integer pass;
    integer op;
    integer i;
    reg [7:0] a0, a1, a2, a3;
    reg [11:0] e0, e1, e2, e3;
    reg [11:0] s0, s1, s2, s3;
    begin
      for (pass = 0; pass < 4; pass = pass + 1) begin
        for (i = 0; i < N; i = i + 1) begin
          tmp_a[i] = ref_a[i];
          tmp_b[i] = ref_b[i];
          tmp_c[i] = ref_c[i];
        end

        for (op = 0; op < 64; op = op + 1) begin
          a0 = calc_addr(pass[1:0], op[5:0], 2'd0, intt_i);
          a1 = calc_addr(pass[1:0], op[5:0], 2'd1, intt_i);
          a2 = calc_addr(pass[1:0], op[5:0], 2'd2, intt_i);
          a3 = calc_addr(pass[1:0], op[5:0], 2'd3, intt_i);

          if (phase_i == 0) begin
            if (pass[0]) begin
              s0 = tmp_c[a0]; s1 = tmp_c[a1]; s2 = tmp_c[a2]; s3 = tmp_c[a3];
            end else begin
              s0 = tmp_a[a0]; s1 = tmp_a[a1]; s2 = tmp_a[a2]; s3 = tmp_a[a3];
            end
          end else if (phase_i == 1) begin
            if (pass[0]) begin
              s0 = tmp_c[a0]; s1 = tmp_c[a1]; s2 = tmp_c[a2]; s3 = tmp_c[a3];
            end else begin
              s0 = tmp_b[a0]; s1 = tmp_b[a1]; s2 = tmp_b[a2]; s3 = tmp_b[a3];
            end
          end else begin
            if (pass[0]) begin
              s0 = tmp_a[a0]; s1 = tmp_a[a1]; s2 = tmp_a[a2]; s3 = tmp_a[a3];
            end else begin
              s0 = tmp_c[a0]; s1 = tmp_c[a1]; s2 = tmp_c[a2]; s3 = tmp_c[a3];
            end
          end

          block_ref(intt_i, s0, s1, s2, s3,
                    tw_value(intt_i, pass[1:0], op[5:0], 5'd0),
                    tw_value(intt_i, pass[1:0], op[5:0], 5'd1),
                    tw_value(intt_i, pass[1:0], op[5:0], 5'd16),
                    tw_value(intt_i, pass[1:0], op[5:0], 5'd17),
                    e0, e1, e2, e3);

          if (phase_i == 0) begin
            if (pass[0]) begin
              ref_a[a0] = e0; ref_a[a1] = e1; ref_a[a2] = e2; ref_a[a3] = e3;
            end else begin
              ref_c[a0] = e0; ref_c[a1] = e1; ref_c[a2] = e2; ref_c[a3] = e3;
            end
          end else if (phase_i == 1) begin
            if (pass[0]) begin
              ref_b[a0] = e0; ref_b[a1] = e1; ref_b[a2] = e2; ref_b[a3] = e3;
            end else begin
              ref_c[a0] = e0; ref_c[a1] = e1; ref_c[a2] = e2; ref_c[a3] = e3;
            end
          end else begin
            if (pass[0]) begin
              ref_c[a0] = e0; ref_c[a1] = e1; ref_c[a2] = e2; ref_c[a3] = e3;
            end else begin
              ref_a[a0] = e0; ref_a[a1] = e1; ref_a[a2] = e2; ref_a[a3] = e3;
            end
          end
        end
      end
    end
  endtask

  task automatic compute_reference;
    integer i;
    begin
      for (i = 0; i < N; i = i + 1) begin
        ref_a[i] = input_a[i];
        ref_b[i] = input_b[i];
        ref_c[i] = 12'd0;
      end

      run_reference_transform(1'b0, 0);
      run_reference_transform(1'b0, 1);
      for (i = 0; i < N; i = i + 1) begin
        ref_c[i] = mul_mod_q(ref_a[i], ref_b[i]);
      end
      run_reference_transform(1'b1, 2);
    end
  endtask

  task automatic check_rom_contract;
    integer i;
    integer expected;
    integer coverage [0:N-1];
    integer pass;
    integer op;
    integer lane;
    integer addr;
    begin
      expected = 2285;
      for (i = 0; i < 128; i = i + 1) begin
        if (rom[i] !== expected[11:0])
          fail_value("ROM is not k^-2*17^i mod q", i, rom[i], expected);
        expected = (expected * 17) % Q;
      end

      if (((K2 * rom[0]) % Q) != 1)
        fail("ROM[0] does not cancel K2RED scaling");
      if (((K2 * 1044) % Q) != (Q - 1))
        fail("-k^-2 override constant 1044 does not reduce to -1");

      for (pass = 0; pass < 4; pass = pass + 1) begin
        for (i = 0; i < N; i = i + 1)
          coverage[i] = 0;
        for (op = 0; op < 64; op = op + 1) begin
          for (lane = 0; lane < 4; lane = lane + 1) begin
            addr = calc_addr(pass[1:0], op[5:0], lane[1:0], 1'b0);
            coverage[addr] = coverage[addr] + 1;
          end
        end
        for (i = 0; i < N; i = i + 1) begin
          if (coverage[i] != 1)
            fail_value("NTT address coverage is not exactly once per pass", i, coverage[i], 1);
        end

        for (i = 0; i < N; i = i + 1)
          coverage[i] = 0;
        for (op = 0; op < 64; op = op + 1) begin
          for (lane = 0; lane < 4; lane = lane + 1) begin
            addr = calc_addr(pass[1:0], op[5:0], lane[1:0], 1'b1);
            coverage[addr] = coverage[addr] + 1;
          end
        end
        for (i = 0; i < N; i = i + 1) begin
          if (coverage[i] != 1)
            fail_value("INTT address coverage is not exactly once per pass", i, coverage[i], 1);
        end
      end
    end
  endtask

  task automatic load_pair(input [1:0] ram_sel, input [7:0] addr0, input [7:0] addr1,
                           input [11:0] data0, input [11:0] data1);
    begin
      @(negedge clk);
      load_en = 1'b1;
      load_ram_sel = ram_sel;
      load_addr0 = addr0;
      load_addr1 = addr1;
      load_data0 = data0;
      load_data1 = data1;
      @(posedge clk);
      @(negedge clk);
      load_en = 1'b0;
    end
  endtask

  task automatic read_pair(input [1:0] ram_sel, input [7:0] addr0, input [7:0] addr1,
                           output [11:0] data0, output [11:0] data1);
    begin
      @(negedge clk);
      host_rd_en = 1'b1;
      host_rd_ram_sel = ram_sel;
      host_rd_addr0 = addr0;
      host_rd_addr1 = addr1;
      @(posedge clk);
      @(posedge clk);
      #1;
      data0 = ram_rd0;
      data1 = ram_rd1;
      @(negedge clk);
      host_rd_en = 1'b0;
    end
  endtask

  task automatic apply_reset;
    begin
      @(negedge clk);
      rst = 1'b1;
      start = 1'b0;
      load_en = 1'b0;
      host_rd_en = 1'b0;
      monitor_core = 0;
      repeat (5) @(posedge clk);
      @(negedge clk);
      rst = 1'b0;
    end
  endtask

  task automatic reset_run_counters;
    integer p;
    begin
      done_pulse_count = 0;
      conflict_count = 0;
      x_write_count = 0;
      range_write_count = 0;
      core_a_write_cycles = 0;
      core_b_write_cycles = 0;
      core_c_write_cycles = 0;
      core_c_bf_write_cycles = 0;
      core_mul_write_cycles = 0;
      actual_force_neg_count = 0;
      for (p = 0; p < 5; p = p + 1)
        phase_seen[p] = 0;
    end
  endtask

  task automatic fill_inputs(input integer case_i);
    integer i;
    begin
      for (i = 0; i < N; i = i + 1) begin
        input_a[i] = coeff_pattern(case_i, i, 1'b0);
        input_b[i] = coeff_pattern(case_i, i, 1'b1);
      end
    end
  endtask

  task automatic load_and_verify_inputs(input integer case_i);
    integer pair;
    integer addr;
    reg [11:0] got0, got1;
    begin
      for (pair = 0; pair < 128; pair = pair + 1) begin
        addr = pair * 2;
        load_pair(RAM_C, addr[7:0], (addr + 1), c_sentinel(case_i, addr),
                  c_sentinel(case_i, addr + 1));
        load_pair(RAM_A, addr[7:0], (addr + 1), input_a[addr], input_a[addr + 1]);
        load_pair(RAM_B, addr[7:0], (addr + 1), input_b[addr], input_b[addr + 1]);
      end

      for (pair = 0; pair < 128; pair = pair + 1) begin
        addr = pair * 2;
        read_pair(RAM_A, addr[7:0], (addr + 1), got0, got1);
        if (got0 !== input_a[addr])
          fail_value("host readback mismatch after loading RAM A port0", addr, got0, input_a[addr]);
        if (got1 !== input_a[addr + 1])
          fail_value("host readback mismatch after loading RAM A port1", addr + 1, got1, input_a[addr + 1]);

        read_pair(RAM_B, addr[7:0], (addr + 1), got0, got1);
        if (got0 !== input_b[addr])
          fail_value("host readback mismatch after loading RAM B port0", addr, got0, input_b[addr]);
        if (got1 !== input_b[addr + 1])
          fail_value("host readback mismatch after loading RAM B port1", addr + 1, got1, input_b[addr + 1]);

        read_pair(RAM_C, addr[7:0], (addr + 1), got0, got1);
        if (got0 !== c_sentinel(case_i, addr))
          fail_value("host readback mismatch after loading RAM C port0", addr, got0, c_sentinel(case_i, addr));
        if (got1 !== c_sentinel(case_i, addr + 1))
          fail_value("host readback mismatch after loading RAM C port1", addr + 1, got1, c_sentinel(case_i, addr + 1));
      end
    end
  endtask

  task automatic run_core(output integer cycles);
    begin
      @(negedge clk);
      monitor_core = 1;
      start = 1'b1;
      @(posedge clk);
      @(negedge clk);
      start = 1'b0;

      cycles = 0;
      while (!done && !error && cycles < 20000) begin
        @(posedge clk);
        cycles = cycles + 1;
      end

      if (error)
        fail("core asserted error");
      if (!done)
        fail("core timed out before done");
      if (busy !== 1'b0)
        fail("busy was not low on the done cycle");
      if (cycles != EXPECTED_CORE_CYCLES)
        fail_value("unexpected FSM cycle count", 0, cycles, EXPECTED_CORE_CYCLES);

      @(posedge clk);
      #1;
      if (done !== 1'b0)
        fail("done did not deassert after one cycle");
      monitor_core = 0;
    end
  endtask

  task automatic check_run_counters;
    integer exp_force;
    integer p;
    begin
      exp_force = expected_force_neg_count();
      if (done_pulse_count != 1)
        fail_value("done pulse count mismatch", 0, done_pulse_count, 1);
      if (conflict_count != 0)
        fail_value("ram_conflict pulse count mismatch", 0, conflict_count, 0);
      if (x_write_count != 0)
        fail_value("X write count mismatch", 0, x_write_count, 0);
      if (range_write_count != 0)
        fail_value("out-of-field write count mismatch", 0, range_write_count, 0);
      if (core_a_write_cycles != EXPECTED_A_WRITE_CYCLES)
        fail_value("RAM A core write-cycle count mismatch", 0, core_a_write_cycles, EXPECTED_A_WRITE_CYCLES);
      if (core_b_write_cycles != EXPECTED_B_WRITE_CYCLES)
        fail_value("RAM B core write-cycle count mismatch", 0, core_b_write_cycles, EXPECTED_B_WRITE_CYCLES);
      if (core_c_write_cycles != EXPECTED_C_WRITE_CYCLES)
        fail_value("RAM C core write-cycle count mismatch", 0, core_c_write_cycles, EXPECTED_C_WRITE_CYCLES);
      if (core_c_bf_write_cycles != EXPECTED_C_BF_WRITE_CYCLES)
        fail_value("RAM C butterfly write-cycle count mismatch", 0, core_c_bf_write_cycles, EXPECTED_C_BF_WRITE_CYCLES);
      if (core_mul_write_cycles != EXPECTED_MUL_WRITE_CYCLES)
        fail_value("pointwise multiply write-cycle count mismatch", 0, core_mul_write_cycles, EXPECTED_MUL_WRITE_CYCLES);
      if (actual_force_neg_count != exp_force)
        fail_value("INTT -k^-2 force count mismatch", 0, actual_force_neg_count, exp_force);

      for (p = 0; p < 5; p = p + 1) begin
        if (phase_seen[p] == 0)
          fail_value("FSM phase was not observed", p, 0, 1);
      end
    end
  endtask

  task automatic check_final_rams;
    integer pair;
    integer i;
    integer addr;
    reg [11:0] got0, got1;
    begin
      for (i = 0; i < N; i = i + 1) begin
        if (dut.u_datapath.u_ram_a.ram[i] !== ref_a[i])
          fail_value("direct final RAM A mismatch", i, dut.u_datapath.u_ram_a.ram[i], ref_a[i]);
        if (dut.u_datapath.u_ram_b.ram[i] !== ref_b[i])
          fail_value("direct final RAM B mismatch", i, dut.u_datapath.u_ram_b.ram[i], ref_b[i]);
        if (dut.u_datapath.u_ram_c.ram[i] !== ref_c[i])
          fail_value("direct final RAM C mismatch", i, dut.u_datapath.u_ram_c.ram[i], ref_c[i]);
      end

      for (pair = 0; pair < 128; pair = pair + 1) begin
        addr = pair * 2;
        read_pair(RAM_A, addr[7:0], (addr + 1), got0, got1);
        if (got0 !== ref_a[addr])
          fail_value("host final RAM A mismatch port0", addr, got0, ref_a[addr]);
        if (got1 !== ref_a[addr + 1])
          fail_value("host final RAM A mismatch port1", addr + 1, got1, ref_a[addr + 1]);

        read_pair(RAM_B, addr[7:0], (addr + 1), got0, got1);
        if (got0 !== ref_b[addr])
          fail_value("host final RAM B mismatch port0", addr, got0, ref_b[addr]);
        if (got1 !== ref_b[addr + 1])
          fail_value("host final RAM B mismatch port1", addr + 1, got1, ref_b[addr + 1]);

        read_pair(RAM_C, addr[7:0], (addr + 1), got0, got1);
        if (got0 !== ref_c[addr])
          fail_value("host final RAM C mismatch port0", addr, got0, ref_c[addr]);
        if (got1 !== ref_c[addr + 1])
          fail_value("host final RAM C mismatch port1", addr + 1, got1, ref_c[addr + 1]);
      end
    end
  endtask

  task automatic check_write_port(input string ram_name, input bit we, input [AW-1:0] addr,
                                  input [DW-1:0] data);
    begin
      if (we) begin
        if ((^addr === 1'bx) || (^data === 1'bx)) begin
          x_write_count = x_write_count + 1;
          $display("DEBUG: X write ram=%s addr=%b data=%b time=%0t", ram_name, addr, data, $time);
        end else if (data >= Q) begin
          range_write_count = range_write_count + 1;
          $display("DEBUG: out-of-field write ram=%s addr=%0d data=%0d time=%0t", ram_name, addr, data, $time);
        end
      end
    end
  endtask

  always @(posedge clk) begin
    if (!rst) begin
      check_write_port("A.a", dut.u_datapath.u_ram_a.we_a,
                       dut.u_datapath.u_ram_a.addr_a, dut.u_datapath.u_ram_a.din_a);
      check_write_port("A.b", dut.u_datapath.u_ram_a.we_b,
                       dut.u_datapath.u_ram_a.addr_b, dut.u_datapath.u_ram_a.din_b);
      check_write_port("B.a", dut.u_datapath.u_ram_b.we_a,
                       dut.u_datapath.u_ram_b.addr_a, dut.u_datapath.u_ram_b.din_a);
      check_write_port("B.b", dut.u_datapath.u_ram_b.we_b,
                       dut.u_datapath.u_ram_b.addr_b, dut.u_datapath.u_ram_b.din_b);
      check_write_port("C.a", dut.u_datapath.u_ram_c.we_a,
                       dut.u_datapath.u_ram_c.addr_a, dut.u_datapath.u_ram_c.din_a);
      check_write_port("C.b", dut.u_datapath.u_ram_c.we_b,
                       dut.u_datapath.u_ram_c.addr_b, dut.u_datapath.u_ram_c.din_b);

      if (dut.ram_conflict === 1'b1)
        conflict_count = conflict_count + 1;
      if (^dut.ram_conflict === 1'bx)
        fail("ram_conflict became X");

      if (monitor_core) begin
        if (done)
          done_pulse_count = done_pulse_count + 1;
        if (phase_dbg <= 3'd4)
          phase_seen[phase_dbg] = 1;
        if (dut.u_datapath.a_selected_for_write)
          core_a_write_cycles = core_a_write_cycles + 1;
        if (dut.u_datapath.b_selected_for_write)
          core_b_write_cycles = core_b_write_cycles + 1;
        if (dut.u_datapath.u_ram_c.we_a || dut.u_datapath.u_ram_c.we_b)
          core_c_write_cycles = core_c_write_cycles + 1;
        if (dut.u_datapath.c_selected_for_write)
          core_c_bf_write_cycles = core_c_bf_write_cycles + 1;
        if (dut.u_datapath.mul_write_allowed)
          core_mul_write_cycles = core_mul_write_cycles + 1;
        if (dut.f_tw_load) begin
          if (!dut.f_mode_in &&
              (dut.f_tw_force_neg_s0_b0 || dut.f_tw_force_neg_s0_b1 ||
               dut.f_tw_force_neg_s1_b0 || dut.f_tw_force_neg_s1_b1))
            fail("force-negative twiddle asserted during NTT");
          actual_force_neg_count = actual_force_neg_count +
                                   dut.f_tw_force_neg_s0_b0 +
                                   dut.f_tw_force_neg_s0_b1 +
                                   dut.f_tw_force_neg_s1_b0 +
                                   dut.f_tw_force_neg_s1_b1;
        end
      end
    end
  end

  initial begin
    integer case_i;
    integer cycles;

    current_case = -1;
    total_cases_passed = 0;
    monitor_core = 0;
    rst = 1'b1;
    start = 1'b0;
    load_en = 1'b0;
    load_ram_sel = 2'd0;
    load_addr0 = 0;
    load_addr1 = 0;
    load_data0 = 0;
    load_data1 = 0;
    host_rd_en = 1'b0;
    host_rd_ram_sel = 2'd0;
    host_rd_addr0 = 0;
    host_rd_addr1 = 0;
    reset_run_counters();

    $readmemh("kiber_test.srcs/sources_1/imports/Desktop/twiddle_k2red.mem", rom);
    check_rom_contract();

    for (case_i = 0; case_i < CASE_COUNT; case_i = case_i + 1) begin
      current_case = case_i;
      $display("INFO: starting signoff case %0d (%s)", current_case, case_name(current_case));

      reset_run_counters();
      fill_inputs(current_case);
      compute_reference();
      apply_reset();
      load_and_verify_inputs(current_case);
      run_core(cycles);
      check_run_counters();
      check_final_rams();

      total_cases_passed = total_cases_passed + 1;
      $display("PASS: case %0d (%s) matched reference. cycles=%0d force_neg_count=%0d",
               current_case, case_name(current_case), cycles, actual_force_neg_count);
    end

    $display("PASS: signoff test completed %0d/%0d cases. Full datapath/control/ROM checks passed.",
             total_cases_passed, CASE_COUNT);
    $finish;
  end

  initial begin
    #20000000;
    $display("TIMEOUT: signoff simulation did not finish.");
    $fatal(1);
  end

endmodule
