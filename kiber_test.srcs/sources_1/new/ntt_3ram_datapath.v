`timescale 1ns / 1ps

// Datapath for a 3-RAM NTT/INTT engine using the 2-stage / 4-butterfly block
// plus pointwise multiplication.
//
// Intended controller sequence for one 4-coefficient group:
//   1. Set rd_src_sel and rd_addr0/1, assert rd_en.
//   2. One cycle later assert rd_capture_sel=0 and rd_capture_en to latch in0/in1.
//   3. Set next rd_addr0/1, assert rd_en.
//   4. One cycle later assert rd_capture_sel=1 and rd_capture_en to latch in2/in3.
//   5. Set ROM addresses, wait one cycle, assert tw_load.
//   6. Assert bf_start for one cycle. bf_valid pulses when bf_out* can be written.
//   7. Write bf_out0/bf_out1 with wr_result_sel=0, then bf_out2/bf_out3 with wr_result_sel=1.
//
// RAM A and RAM B hold the input polynomial coefficients. RAM C is the scratch
// RAM used for ping-pong stages and for the pointwise multiply result.
//
// Full intended flow:
//   - NTT(A): use normal rd/wr controls, ping-pong A <-> C.
//   - NTT(B): use normal rd/wr controls, ping-pong B <-> C.
//   - MUL: read final NTT(A) from A and final NTT(B) from B, write products to C.
//   - INTT(C): use normal rd/wr controls, ping-pong C <-> A.
module ntt_3ram_datapath #(
    parameter AW = 8,
    parameter DW = 12,
    parameter TW_AW = 7,
    parameter [DW-1:0] K_INV4_MOD_Q = 12'd1353,
    parameter RAM_A_MEMFILE = "",
    parameter RAM_B_MEMFILE = "",
    parameter RAM_C_MEMFILE = "",
    parameter TW_MEMFILE = "twiddle_k2red.mem"
)(
    input  wire              clk,
    input  wire              rst,

    input  wire              mode_in,        // 0=NTT, 1=INTT

    input  wire              rd_en,
    input  wire [1:0]        rd_src_sel,     // 0=A, 1=B, 2=C
    input  wire [AW-1:0]     rd_addr0,
    input  wire [AW-1:0]     rd_addr1,
    input  wire              rd_capture_en,
    input  wire              rd_capture_sel, // 0 captures coeff0/1, 1 captures coeff2/3

    input  wire              wr_en,
    input  wire [1:0]        wr_dst_sel,     // 0=A, 1=B, 2=C
    input  wire [AW-1:0]     wr_addr0,
    input  wire [AW-1:0]     wr_addr1,
    input  wire              wr_result_sel,  // 0 writes bf_out0/1, 1 writes bf_out2/3
    input  wire              wr_use_ext,
    input  wire [DW-1:0]     wr_ext0,
    input  wire [DW-1:0]     wr_ext1,

    input  wire              mul_rd_en,
    input  wire              mul_wr_en,
    input  wire [AW-1:0]     mul_addr0,
    input  wire [AW-1:0]     mul_addr1,
    output reg               mul_valid,
    output wire [DW-1:0]     mul_out0,
    output wire [DW-1:0]     mul_out1,

    input  wire [TW_AW-1:0]  tw_addr_s0_b0,
    input  wire [TW_AW-1:0]  tw_addr_s0_b1,
    input  wire [TW_AW-1:0]  tw_addr_s1_b0,
    input  wire [TW_AW-1:0]  tw_addr_s1_b1,
    input  wire              tw_force_neg_s0_b0,
    input  wire              tw_force_neg_s0_b1,
    input  wire              tw_force_neg_s1_b0,
    input  wire              tw_force_neg_s1_b1,
    input  wire              tw_load,

    input  wire              bf_start,
    output reg               bf_valid,

    output reg  [DW-1:0]     coeff0,
    output reg  [DW-1:0]     coeff1,
    output reg  [DW-1:0]     coeff2,
    output reg  [DW-1:0]     coeff3,

    output wire [DW-1:0]     bf_out0,
    output wire [DW-1:0]     bf_out1,
    output wire [DW-1:0]     bf_out2,
    output wire [DW-1:0]     bf_out3,

    output wire [DW-1:0]     ram_rd0,
    output wire [DW-1:0]     ram_rd1,
    output wire              ram_conflict
);

    localparam [1:0] RAM_A = 2'd0;
    localparam [1:0] RAM_B = 2'd1;
    localparam [1:0] RAM_C = 2'd2;
    localparam [DW-1:0] K_INV2_NEG_MOD_Q = 12'd1044;

    wire same_ram_read_write = (rd_en === 1'b1) &&
                               (wr_en === 1'b1) &&
                               (rd_src_sel == wr_dst_sel);
    wire dst_is_valid = (wr_dst_sel == RAM_A) || (wr_dst_sel == RAM_B) || (wr_dst_sel == RAM_C);
    wire normal_access = (rd_en === 1'b1) || (wr_en === 1'b1);
    wire mul_access = (mul_rd_en === 1'b1) || (mul_wr_en === 1'b1);
    wire mul_read_window = (mul_rd_en === 1'b1) || (mul_valid === 1'b1);
    assign ram_conflict = same_ram_read_write ||
                          (wr_en && !dst_is_valid) ||
                          (normal_access && mul_access);

    wire [DW-1:0] wr_bf0 = wr_result_sel ? bf_out2 : bf_out0;
    wire [DW-1:0] wr_bf1 = wr_result_sel ? bf_out3 : bf_out1;
    wire [DW-1:0] wr_data0 = wr_use_ext ? wr_ext0 : wr_bf0;
    wire [DW-1:0] wr_data1 = wr_use_ext ? wr_ext1 : wr_bf1;

    wire write_allowed = (wr_en === 1'b1) && !same_ram_read_write && dst_is_valid && !mul_access;
    wire mul_write_allowed = (mul_wr_en === 1'b1) && !normal_access;

    wire a_selected_for_read  = (rd_en === 1'b1) && (rd_src_sel == RAM_A);
    wire b_selected_for_read  = (rd_en === 1'b1) && (rd_src_sel == RAM_B);
    wire c_selected_for_read  = (rd_en === 1'b1) && (rd_src_sel == RAM_C);
    wire a_selected_for_write = write_allowed && (wr_dst_sel == RAM_A);
    wire b_selected_for_write = write_allowed && (wr_dst_sel == RAM_B);
    wire c_selected_for_write = write_allowed && (wr_dst_sel == RAM_C);

    wire [AW-1:0] ram_a_addr0 = a_selected_for_write ? wr_addr0 :
                                mul_read_window       ? mul_addr0 :
                                a_selected_for_read  ? rd_addr0 : {AW{1'b0}};
    wire [AW-1:0] ram_a_addr1 = a_selected_for_write ? wr_addr1 :
                                mul_read_window       ? mul_addr1 :
                                a_selected_for_read  ? rd_addr1 : {AW{1'b0}};
    wire [AW-1:0] ram_b_addr0 = b_selected_for_write ? wr_addr0 :
                                mul_read_window       ? mul_addr0 :
                                b_selected_for_read  ? rd_addr0 : {AW{1'b0}};
    wire [AW-1:0] ram_b_addr1 = b_selected_for_write ? wr_addr1 :
                                mul_read_window       ? mul_addr1 :
                                b_selected_for_read  ? rd_addr1 : {AW{1'b0}};
    wire [AW-1:0] ram_c_addr0 = mul_write_allowed    ? mul_addr0 :
                                c_selected_for_write ? wr_addr0 :
                                c_selected_for_read  ? rd_addr0 : {AW{1'b0}};
    wire [AW-1:0] ram_c_addr1 = mul_write_allowed    ? mul_addr1 :
                                c_selected_for_write ? wr_addr1 :
                                c_selected_for_read  ? rd_addr1 : {AW{1'b0}};

    wire [DW-1:0] ram_a_dout0, ram_a_dout1;
    wire [DW-1:0] ram_b_dout0, ram_b_dout1;
    wire [DW-1:0] ram_c_dout0, ram_c_dout1;
    wire [DW-1:0] ram_c_din0 = mul_write_allowed ? mul_out0 : wr_data0;
    wire [DW-1:0] ram_c_din1 = mul_write_allowed ? mul_out1 : wr_data1;
    reg  [1:0]    rd_src_sel_r;

    RAM1 #(.AW(AW), .DW(DW), .MEMFILE(RAM_A_MEMFILE)) u_ram_a (
        .clk(clk),
        .we_a(a_selected_for_write),
        .addr_a(ram_a_addr0),
        .din_a(wr_data0),
        .dout_a(ram_a_dout0),
        .we_b(a_selected_for_write),
        .addr_b(ram_a_addr1),
        .din_b(wr_data1),
        .dout_b(ram_a_dout1)
    );

    RAM1 #(.AW(AW), .DW(DW), .MEMFILE(RAM_B_MEMFILE)) u_ram_b (
        .clk(clk),
        .we_a(b_selected_for_write),
        .addr_a(ram_b_addr0),
        .din_a(wr_data0),
        .dout_a(ram_b_dout0),
        .we_b(b_selected_for_write),
        .addr_b(ram_b_addr1),
        .din_b(wr_data1),
        .dout_b(ram_b_dout1)
    );

    RAM1 #(.AW(AW), .DW(DW), .MEMFILE(RAM_C_MEMFILE)) u_ram_c (
        .clk(clk),
        .we_a(c_selected_for_write || mul_write_allowed),
        .addr_a(ram_c_addr0),
        .din_a(ram_c_din0),
        .dout_a(ram_c_dout0),
        .we_b(c_selected_for_write || mul_write_allowed),
        .addr_b(ram_c_addr1),
        .din_b(ram_c_din1),
        .dout_b(ram_c_dout1)
    );

    assign ram_rd0 = (rd_src_sel_r == RAM_A) ? ram_a_dout0 :
                     (rd_src_sel_r == RAM_B) ? ram_b_dout0 :
                     (rd_src_sel_r == RAM_C) ? ram_c_dout0 : {DW{1'b0}};
    assign ram_rd1 = (rd_src_sel_r == RAM_A) ? ram_a_dout1 :
                     (rd_src_sel_r == RAM_B) ? ram_b_dout1 :
                     (rd_src_sel_r == RAM_C) ? ram_c_dout1 : {DW{1'b0}};

    wire [23:0] mul_scale_prod0 = ram_b_dout0 * K_INV4_MOD_Q;
    wire [23:0] mul_scale_prod1 = ram_b_dout1 * K_INV4_MOD_Q;
    wire [DW-1:0] mul_b_scaled0;
    wire [DW-1:0] mul_b_scaled1;

    k2red_kyber u_mul_scale0 (
        .C(mul_scale_prod0),
        .R(mul_b_scaled0)
    );

    k2red_kyber u_mul_scale1 (
        .C(mul_scale_prod1),
        .R(mul_b_scaled1)
    );

    wire [23:0] mul_prod0 = ram_a_dout0 * mul_b_scaled0;
    wire [23:0] mul_prod1 = ram_a_dout1 * mul_b_scaled1;

    k2red_kyber u_mul_red0 (
        .C(mul_prod0),
        .R(mul_out0)
    );

    k2red_kyber u_mul_red1 (
        .C(mul_prod1),
        .R(mul_out1)
    );

    wire [DW-1:0] rom_s0_b0, rom_s0_b1, rom_s1_b0, rom_s1_b1;
    reg  [DW-1:0] tw_s0_b0, tw_s0_b1, tw_s1_b0, tw_s1_b1;

    twiddle_rom_k2red #(.AW(TW_AW), .DW(DW), .MEMFILE(TW_MEMFILE)) u_rom_s0_b0 (
        .clk(clk),
        .addr(tw_addr_s0_b0),
        .tf(rom_s0_b0)
    );

    twiddle_rom_k2red #(.AW(TW_AW), .DW(DW), .MEMFILE(TW_MEMFILE)) u_rom_s0_b1 (
        .clk(clk),
        .addr(tw_addr_s0_b1),
        .tf(rom_s0_b1)
    );

    twiddle_rom_k2red #(.AW(TW_AW), .DW(DW), .MEMFILE(TW_MEMFILE)) u_rom_s1_b0 (
        .clk(clk),
        .addr(tw_addr_s1_b0),
        .tf(rom_s1_b0)
    );

    twiddle_rom_k2red #(.AW(TW_AW), .DW(DW), .MEMFILE(TW_MEMFILE)) u_rom_s1_b1 (
        .clk(clk),
        .addr(tw_addr_s1_b1),
        .tf(rom_s1_b1)
    );

    ntt_2stage_4butterfly u_bf_2x2 (
        .clk(clk),
        .mode_in(mode_in),
        .in0(coeff0),
        .in1(coeff1),
        .in2(coeff2),
        .in3(coeff3),
        .tw_s0_b0(tw_s0_b0),
        .tw_s0_b1(tw_s0_b1),
        .tw_s1_b0(tw_s1_b0),
        .tw_s1_b1(tw_s1_b1),
        .out0(bf_out0),
        .out1(bf_out1),
        .out2(bf_out2),
        .out3(bf_out3)
    );

    reg [1:0] bf_valid_pipe;

    always @(posedge clk) begin
        if (rst) begin
            coeff0 <= {DW{1'b0}};
            coeff1 <= {DW{1'b0}};
            coeff2 <= {DW{1'b0}};
            coeff3 <= {DW{1'b0}};
            tw_s0_b0 <= {DW{1'b0}};
            tw_s0_b1 <= {DW{1'b0}};
            tw_s1_b0 <= {DW{1'b0}};
            tw_s1_b1 <= {DW{1'b0}};
            bf_valid_pipe <= 2'b00;
            bf_valid <= 1'b0;
            mul_valid <= 1'b0;
            rd_src_sel_r <= RAM_A;
        end else begin
            if (rd_en === 1'b1) begin
                rd_src_sel_r <= rd_src_sel;
            end

            if (rd_capture_en && !rd_capture_sel) begin
                coeff0 <= ram_rd0;
                coeff1 <= ram_rd1;
            end

            if (rd_capture_en && rd_capture_sel) begin
                coeff2 <= ram_rd0;
                coeff3 <= ram_rd1;
            end

            if (tw_load) begin
                tw_s0_b0 <= tw_force_neg_s0_b0 ? K_INV2_NEG_MOD_Q : rom_s0_b0;
                tw_s0_b1 <= tw_force_neg_s0_b1 ? K_INV2_NEG_MOD_Q : rom_s0_b1;
                tw_s1_b0 <= tw_force_neg_s1_b0 ? K_INV2_NEG_MOD_Q : rom_s1_b0;
                tw_s1_b1 <= tw_force_neg_s1_b1 ? K_INV2_NEG_MOD_Q : rom_s1_b1;
            end

            bf_valid <= bf_valid_pipe[1];
            bf_valid_pipe <= {bf_valid_pipe[0], bf_start};
            mul_valid <= mul_rd_en;
        end
    end

endmodule
