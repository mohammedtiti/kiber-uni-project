`timescale 1ns / 1ps

// Controller for ntt_3ram_datapath.
//
// It runs:
//   1. NTT(A), ping-pong A <-> C
//   2. NTT(B), ping-pong B <-> C
//   3. pointwise multiply A*B -> C
//   4. INTT(C), ping-pong C <-> A
//
// The address generator processes two NTT/INTT stages per pass, so a 256-point
// transform uses four passes. The butterfly addresses use strides:
//   NTT : 64, 16, 4, 1
//   INTT: 1, 4, 16, 64
//
// The default twiddle address generator is intentionally isolated in one block
// below. If your ROM order differs, only that block should need adjustment.
module ntt_3ram_fsm #(
    parameter AW = 8,
    parameter TW_AW = 7
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              start,

    input  wire              bf_valid,
    input  wire              mul_valid,
    input  wire              ram_conflict,

    output reg               mode_in,

    output reg               rd_en,
    output reg  [1:0]        rd_src_sel,
    output reg  [AW-1:0]     rd_addr0,
    output reg  [AW-1:0]     rd_addr1,
    output reg               rd_capture_en,
    output reg               rd_capture_sel,

    output reg               wr_en,
    output reg  [1:0]        wr_dst_sel,
    output reg  [AW-1:0]     wr_addr0,
    output reg  [AW-1:0]     wr_addr1,
    output reg               wr_result_sel,

    output reg               mul_rd_en,
    output reg               mul_wr_en,
    output reg  [AW-1:0]     mul_addr0,
    output reg  [AW-1:0]     mul_addr1,

    output reg  [TW_AW-1:0]  tw_addr_s0_b0,
    output reg  [TW_AW-1:0]  tw_addr_s0_b1,
    output reg  [TW_AW-1:0]  tw_addr_s1_b0,
    output reg  [TW_AW-1:0]  tw_addr_s1_b1,
    output reg               tw_force_neg_s0_b0,
    output reg               tw_force_neg_s0_b1,
    output reg               tw_force_neg_s1_b0,
    output reg               tw_force_neg_s1_b1,
    output reg               tw_load,

    output reg               bf_start,

    output reg               busy,
    output reg               done,
    output reg               error,
    output reg  [2:0]        phase_dbg,
    output reg  [1:0]        pass_dbg,
    output reg  [6:0]        op_dbg
);

    localparam [1:0] RAM_A = 2'd0;
    localparam [1:0] RAM_B = 2'd1;
    localparam [1:0] RAM_C = 2'd2;

    localparam [2:0] PH_NTT_A = 3'd0;
    localparam [2:0] PH_NTT_B = 3'd1;
    localparam [2:0] PH_MUL   = 3'd2;
    localparam [2:0] PH_INTT  = 3'd3;
    localparam [2:0] PH_DONE  = 3'd4;

    localparam [4:0] ST_IDLE      = 5'd0;
    localparam [4:0] ST_SETUP     = 5'd1;
    localparam [4:0] ST_RD0       = 5'd2;
    localparam [4:0] ST_CAP0      = 5'd3;
    localparam [4:0] ST_RD1       = 5'd4;
    localparam [4:0] ST_CAP1      = 5'd5;
    localparam [4:0] ST_TW_WAIT   = 5'd6;
    localparam [4:0] ST_TW_LOAD   = 5'd7;
    localparam [4:0] ST_BF_START  = 5'd8;
    localparam [4:0] ST_BF_WAIT   = 5'd9;
    localparam [4:0] ST_WR0       = 5'd10;
    localparam [4:0] ST_WR1       = 5'd11;
    localparam [4:0] ST_NEXT_OP   = 5'd12;
    localparam [4:0] ST_NEXT_PASS = 5'd13;
    localparam [4:0] ST_MUL_RD    = 5'd14;
    localparam [4:0] ST_MUL_WAIT  = 5'd15;
    localparam [4:0] ST_MUL_WR    = 5'd16;
    localparam [4:0] ST_DONE      = 5'd17;
    localparam [4:0] ST_ERROR     = 5'd18;

    reg [4:0] state;
    reg [2:0] phase;
    reg [1:0] pass;
    reg [6:0] op;

    reg [AW-1:0] addr0;
    reg [AW-1:0] addr1;
    reg [AW-1:0] addr2;
    reg [AW-1:0] addr3;

    reg [1:0] src_ram;
    reg [1:0] dst_ram;

    wire is_intt = (phase == PH_INTT);
    wire [1:0] src_ram_w = (phase == PH_NTT_A) ? (pass[0] ? RAM_C : RAM_A) :
                           (phase == PH_NTT_B) ? (pass[0] ? RAM_C : RAM_B) :
                           (phase == PH_INTT)  ? (pass[0] ? RAM_A : RAM_C) : RAM_A;
    wire [1:0] dst_ram_w = (phase == PH_NTT_A) ? (pass[0] ? RAM_A : RAM_C) :
                           (phase == PH_NTT_B) ? (pass[0] ? RAM_B : RAM_C) :
                           (phase == PH_INTT)  ? (pass[0] ? RAM_C : RAM_A) : RAM_C;
    wire [AW-1:0] addr0_w = calc_addr(pass, op[5:0], 2'd0, is_intt);
    wire [AW-1:0] addr1_w = calc_addr(pass, op[5:0], 2'd1, is_intt);
    wire [AW-1:0] addr2_w = calc_addr(pass, op[5:0], 2'd2, is_intt);
    wire [AW-1:0] addr3_w = calc_addr(pass, op[5:0], 2'd3, is_intt);
    wire [TW_AW-1:0] tw_s0_b0_w = twiddle_addr(pass, addr0_w, 1'b0, is_intt);
    wire [TW_AW-1:0] tw_s0_b1_w = twiddle_addr(pass, is_intt ? addr2_w : addr1_w, 1'b0, is_intt);
    wire [TW_AW-1:0] tw_s1_b0_w = twiddle_addr(pass, addr0_w, 1'b1, is_intt);
    wire [TW_AW-1:0] tw_s1_b1_w = twiddle_addr(pass, is_intt ? addr1_w : addr2_w, 1'b1, is_intt);
    wire tw_force_neg_s0_b0_w = twiddle_force_neg_one(pass, addr0_w, 1'b0, is_intt);
    wire tw_force_neg_s0_b1_w = twiddle_force_neg_one(pass, is_intt ? addr2_w : addr1_w, 1'b0, is_intt);
    wire tw_force_neg_s1_b0_w = twiddle_force_neg_one(pass, addr0_w, 1'b1, is_intt);
    wire tw_force_neg_s1_b1_w = twiddle_force_neg_one(pass, is_intt ? addr1_w : addr2_w, 1'b1, is_intt);

    function automatic [AW-1:0] calc_addr;
        input [1:0] pass_i;
        input [5:0] op_i;
        input [1:0] lane_i;
        input       intt_i;
        reg [1:0] eff_pass;
        reg [AW-1:0] base;
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

    function automatic [TW_AW-1:0] twiddle_addr;
        input [1:0]    pass_i;
        input [AW-1:0] addr_i;
        input          second_stage_i;
        input          intt_i;
        reg [1:0]      eff_pass;
        reg [AW-1:0]   len;
        reg [AW-1:0]   j;
        reg [TW_AW:0]  exp;
        reg [TW_AW:0]  inv_exp;
        begin
            eff_pass = intt_i ? (2'd3 - pass_i) : pass_i;

            if (!second_stage_i) begin
                case (eff_pass)
                    2'd0: len = 8'd128;
                    2'd1: len = 8'd32;
                    2'd2: len = 8'd8;
                    default: len = 8'd2;
                endcase
                j = addr_i & (len - 1'b1);
                exp = j << (2*eff_pass);
            end else begin
                case (eff_pass)
                    2'd0: len = 8'd64;
                    2'd1: len = 8'd16;
                    2'd2: len = 8'd4;
                    default: len = 8'd1;
                endcase
                j = (len == 1) ? {AW{1'b0}} : (addr_i & (len - 1'b1));
                exp = j << ((2*eff_pass) + 1);
            end

            if (intt_i && exp != 0) begin
                inv_exp = {1'b1, {TW_AW{1'b0}}} - exp;
                twiddle_addr = inv_exp[TW_AW-1:0];
            end else begin
                twiddle_addr = exp[TW_AW-1:0];
            end
        end
    endfunction

    function automatic twiddle_force_neg_one;
        input [1:0]    pass_i;
        input [AW-1:0] addr_i;
        input          second_stage_i;
        input          intt_i;
        reg [1:0]      eff_pass;
        reg [AW-1:0]   len;
        reg [AW-1:0]   j;
        reg [TW_AW:0]  exp;
        begin
            eff_pass = intt_i ? (2'd3 - pass_i) : pass_i;

            if (!second_stage_i) begin
                case (eff_pass)
                    2'd0: len = 8'd128;
                    2'd1: len = 8'd32;
                    2'd2: len = 8'd8;
                    default: len = 8'd2;
                endcase
                j = addr_i & (len - 1'b1);
                exp = j << (2*eff_pass);
            end else begin
                case (eff_pass)
                    2'd0: len = 8'd64;
                    2'd1: len = 8'd16;
                    2'd2: len = 8'd4;
                    default: len = 8'd1;
                endcase
                j = (len == 1) ? {AW{1'b0}} : (addr_i & (len - 1'b1));
                exp = j << ((2*eff_pass) + 1);
            end

            twiddle_force_neg_one = intt_i && (exp == 0);
        end
    endfunction

    always @* begin
        case (phase)
            PH_NTT_A: begin
                src_ram = pass[0] ? RAM_C : RAM_A;
                dst_ram = pass[0] ? RAM_A : RAM_C;
            end
            PH_NTT_B: begin
                src_ram = pass[0] ? RAM_C : RAM_B;
                dst_ram = pass[0] ? RAM_B : RAM_C;
            end
            PH_INTT: begin
                src_ram = pass[0] ? RAM_A : RAM_C;
                dst_ram = pass[0] ? RAM_C : RAM_A;
            end
            default: begin
                src_ram = RAM_A;
                dst_ram = RAM_C;
            end
        endcase

        addr0 = calc_addr(pass, op[5:0], 2'd0, is_intt);
        addr1 = calc_addr(pass, op[5:0], 2'd1, is_intt);
        addr2 = calc_addr(pass, op[5:0], 2'd2, is_intt);
        addr3 = calc_addr(pass, op[5:0], 2'd3, is_intt);
    end

    task automatic clear_outputs;
        begin
            mode_in = 1'b0;
            rd_en = 1'b0;
            rd_src_sel = RAM_A;
            rd_addr0 = {AW{1'b0}};
            rd_addr1 = {AW{1'b0}};
            rd_capture_en = 1'b0;
            rd_capture_sel = 1'b0;
            wr_en = 1'b0;
            wr_dst_sel = RAM_A;
            wr_addr0 = {AW{1'b0}};
            wr_addr1 = {AW{1'b0}};
            wr_result_sel = 1'b0;
            mul_rd_en = 1'b0;
            mul_wr_en = 1'b0;
            mul_addr0 = {AW{1'b0}};
            mul_addr1 = {AW{1'b0}};
            tw_addr_s0_b0 = {TW_AW{1'b0}};
            tw_addr_s0_b1 = {TW_AW{1'b0}};
            tw_addr_s1_b0 = {TW_AW{1'b0}};
            tw_addr_s1_b1 = {TW_AW{1'b0}};
            tw_force_neg_s0_b0 = 1'b0;
            tw_force_neg_s0_b1 = 1'b0;
            tw_force_neg_s1_b0 = 1'b0;
            tw_force_neg_s1_b1 = 1'b0;
            tw_load = 1'b0;
            bf_start = 1'b0;
        end
    endtask

    always @* begin
        clear_outputs();
        mode_in = is_intt;

        tw_addr_s0_b0 = tw_s0_b0_w;
        tw_addr_s0_b1 = tw_s0_b1_w;
        tw_addr_s1_b0 = tw_s1_b0_w;
        tw_addr_s1_b1 = tw_s1_b1_w;
        tw_force_neg_s0_b0 = tw_force_neg_s0_b0_w;
        tw_force_neg_s0_b1 = tw_force_neg_s0_b1_w;
        tw_force_neg_s1_b0 = tw_force_neg_s1_b0_w;
        tw_force_neg_s1_b1 = tw_force_neg_s1_b1_w;

        case (state)
            ST_RD0: begin
                rd_en = 1'b1;
                rd_src_sel = src_ram_w;
                rd_addr0 = addr0_w;
                rd_addr1 = addr1_w;
            end
            ST_CAP0: begin
                rd_capture_en = 1'b1;
                rd_capture_sel = 1'b0;
            end
            ST_RD1: begin
                rd_en = 1'b1;
                rd_src_sel = src_ram_w;
                rd_addr0 = addr2_w;
                rd_addr1 = addr3_w;
            end
            ST_CAP1: begin
                rd_capture_en = 1'b1;
                rd_capture_sel = 1'b1;
            end
            ST_TW_LOAD: begin
                tw_load = 1'b1;
            end
            ST_BF_START: begin
                bf_start = 1'b1;
            end
            ST_WR0: begin
                wr_en = 1'b1;
                wr_dst_sel = dst_ram_w;
                wr_addr0 = addr0_w;
                wr_addr1 = addr1_w;
                wr_result_sel = 1'b0;
            end
            ST_WR1: begin
                wr_en = 1'b1;
                wr_dst_sel = dst_ram_w;
                wr_addr0 = addr2_w;
                wr_addr1 = addr3_w;
                wr_result_sel = 1'b1;
            end
            ST_MUL_RD: begin
                mul_rd_en = 1'b1;
                mul_addr0 = {op, 1'b0};
                mul_addr1 = {op, 1'b1};
            end
            ST_MUL_WAIT: begin
                mul_addr0 = {op, 1'b0};
                mul_addr1 = {op, 1'b1};
            end
            ST_MUL_WR: begin
                mul_wr_en = 1'b1;
                mul_addr0 = {op, 1'b0};
                mul_addr1 = {op, 1'b1};
            end
            default: begin
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            phase <= PH_NTT_A;
            pass <= 2'd0;
            op <= 7'd0;
            busy <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
            phase_dbg <= PH_NTT_A;
            pass_dbg <= 2'd0;
            op_dbg <= 7'd0;
        end else begin
            done <= 1'b0;
            phase_dbg <= phase;
            pass_dbg <= pass;
            op_dbg <= op;

            if (ram_conflict) begin
                state <= ST_ERROR;
                busy <= 1'b0;
                error <= 1'b1;
            end else begin
                case (state)
                    ST_IDLE: begin
                        busy <= 1'b0;
                        error <= 1'b0;
                        if (start) begin
                            busy <= 1'b1;
                            phase <= PH_NTT_A;
                            pass <= 2'd0;
                            op <= 7'd0;
                            state <= ST_SETUP;
                        end
                    end
                    ST_SETUP: state <= ST_RD0;
                    ST_RD0: state <= ST_CAP0;
                    ST_CAP0: state <= ST_RD1;
                    ST_RD1: state <= ST_CAP1;
                    ST_CAP1: state <= ST_TW_WAIT;
                    ST_TW_WAIT: state <= ST_TW_LOAD;
                    ST_TW_LOAD: state <= ST_BF_START;
                    ST_BF_START: state <= ST_BF_WAIT;
                    ST_BF_WAIT: begin
                        if (bf_valid) state <= ST_WR0;
                    end
                    ST_WR0: state <= ST_WR1;
                    ST_WR1: state <= ST_NEXT_OP;
                    ST_NEXT_OP: begin
                        if (op == 7'd63) begin
                            op <= 7'd0;
                            state <= ST_NEXT_PASS;
                        end else begin
                            op <= op + 7'd1;
                            state <= ST_RD0;
                        end
                    end
                    ST_NEXT_PASS: begin
                        if (pass == 2'd3) begin
                            pass <= 2'd0;
                            if (phase == PH_NTT_A) begin
                                phase <= PH_NTT_B;
                                state <= ST_SETUP;
                            end else if (phase == PH_NTT_B) begin
                                phase <= PH_MUL;
                                state <= ST_MUL_RD;
                            end else if (phase == PH_INTT) begin
                                phase <= PH_DONE;
                                state <= ST_DONE;
                            end else begin
                                state <= ST_ERROR;
                                error <= 1'b1;
                            end
                        end else begin
                            pass <= pass + 2'd1;
                            state <= ST_SETUP;
                        end
                    end
                    ST_MUL_RD: state <= ST_MUL_WAIT;
                    ST_MUL_WAIT: begin
                        if (mul_valid) state <= ST_MUL_WR;
                    end
                    ST_MUL_WR: begin
                        if (op == 7'd127) begin
                            op <= 7'd0;
                            phase <= PH_INTT;
                            pass <= 2'd0;
                            state <= ST_SETUP;
                        end else begin
                            op <= op + 7'd1;
                            state <= ST_MUL_RD;
                        end
                    end
                    ST_DONE: begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        state <= ST_IDLE;
                    end
                    ST_ERROR: begin
                        busy <= 1'b0;
                        error <= 1'b1;
                        if (!start) state <= ST_IDLE;
                    end
                    default: state <= ST_ERROR;
                endcase
            end
        end
    end

endmodule
