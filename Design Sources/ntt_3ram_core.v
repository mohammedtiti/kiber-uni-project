`timescale 1ns / 1ps

// Kyber polynomial-multiplication core.  Inputs A and B are ordinary
// coefficients in [0,3328].  After done, RAM C contains A*B mod (x^256+1,3329).
module ntt_3ram_core #(
    parameter AW = 8,
    parameter DW = 12,
    parameter TW_AW = 7,
    parameter RAM_A_MEMFILE = "",
    parameter RAM_B_MEMFILE = "",
    parameter RAM_C_MEMFILE = "",
    parameter TW_MEMFILE = ""
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              start,

    input  wire              load_en,
    input  wire [1:0]        load_ram_sel,
    input  wire [AW-1:0]     load_addr0,
    input  wire [AW-1:0]     load_addr1,
    input  wire [DW-1:0]     load_data0,
    input  wire [DW-1:0]     load_data1,

    input  wire              host_rd_en,
    input  wire [1:0]        host_rd_ram_sel,
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
    wire core_active;
    wire [AW-1:0] core_addr0, core_addr1;
    wire core_wr_en;
    wire [1:0] core_wr_ram_sel;
    wire [DW-1:0] core_wr_data0, core_wr_data1;

    wire [DW-1:0] ram_a_rd0, ram_a_rd1;
    wire [DW-1:0] ram_b_rd0, ram_b_rd1;
    wire [DW-1:0] ram_c_rd0, ram_c_rd1;

    wire block_mode;
    wire block_two_stage;
    wire [DW-1:0] block_in0, block_in1, block_in2, block_in3;
    wire [DW-1:0] block_out0, block_out1, block_out2, block_out3;
    wire [6:0] block_tw_addr0, block_tw_addr1;
    wire [6:0] block_tw_addr2, block_tw_addr3;
    wire [11:0] block_tw0, block_tw1, block_tw2, block_tw3;
    wire [6:0] tw_addr;
    wire tw_negate;
    wire [11:0] tw_zeta;

    wire [DW-1:0] mul_a0, mul_b0, mul_a1, mul_b1;

    wire load_allowed = load_en && !busy;
    wire read_allowed = host_rd_en && !busy && !load_en;

    ntt_3ram_datapath #(
        .AW(AW), .DW(DW),
        .RAM_A_MEMFILE(RAM_A_MEMFILE),
        .RAM_B_MEMFILE(RAM_B_MEMFILE),
        .RAM_C_MEMFILE(RAM_C_MEMFILE)
    ) u_datapath (
        .clk(clk),
        .core_active(core_active),
        .core_addr0(core_addr0), .core_addr1(core_addr1),
        .core_wr_en(core_wr_en), .core_wr_ram_sel(core_wr_ram_sel),
        .core_wr_data0(core_wr_data0), .core_wr_data1(core_wr_data1),
        .load_en(load_allowed), .load_ram_sel(load_ram_sel),
        .load_addr0(load_addr0), .load_addr1(load_addr1),
        .load_data0(load_data0), .load_data1(load_data1),
        .host_rd_en(read_allowed), .host_rd_ram_sel(host_rd_ram_sel),
        .host_rd_addr0(host_rd_addr0), .host_rd_addr1(host_rd_addr1),
        .ram_a_rd0(ram_a_rd0), .ram_a_rd1(ram_a_rd1),
        .ram_b_rd0(ram_b_rd0), .ram_b_rd1(ram_b_rd1),
        .ram_c_rd0(ram_c_rd0), .ram_c_rd1(ram_c_rd1),
        .host_rd_data0(ram_rd0), .host_rd_data1(ram_rd1)
    );

    kyber_twiddle_rom u_twiddle (
        .addr(tw_addr),
        .negate(tw_negate),
        .zeta(tw_zeta),
        .zeta_scaled()
    );

    // Four independent scaled-twiddle lookups feed the integrated 2x2 block.
    // Vivado can optimize the duplicated constant decode logic while retaining
    // four arithmetic issue lanes.
    kyber_twiddle_rom u_block_tw0 (
        .addr(block_tw_addr0), .negate(1'b0),
        .zeta(), .zeta_scaled(block_tw0)
    );
    kyber_twiddle_rom u_block_tw1 (
        .addr(block_tw_addr1), .negate(1'b0),
        .zeta(), .zeta_scaled(block_tw1)
    );
    kyber_twiddle_rom u_block_tw2 (
        .addr(block_tw_addr2), .negate(1'b0),
        .zeta(), .zeta_scaled(block_tw2)
    );
    kyber_twiddle_rom u_block_tw3 (
        .addr(block_tw_addr3), .negate(1'b0),
        .zeta(), .zeta_scaled(block_tw3)
    );

    ntt_2stage_4butterfly u_2x2_butterfly (
        .clk(clk),
        .mode_in(block_mode),
        .two_stage_en(block_two_stage),
        .in0(block_in0), .in1(block_in1),
        .in2(block_in2), .in3(block_in3),
        .tw_s0_b0(block_tw0), .tw_s0_b1(block_tw1),
        .tw_s1_b0(block_tw2), .tw_s1_b1(block_tw3),
        .out0(block_out0), .out1(block_out1),
        .out2(block_out2), .out3(block_out3)
    );

    kyber_modmul u_mul0 (.a(mul_a0), .b(mul_b0), .r(mul_out0));
    kyber_modmul u_mul1 (.a(mul_a1), .b(mul_b1), .r(mul_out1));

    ntt_3ram_fsm #(.AW(AW), .DW(DW)) u_fsm (
        .clk(clk), .rst(rst), .start(start),
        .ram_a_rd0(ram_a_rd0), .ram_a_rd1(ram_a_rd1),
        .ram_b_rd0(ram_b_rd0), .ram_b_rd1(ram_b_rd1),
        .ram_c_rd0(ram_c_rd0), .ram_c_rd1(ram_c_rd1),
        .block_out0(block_out0), .block_out1(block_out1),
        .block_out2(block_out2), .block_out3(block_out3),
        .mul_result0(mul_out0), .mul_result1(mul_out1),
        .tw_zeta(tw_zeta),
        .core_active(core_active),
        .core_addr0(core_addr0), .core_addr1(core_addr1),
        .core_wr_en(core_wr_en), .core_wr_ram_sel(core_wr_ram_sel),
        .core_wr_data0(core_wr_data0), .core_wr_data1(core_wr_data1),
        .block_mode(block_mode), .block_two_stage(block_two_stage),
        .block_in0(block_in0), .block_in1(block_in1),
        .block_in2(block_in2), .block_in3(block_in3),
        .block_tw_addr0(block_tw_addr0), .block_tw_addr1(block_tw_addr1),
        .block_tw_addr2(block_tw_addr2), .block_tw_addr3(block_tw_addr3),
        .tw_addr(tw_addr), .tw_negate(tw_negate),
        .mul_a0(mul_a0), .mul_b0(mul_b0),
        .mul_a1(mul_a1), .mul_b1(mul_b1),
        .busy(busy), .done(done), .error(error),
        .phase_dbg(phase_dbg), .pass_dbg(pass_dbg), .op_dbg(op_dbg)
    );

    // TW_AW and TW_MEMFILE remain in the public parameter list for project
    // compatibility.  Kyber's fixed seven-bit zeta table is now authoritative.
endmodule
