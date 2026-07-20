`timescale 1ns/1ps

module tb_ntt_3ram_core;

  localparam int Q = 3329;
  localparam int AW = 8;
  localparam int DW = 12;

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

  task automatic clear_inputs;
    begin
      start = 1'b0;
      load_en = 1'b0;
      load_ram_sel = 2'd0;
      load_addr0 = {AW{1'b0}};
      load_addr1 = {AW{1'b0}};
      load_data0 = {DW{1'b0}};
      load_data1 = {DW{1'b0}};
      host_rd_en = 1'b0;
      host_rd_ram_sel = 2'd0;
      host_rd_addr0 = {AW{1'b0}};
      host_rd_addr1 = {AW{1'b0}};
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

  integer i;
  integer cycles;

  initial begin
    clear_inputs();
    rst = 1'b1;
    repeat (5) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    for (i = 0; i < 128; i = i + 1) begin
      load_pair(2'd0, i[7:0] << 1, (i[7:0] << 1) + 8'd1,
                ((2*i + 1) % Q), ((2*i + 2) % Q));
      load_pair(2'd1, i[7:0] << 1, (i[7:0] << 1) + 8'd1,
                ((3*i + 5) % Q), ((3*i + 6) % Q));
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
      $display("FAIL: core FSM reported error at phase=%0d pass=%0d op=%0d",
               phase_dbg, pass_dbg, op_dbg);
      $stop;
    end

    if (!done) begin
      $display("FAIL: core FSM timeout at phase=%0d pass=%0d op=%0d",
               phase_dbg, pass_dbg, op_dbg);
      $stop;
    end

    $display("PASS: ntt_3ram_core FSM completed in %0d cycles.", cycles);
    $finish;
  end

  initial begin
    #5000000;
    $display("TIMEOUT: simulation did not finish.");
    $finish;
  end

endmodule
