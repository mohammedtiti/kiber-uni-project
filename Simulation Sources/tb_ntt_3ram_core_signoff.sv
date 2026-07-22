`timescale 1ns/1ps

// Signoff testbench.  The oracle is deliberately independent of the RTL NTT:
// it performs direct schoolbook multiplication modulo x^256+1 and q=3329.
module tb_ntt_3ram_core_signoff;
  localparam int Q = 3329;
  localparam int N = 256;
  localparam int CASE_COUNT = 11;
  localparam int EXPECTED_CORE_CYCLES = 8065;
  localparam int EXPECTED_A_WRITES = 512;
  localparam int EXPECTED_B_WRITES = 512;
  localparam int EXPECTED_C_WRITES = 768;

  localparam [1:0] RAM_A = 2'd0;
  localparam [1:0] RAM_B = 2'd1;
  localparam [1:0] RAM_C = 2'd2;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst, start;
  logic load_en;
  logic [1:0] load_ram_sel;
  logic [7:0] load_addr0, load_addr1;
  logic [11:0] load_data0, load_data1;
  logic host_rd_en;
  logic [1:0] host_rd_ram_sel;
  logic [7:0] host_rd_addr0, host_rd_addr1;
  wire busy, done, error;
  wire [2:0] phase_dbg;
  wire [1:0] pass_dbg;
  wire [6:0] op_dbg;
  wire [11:0] ram_rd0, ram_rd1, mul_out0, mul_out1;

  logic [11:0] input_a [0:N-1];
  logic [11:0] input_b [0:N-1];
  logic [11:0] reference_c [0:N-1];
  longint signed accumulator [0:N-1];

  integer current_case;
  integer total_comparisons;
  integer write_count_a, write_count_b, write_count_c;
  integer range_errors;
  integer phase_seen [0:4];

  ntt_3ram_core dut (
    .clk(clk), .rst(rst), .start(start),
    .load_en(load_en), .load_ram_sel(load_ram_sel),
    .load_addr0(load_addr0), .load_addr1(load_addr1),
    .load_data0(load_data0), .load_data1(load_data1),
    .host_rd_en(host_rd_en), .host_rd_ram_sel(host_rd_ram_sel),
    .host_rd_addr0(host_rd_addr0), .host_rd_addr1(host_rd_addr1),
    .busy(busy), .done(done), .error(error),
    .phase_dbg(phase_dbg), .pass_dbg(pass_dbg), .op_dbg(op_dbg),
    .ram_rd0(ram_rd0), .ram_rd1(ram_rd1),
    .mul_out0(mul_out0), .mul_out1(mul_out1)
  );

  function automatic string case_name(input integer c);
    case (c)
      0: case_name = "zero";
      1: case_name = "identity";
      2: case_name = "explicit_negacyclic_wrap";
      3: case_name = "ones_times_q_minus_1";
      4: case_name = "alternating_edges";
      5: case_name = "ramp_quadratic";
      6: case_name = "sparse_boundary_terms";
      7: case_name = "high_product_stress";
      8: case_name = "deterministic_random_1";
      9: case_name = "deterministic_random_2";
      default: case_name = "deterministic_random_3";
    endcase
  endfunction

  function automatic [11:0] pseudo_random_coeff(
      input integer c, input integer index, input bit select_b);
    int unsigned x;
    integer k;
    begin
      x = 32'h9e3779b9 ^ (c * 32'h045d9f3b) ^ (index * 32'h119de1f3);
      if (select_b)
        x = x ^ 32'h7f4a7c15;
      for (k = 0; k < 4; k = k + 1)
        x = x * 32'd1664525 + 32'd1013904223;
      pseudo_random_coeff = x % Q;
    end
  endfunction

  function automatic [11:0] pattern(
      input integer c, input integer index, input bit select_b);
    int unsigned value;
    begin
      case (c)
        0: value = 0;
        1: value = select_b ? ((index == 0) ? 1 : 0) :
                              ((17*index*index + 9*index + 31) % Q);
        2: value = select_b ? ((index == 1) ? 1 : 0) :
                              ((index == 255) ? 1 : 0);
        3: value = select_b ? Q-1 : 1;
        4: value = select_b ? (index[0] ? Q-1 : 0) :
                              (index[0] ? 0 : Q-1);
        5: value = select_b ? ((index*index + 5*index + 11) % Q) :
                              ((17*index + 9) % Q);
        6: begin
          if (select_b)
            value = ((index == 1) || (index == 64) ||
                     (index == 129) || (index == 255)) ? (37*index+19)%Q : 0;
          else
            value = ((index == 0) || (index == 2) ||
                     (index == 127) || (index == 128) ||
                     (index == 254) || (index == 255)) ? (91*index+7)%Q : 0;
        end
        7: value = select_b ? (Q-1-((29*index)%Q)) :
                              (Q-1-((index*index+13)%Q));
        default: value = pseudo_random_coeff(c, index, select_b);
      endcase
      pattern = value % Q;
    end
  endfunction

  task automatic fail(input string message);
    begin
      $display("FAIL case=%0d (%s), phase=%0d stage_low=%0d op=%0d, t=%0t: %s",
               current_case, case_name(current_case), phase_dbg, pass_dbg, op_dbg,
               $time, message);
      $fatal(1);
    end
  endtask

  task automatic prepare_case(input integer c);
    integer i, j, index;
    longint signed reduced;
    begin
      for (i = 0; i < N; i = i + 1) begin
        input_a[i] = pattern(c, i, 1'b0);
        input_b[i] = pattern(c, i, 1'b1);
        accumulator[i] = 0;
      end

      // Independent negacyclic oracle: x^256 = -1.
      for (i = 0; i < N; i = i + 1) begin
        for (j = 0; j < N; j = j + 1) begin
          index = i + j;
          if (index < N)
            accumulator[index] = accumulator[index] +
                                 (longint'(input_a[i]) * longint'(input_b[j]));
          else
            accumulator[index-N] = accumulator[index-N] -
                                   (longint'(input_a[i]) * longint'(input_b[j]));
        end
      end

      for (i = 0; i < N; i = i + 1) begin
        reduced = accumulator[i] % Q;
        if (reduced < 0)
          reduced = reduced + Q;
        reference_c[i] = reduced[11:0];
      end
    end
  endtask

  task automatic load_pair(
      input [1:0] selected_ram, input [7:0] address,
      input [11:0] data0, input [11:0] data1);
    begin
      @(negedge clk);
      load_en = 1'b1;
      load_ram_sel = selected_ram;
      load_addr0 = address;
      load_addr1 = address + 1'b1;
      load_data0 = data0;
      load_data1 = data1;
      @(posedge clk);
      @(negedge clk);
      load_en = 1'b0;
    end
  endtask

  task automatic read_pair(
      input [1:0] selected_ram, input [7:0] address,
      output [11:0] data0, output [11:0] data1);
    begin
      @(negedge clk);
      host_rd_en = 1'b1;
      host_rd_ram_sel = selected_ram;
      host_rd_addr0 = address;
      host_rd_addr1 = address + 1'b1;
      @(posedge clk);
      #1;
      data0 = ram_rd0;
      data1 = ram_rd1;
      @(negedge clk);
      host_rd_en = 1'b0;
    end
  endtask

  task automatic load_inputs;
    integer p, a;
    begin
      for (p = 0; p < 128; p = p + 1) begin
        a = 2*p;
        load_pair(RAM_A, a[7:0], input_a[a], input_a[a+1]);
        load_pair(RAM_B, a[7:0], input_b[a], input_b[a+1]);
        load_pair(RAM_C, a[7:0], (12'd123 + a) % Q,
                  (12'd123 + a + 1) % Q);
      end
    end
  endtask

  task automatic reset_monitors;
    integer p;
    begin
      write_count_a = 0;
      write_count_b = 0;
      write_count_c = 0;
      range_errors = 0;
      for (p = 0; p < 5; p = p + 1)
        phase_seen[p] = 0;
    end
  endtask

  task automatic run_core(output integer cycles);
    begin
      reset_monitors();
      @(negedge clk);
      start = 1'b1;
      @(posedge clk);
      @(negedge clk);
      start = 1'b0;

      cycles = 0;
      while (!done && !error && cycles < 12000) begin
        @(posedge clk);
        #1;
        cycles = cycles + 1;
      end
      if (error)
        fail("core asserted error");
      if (!done)
        fail("core timed out");
      if (busy)
        fail("busy must be low when done is asserted");
      if (cycles != EXPECTED_CORE_CYCLES) begin
        $display("Got %0d cycles, expected %0d", cycles, EXPECTED_CORE_CYCLES);
        fail("unexpected controller cycle count");
      end

      @(posedge clk);
      #1;
      if (done)
        fail("done must be a one-cycle pulse");
    end
  endtask

  task automatic verify_result;
    integer p, a;
    logic [11:0] got0, got1;
    begin
      for (p = 0; p < 128; p = p + 1) begin
        a = 2*p;
        read_pair(RAM_C, a[7:0], got0, got1);
        if (got0 !== reference_c[a]) begin
          $display("coefficient %0d: got %0d expected %0d", a, got0, reference_c[a]);
          fail("RAM C mismatch");
        end
        if (got1 !== reference_c[a+1]) begin
          $display("coefficient %0d: got %0d expected %0d", a+1, got1, reference_c[a+1]);
          fail("RAM C mismatch");
        end
        if ((got0 >= Q) || (got1 >= Q))
          fail("non-canonical result coefficient");
        total_comparisons = total_comparisons + 2;
      end

      if (write_count_a != EXPECTED_A_WRITES)
        fail("unexpected RAM A core-write count");
      if (write_count_b != EXPECTED_B_WRITES)
        fail("unexpected RAM B core-write count");
      if (write_count_c != EXPECTED_C_WRITES)
        fail("unexpected RAM C core-write count");
      if (range_errors != 0)
        fail("an internal write was X or outside [0,q)");
      for (p = 0; p < 5; p = p + 1)
        if (phase_seen[p] == 0)
          fail("not all computation phases were observed");
    end
  endtask

  always @(posedge clk) begin
    if (!rst && busy) begin
      if (phase_dbg <= 4)
        phase_seen[phase_dbg] = 1;
      if (dut.core_wr_en) begin
        case (dut.core_wr_ram_sel)
          RAM_A: write_count_a = write_count_a + 1;
          RAM_B: write_count_b = write_count_b + 1;
          RAM_C: write_count_c = write_count_c + 1;
          default: fail("invalid core write RAM selection");
        endcase
        if ((^dut.core_wr_data0 === 1'bx) || (^dut.core_wr_data1 === 1'bx) ||
            (dut.core_wr_data0 >= Q) || (dut.core_wr_data1 >= Q))
          range_errors = range_errors + 1;
      end
    end
  end

  initial begin
    integer c, cycles;
    current_case = -1;
    total_comparisons = 0;
    rst = 1'b1;
    start = 1'b0;
    load_en = 1'b0;
    load_ram_sel = RAM_A;
    load_addr0 = 0;
    load_addr1 = 1;
    load_data0 = 0;
    load_data1 = 0;
    host_rd_en = 1'b0;
    host_rd_ram_sel = RAM_C;
    host_rd_addr0 = 0;
    host_rd_addr1 = 1;
    reset_monitors();

    repeat (5) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    // All cases are run back-to-back with no reset between them.
    for (c = 0; c < CASE_COUNT; c = c + 1) begin
      current_case = c;
      $display("INFO: case %0d/%0d: %s", c+1, CASE_COUNT, case_name(c));
      prepare_case(c);
      if ((c == 2) && (reference_c[0] !== 12'd3328))
        fail("explicit x^255*x oracle did not produce -1 at coefficient zero");
      load_inputs();
      run_core(cycles);
      verify_result();
      $display("PASS: %s, 256 coefficients, %0d cycles",
               case_name(c), cycles);
    end

    $display("PASS: Kyber signoff completed: %0d cases, %0d independent comparisons.",
             CASE_COUNT, total_comparisons);
    $finish;
  end

  initial begin
    #2000000;
    $display("TIMEOUT");
    $fatal(1);
  end
endmodule
