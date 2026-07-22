`timescale 1ns/1ps

module tb_ntt_3ram_datapath;
  localparam [1:0] RAM_A=2'd0, RAM_B=2'd1, RAM_C=2'd2;
  logic clk=0;
  always #5 clk=~clk;

  logic core_active, core_wr_en;
  logic [7:0] core_addr0, core_addr1;
  logic [1:0] core_wr_ram_sel;
  logic [11:0] core_wr_data0, core_wr_data1;
  logic load_en;
  logic [1:0] load_ram_sel;
  logic [7:0] load_addr0, load_addr1;
  logic [11:0] load_data0, load_data1;
  logic host_rd_en;
  logic [1:0] host_rd_ram_sel;
  logic [7:0] host_rd_addr0, host_rd_addr1;
  wire [11:0] a0,a1,b0,b1,c0,c1,host0,host1;

  ntt_3ram_datapath dut (
    .clk(clk),
    .core_active(core_active), .core_addr0(core_addr0), .core_addr1(core_addr1),
    .core_wr_en(core_wr_en), .core_wr_ram_sel(core_wr_ram_sel),
    .core_wr_data0(core_wr_data0), .core_wr_data1(core_wr_data1),
    .load_en(load_en), .load_ram_sel(load_ram_sel),
    .load_addr0(load_addr0), .load_addr1(load_addr1),
    .load_data0(load_data0), .load_data1(load_data1),
    .host_rd_en(host_rd_en), .host_rd_ram_sel(host_rd_ram_sel),
    .host_rd_addr0(host_rd_addr0), .host_rd_addr1(host_rd_addr1),
    .ram_a_rd0(a0), .ram_a_rd1(a1), .ram_b_rd0(b0), .ram_b_rd1(b1),
    .ram_c_rd0(c0), .ram_c_rd1(c1),
    .host_rd_data0(host0), .host_rd_data1(host1)
  );

  task automatic load(input [1:0] bank, input [7:0] address,
                      input [11:0] d0, input [11:0] d1);
    begin
      @(negedge clk);
      load_en=1; load_ram_sel=bank; load_addr0=address; load_addr1=address+1;
      load_data0=d0; load_data1=d1;
      @(posedge clk);
      @(negedge clk); load_en=0;
    end
  endtask

  task automatic check_host(input [1:0] bank, input [7:0] address,
                            input [11:0] e0, input [11:0] e1);
    begin
      @(negedge clk);
      host_rd_en=1; host_rd_ram_sel=bank;
      host_rd_addr0=address; host_rd_addr1=address+1;
      @(posedge clk); #1;
      if (host0!==e0 || host1!==e1)
        $fatal(1,"FAIL host bank=%0d got=(%0d,%0d) expected=(%0d,%0d)",
               bank,host0,host1,e0,e1);
      @(negedge clk); host_rd_en=0;
    end
  endtask

  initial begin
    core_active=0; core_wr_en=0; core_addr0=0; core_addr1=1;
    core_wr_ram_sel=RAM_C; core_wr_data0=0; core_wr_data1=0;
    load_en=0; load_ram_sel=0; load_addr0=0; load_addr1=1;
    load_data0=0; load_data1=0;
    host_rd_en=0; host_rd_ram_sel=0; host_rd_addr0=0; host_rd_addr1=1;

    load(RAM_A,8'd20,12'd101,12'd102);
    load(RAM_B,8'd20,12'd201,12'd202);
    load(RAM_C,8'd20,12'd301,12'd302);
    check_host(RAM_A,8'd20,12'd101,12'd102);
    check_host(RAM_B,8'd20,12'd201,12'd202);
    check_host(RAM_C,8'd20,12'd301,12'd302);

    // The core sees A, B, and C concurrently at one common address pair.
    @(negedge clk);
    core_active=1; core_addr0=8'd20; core_addr1=8'd21;
    @(posedge clk); #1;
    if (a0!==101 || a1!==102 || b0!==201 || b1!==202 || c0!==301 || c1!==302)
      $fatal(1,"FAIL concurrent core read");

    // A core write owns the ports and updates only the selected bank.
    @(negedge clk);
    core_wr_en=1; core_wr_ram_sel=RAM_C;
    core_wr_data0=12'd777; core_wr_data1=12'd888;
    @(posedge clk);
    @(negedge clk);
    core_wr_en=0; core_active=0;
    check_host(RAM_C,8'd20,12'd777,12'd888);
    check_host(RAM_A,8'd20,12'd101,12'd102);
    check_host(RAM_B,8'd20,12'd201,12'd202);

    $display("PASS: ntt_3ram_datapath load/read/core arbitration");
    $finish;
  end
endmodule
