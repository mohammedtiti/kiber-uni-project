`timescale 1ns / 1ps

// Top-level core: controller FSM + 3-RAM datapath.
//
// Use load_* while busy=0 to initialize RAM A/B, or RAM C for tests.
// Then pulse start for one clock. done pulses when INTT(C) is complete.
module ntt_3ram_core #(
    parameter AW = 8,
    parameter DW = 12,
    parameter TW_AW = 7,
    parameter RAM_A_MEMFILE = "",
    parameter RAM_B_MEMFILE = "",
    parameter RAM_C_MEMFILE = "",
    parameter TW_MEMFILE = "twiddle_k2red.mem"
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              start,

    input  wire              load_en,
    input  wire [1:0]        load_ram_sel,   // 0=A, 1=B, 2=C
    input  wire [AW-1:0]     load_addr0,
    input  wire [AW-1:0]     load_addr1,
    input  wire [DW-1:0]     load_data0,
    input  wire [DW-1:0]     load_data1,

    input  wire              host_rd_en,
    input  wire [1:0]        host_rd_ram_sel, // 0=A, 1=B, 2=C
    input  wire [AW-1:0]     host_rd_addr0,
    input  wire [AW-1:0]     host_rd_addr1,

    output wire              busy,
    output wire              done,
    output wire              error,
    output wire [2:0]        phase_dbg,
    output wire [1:0]        pass_dbg,
    output wire [6:0]        op_dbg,

    output wire [DW-1:0]     ram_rd0,
    output wire [DW-1:0]     ram_rd1,
    output wire [DW-1:0]     mul_out0,
    output wire [DW-1:0]     mul_out1
);

    wire              f_mode_in;
    wire              f_rd_en;
    wire [1:0]        f_rd_src_sel;
    wire [AW-1:0]     f_rd_addr0;
    wire [AW-1:0]     f_rd_addr1;
    wire              f_rd_capture_en;
    wire              f_rd_capture_sel;
    wire              f_wr_en;
    wire [1:0]        f_wr_dst_sel;
    wire [AW-1:0]     f_wr_addr0;
    wire [AW-1:0]     f_wr_addr1;
    wire              f_wr_result_sel;
    wire              f_mul_rd_en;
    wire              f_mul_wr_en;
    wire [AW-1:0]     f_mul_addr0;
    wire [AW-1:0]     f_mul_addr1;
    wire [TW_AW-1:0]  f_tw_addr_s0_b0;
    wire [TW_AW-1:0]  f_tw_addr_s0_b1;
    wire [TW_AW-1:0]  f_tw_addr_s1_b0;
    wire [TW_AW-1:0]  f_tw_addr_s1_b1;
    wire              f_tw_force_neg_s0_b0;
    wire              f_tw_force_neg_s0_b1;
    wire              f_tw_force_neg_s1_b0;
    wire              f_tw_force_neg_s1_b1;
    wire              f_tw_load;
    wire              f_bf_start;

    wire              bf_valid;
    wire              mul_valid;
    wire              ram_conflict;
    wire              load_active = (load_en === 1'b1) && (busy !== 1'b1);
    wire              host_rd_active = (host_rd_en === 1'b1) && (busy !== 1'b1) && !load_active;

    wire              dp_wr_en = load_active ? 1'b1 : f_wr_en;
    wire [1:0]        dp_wr_dst_sel = load_active ? load_ram_sel : f_wr_dst_sel;
    wire [AW-1:0]     dp_wr_addr0 = load_active ? load_addr0 : f_wr_addr0;
    wire [AW-1:0]     dp_wr_addr1 = load_active ? load_addr1 : f_wr_addr1;
    wire              dp_wr_result_sel = load_active ? 1'b0 : f_wr_result_sel;
    wire              dp_wr_use_ext = load_active;
    wire [DW-1:0]     dp_wr_ext0 = load_data0;
    wire [DW-1:0]     dp_wr_ext1 = load_data1;

    wire              dp_rd_en = host_rd_active ? 1'b1 : f_rd_en;
    wire [1:0]        dp_rd_src_sel = host_rd_active ? host_rd_ram_sel : f_rd_src_sel;
    wire [AW-1:0]     dp_rd_addr0 = host_rd_active ? host_rd_addr0 : f_rd_addr0;
    wire [AW-1:0]     dp_rd_addr1 = host_rd_active ? host_rd_addr1 : f_rd_addr1;

    ntt_3ram_fsm #(.AW(AW), .TW_AW(TW_AW)) u_fsm (
        .clk(clk),
        .rst(rst),
        .start(start),
        .bf_valid(bf_valid),
        .mul_valid(mul_valid),
        .ram_conflict(ram_conflict),
        .mode_in(f_mode_in),
        .rd_en(f_rd_en),
        .rd_src_sel(f_rd_src_sel),
        .rd_addr0(f_rd_addr0),
        .rd_addr1(f_rd_addr1),
        .rd_capture_en(f_rd_capture_en),
        .rd_capture_sel(f_rd_capture_sel),
        .wr_en(f_wr_en),
        .wr_dst_sel(f_wr_dst_sel),
        .wr_addr0(f_wr_addr0),
        .wr_addr1(f_wr_addr1),
        .wr_result_sel(f_wr_result_sel),
        .mul_rd_en(f_mul_rd_en),
        .mul_wr_en(f_mul_wr_en),
        .mul_addr0(f_mul_addr0),
        .mul_addr1(f_mul_addr1),
        .tw_addr_s0_b0(f_tw_addr_s0_b0),
        .tw_addr_s0_b1(f_tw_addr_s0_b1),
        .tw_addr_s1_b0(f_tw_addr_s1_b0),
        .tw_addr_s1_b1(f_tw_addr_s1_b1),
        .tw_force_neg_s0_b0(f_tw_force_neg_s0_b0),
        .tw_force_neg_s0_b1(f_tw_force_neg_s0_b1),
        .tw_force_neg_s1_b0(f_tw_force_neg_s1_b0),
        .tw_force_neg_s1_b1(f_tw_force_neg_s1_b1),
        .tw_load(f_tw_load),
        .bf_start(f_bf_start),
        .busy(busy),
        .done(done),
        .error(error),
        .phase_dbg(phase_dbg),
        .pass_dbg(pass_dbg),
        .op_dbg(op_dbg)
    );

    ntt_3ram_datapath #(
        .AW(AW),
        .DW(DW),
        .TW_AW(TW_AW),
        .RAM_A_MEMFILE(RAM_A_MEMFILE),
        .RAM_B_MEMFILE(RAM_B_MEMFILE),
        .RAM_C_MEMFILE(RAM_C_MEMFILE),
        .TW_MEMFILE(TW_MEMFILE)
    ) u_datapath (
        .clk(clk),
        .rst(rst),
        .mode_in(f_mode_in),
        .rd_en(dp_rd_en),
        .rd_src_sel(dp_rd_src_sel),
        .rd_addr0(dp_rd_addr0),
        .rd_addr1(dp_rd_addr1),
        .rd_capture_en(f_rd_capture_en),
        .rd_capture_sel(f_rd_capture_sel),
        .wr_en(dp_wr_en),
        .wr_dst_sel(dp_wr_dst_sel),
        .wr_addr0(dp_wr_addr0),
        .wr_addr1(dp_wr_addr1),
        .wr_result_sel(dp_wr_result_sel),
        .wr_use_ext(dp_wr_use_ext),
        .wr_ext0(dp_wr_ext0),
        .wr_ext1(dp_wr_ext1),
        .mul_rd_en(f_mul_rd_en),
        .mul_wr_en(f_mul_wr_en),
        .mul_addr0(f_mul_addr0),
        .mul_addr1(f_mul_addr1),
        .mul_valid(mul_valid),
        .mul_out0(mul_out0),
        .mul_out1(mul_out1),
        .tw_addr_s0_b0(f_tw_addr_s0_b0),
        .tw_addr_s0_b1(f_tw_addr_s0_b1),
        .tw_addr_s1_b0(f_tw_addr_s1_b0),
        .tw_addr_s1_b1(f_tw_addr_s1_b1),
        .tw_force_neg_s0_b0(f_tw_force_neg_s0_b0),
        .tw_force_neg_s0_b1(f_tw_force_neg_s0_b1),
        .tw_force_neg_s1_b0(f_tw_force_neg_s1_b0),
        .tw_force_neg_s1_b1(f_tw_force_neg_s1_b1),
        .tw_load(f_tw_load),
        .bf_start(f_bf_start),
        .bf_valid(bf_valid),
        .coeff0(),
        .coeff1(),
        .coeff2(),
        .coeff3(),
        .bf_out0(),
        .bf_out1(),
        .bf_out2(),
        .bf_out3(),
        .ram_rd0(ram_rd0),
        .ram_rd1(ram_rd1),
        .ram_conflict(ram_conflict)
    );

endmodule
