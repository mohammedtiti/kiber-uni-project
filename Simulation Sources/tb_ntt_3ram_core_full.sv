`timescale 1ns/1ps

module tb_ntt_3ram_core_full;

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
  reg [11:0] ref_a [0:255];
  reg [11:0] ref_b [0:255];
  reg [11:0] ref_c [0:255];
  reg [11:0] tmp_a [0:255];
  reg [11:0] tmp_b [0:255];
  reg [11:0] tmp_c [0:255];

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
        for (i = 0; i < 256; i = i + 1) begin
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

  integer i;
  integer check_i;
  integer check_addr;
  integer cycles;
  reg [11:0] got0, got1;
  reg printed_x_write;
  integer c0_write_count;
  integer c_write_count;
  integer fsm_c_write_count;
  integer dp_c_write_count;
  integer selected_c_write_count;

  always @(posedge clk) begin
    if (!rst && !printed_x_write) begin
      if ((dut.u_datapath.u_ram_c.we_a && (^dut.u_datapath.ram_c_din0 === 1'bx)) ||
          (dut.u_datapath.u_ram_c.we_b && (^dut.u_datapath.ram_c_din1 === 1'bx))) begin
        printed_x_write <= 1'b1;
        $display("DEBUG: X write to C at phase=%0d pass=%0d op=%0d we_a=%0d addr_a=%0d din_a=%0d we_b=%0d addr_b=%0d din_b=%0d",
                 phase_dbg, pass_dbg, op_dbg,
                 dut.u_datapath.u_ram_c.we_a,
                 dut.u_datapath.u_ram_c.addr_a,
                 dut.u_datapath.ram_c_din0,
                 dut.u_datapath.u_ram_c.we_b,
                 dut.u_datapath.u_ram_c.addr_b,
                 dut.u_datapath.ram_c_din1);
        $display("DEBUG: coeff=%0d,%0d,%0d,%0d tw=%0d,%0d,%0d,%0d bf=%0d,%0d,%0d,%0d",
                 dut.u_datapath.coeff0, dut.u_datapath.coeff1,
                 dut.u_datapath.coeff2, dut.u_datapath.coeff3,
                 dut.u_datapath.tw_s0_b0, dut.u_datapath.tw_s0_b1,
                 dut.u_datapath.tw_s1_b0, dut.u_datapath.tw_s1_b1,
                 dut.u_datapath.bf_out0, dut.u_datapath.bf_out1,
                 dut.u_datapath.bf_out2, dut.u_datapath.bf_out3);
      end
    end
    if (!rst) begin
      if (dut.f_wr_en && dut.f_wr_dst_sel == RAM_C)
        fsm_c_write_count <= fsm_c_write_count + 1;
      if (dut.dp_wr_en && dut.dp_wr_dst_sel == RAM_C)
        dp_c_write_count <= dp_c_write_count + 1;
      if (dut.u_datapath.c_selected_for_write)
        selected_c_write_count <= selected_c_write_count + 1;
      if (dut.u_datapath.u_ram_c.we_a)
        c_write_count <= c_write_count + 1;
      if (dut.u_datapath.u_ram_c.we_b)
        c_write_count <= c_write_count + 1;
      if (dut.u_datapath.u_ram_c.we_a && dut.u_datapath.u_ram_c.addr_a == 8'd0)
        c0_write_count <= c0_write_count + 1;
      if (dut.u_datapath.u_ram_c.we_b && dut.u_datapath.u_ram_c.addr_b == 8'd0)
        c0_write_count <= c0_write_count + 1;
    end
  end

  initial begin
    $readmemh("kiber_test.srcs/sources_1/imports/Desktop/twiddle_k2red.mem", rom);

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
    printed_x_write = 1'b0;
    c0_write_count = 0;
    c_write_count = 0;
    fsm_c_write_count = 0;
    dp_c_write_count = 0;
    selected_c_write_count = 0;

    for (i = 0; i < 256; i = i + 1) begin
      ref_a[i] = ((i * 17) + 9) % Q;
      ref_b[i] = ((i * i) + (5 * i) + 11) % Q;
      ref_c[i] = 12'd0;
    end

    run_reference_transform(1'b0, 0);
    run_reference_transform(1'b0, 1);
    for (i = 0; i < 256; i = i + 1) begin
      ref_c[i] = mul_mod_q(ref_a[i], ref_b[i]);
    end
    run_reference_transform(1'b1, 2);

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    for (i = 0; i < 128; i = i + 1) begin
      load_pair(RAM_A, i[7:0] << 1, (i[7:0] << 1) + 8'd1,
                (((2*i) * 17) + 9) % Q,
                (((2*i + 1) * 17) + 9) % Q);
      load_pair(RAM_B, i[7:0] << 1, (i[7:0] << 1) + 8'd1,
                (((2*i) * (2*i)) + (5 * (2*i)) + 11) % Q,
                (((2*i + 1) * (2*i + 1)) + (5 * (2*i + 1)) + 11) % Q);
    end

    if (dut.u_datapath.u_ram_a.ram[0] !== 12'd9 ||
        dut.u_datapath.u_ram_a.ram[64] !== ((64 * 17) + 9) % Q) begin
      $display("FAIL: load check A[0]=%0d A[64]=%0d", dut.u_datapath.u_ram_a.ram[0],
               dut.u_datapath.u_ram_a.ram[64]);
      $stop;
    end

    @(negedge clk);
    start = 1'b1;
    @(posedge clk);
    @(negedge clk);
    start = 1'b0;

    cycles = 0;
    while (!done && !error && cycles < 20000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end

    if (error) begin
      $display("FAIL: core error at phase=%0d pass=%0d op=%0d", phase_dbg, pass_dbg, op_dbg);
      $stop;
    end
    if (!done) begin
      $display("FAIL: core timeout at phase=%0d pass=%0d op=%0d", phase_dbg, pass_dbg, op_dbg);
      $stop;
    end

    check_i = 0;
    while (check_i < 128) begin
      check_addr = check_i * 2;
      read_pair(RAM_C, check_addr[7:0], (check_addr + 1), got0, got1);
      if (got0 !== ref_c[check_addr] || got1 !== ref_c[check_addr + 1]) begin
        $display("FAIL: final C mismatch pair=%0d got=%0d,%0d exp=%0d,%0d",
                 check_i, got0, got1, ref_c[check_addr], ref_c[check_addr + 1]);
        $display("DEBUG: direct RAM C[%0d]=%0d RAM C[%0d]=%0d busy=%0d done=%0d phase=%0d pass=%0d op=%0d",
                 check_addr, dut.u_datapath.u_ram_c.ram[check_addr],
                 check_addr + 1, dut.u_datapath.u_ram_c.ram[check_addr + 1],
                 busy, done, phase_dbg, pass_dbg, op_dbg);
        $display("DEBUG: C[0] write count=%0d", c0_write_count);
        $display("DEBUG: total C write count=%0d", c_write_count);
        $display("DEBUG: FSM C write command count=%0d", fsm_c_write_count);
        $display("DEBUG: core dp C write command count=%0d selected C count=%0d",
                 dp_c_write_count, selected_c_write_count);
        $stop;
      end
      check_i = check_i + 1;
    end

    $display("PASS: full core output matched reference for all 256 coefficients. cycles=%0d", cycles);
    $finish;
  end

  initial begin
    #10000000;
    $display("TIMEOUT: simulation did not finish.");
    $finish;
  end

endmodule
