`timescale 1ns / 1ps

// Microstep controller for Kyber polynomial multiplication.
// Transform passes 0/1, 2/3, and 4/5 use the integrated two-stage 2x2 block.
// Pass 6 uses the same block with stage 1 bypassed because Kyber has seven
// incomplete-NTT stages rather than eight.
module ntt_3ram_fsm #(
    parameter AW = 8,
    parameter DW = 12
)(
    input  wire              clk,
    input  wire              rst,
    input  wire              start,
    input  wire [DW-1:0]     ram_a_rd0,
    input  wire [DW-1:0]     ram_a_rd1,
    input  wire [DW-1:0]     ram_b_rd0,
    input  wire [DW-1:0]     ram_b_rd1,
    input  wire [DW-1:0]     ram_c_rd0,
    input  wire [DW-1:0]     ram_c_rd1,
    input  wire [DW-1:0]     block_out0,
    input  wire [DW-1:0]     block_out1,
    input  wire [DW-1:0]     block_out2,
    input  wire [DW-1:0]     block_out3,
    input  wire [DW-1:0]     mul_result0,
    input  wire [DW-1:0]     mul_result1,
    input  wire [DW-1:0]     tw_zeta,

    output wire              core_active,
    output reg  [AW-1:0]     core_addr0,
    output reg  [AW-1:0]     core_addr1,
    output reg               core_wr_en,
    output reg  [1:0]        core_wr_ram_sel,
    output reg  [DW-1:0]     core_wr_data0,
    output reg  [DW-1:0]     core_wr_data1,

    output wire              block_mode,
    output wire              block_two_stage,
    output reg  [DW-1:0]     block_in0,
    output reg  [DW-1:0]     block_in1,
    output reg  [DW-1:0]     block_in2,
    output reg  [DW-1:0]     block_in3,
    output wire [6:0]        block_tw_addr0,
    output wire [6:0]        block_tw_addr1,
    output wire [6:0]        block_tw_addr2,
    output wire [6:0]        block_tw_addr3,
    output wire [6:0]        tw_addr,
    output wire              tw_negate,

    output reg  [DW-1:0]     mul_a0,
    output reg  [DW-1:0]     mul_b0,
    output reg  [DW-1:0]     mul_a1,
    output reg  [DW-1:0]     mul_b1,
    output reg               busy,
    output reg               done,
    output reg               error,
    output wire [2:0]        phase_dbg,
    output wire [1:0]        pass_dbg,
    output wire [6:0]        op_dbg
);
    localparam [1:0] RAM_A = 2'd0;
    localparam [1:0] RAM_B = 2'd1;
    localparam [1:0] RAM_C = 2'd2;

    localparam [2:0] PH_NTT_A = 3'd0;
    localparam [2:0] PH_NTT_B = 3'd1;
    localparam [2:0] PH_BASE  = 3'd2;
    localparam [2:0] PH_INTT  = 3'd3;
    localparam [2:0] PH_NORM  = 3'd4;
    localparam [2:0] PH_DONE  = 3'd5;

    localparam [DW-1:0] Q = 12'd3329;
    localparam [DW-1:0] INV_128 = 12'd3303;

    reg [2:0] phase;
    reg [2:0] stage;
    reg [3:0] microstep;
    reg [5:0] block_index;
    reg [6:0] pair_index;

    reg [DW-1:0] a0_q, a1_q, b0_q, b1_q;
    reg [DW-1:0] p00_q, p11_q, p01_q, p10_q, p11z_q;

    wire inverse_phase = (phase == PH_INTT);
    wire transform_phase = (phase == PH_NTT_A) ||
                           (phase == PH_NTT_B) ||
                           (phase == PH_INTT);
    wire [AW-1:0] block_addr0;
    wire [AW-1:0] block_addr1;
    wire [AW-1:0] block_addr2;
    wire [AW-1:0] block_addr3;
    wire [AW-1:0] pair_addr0 = pair_index << 1;
    wire [AW-1:0] pair_addr1 = (pair_index << 1) | 1'b1;

    assign core_active = busy;
    assign block_mode = inverse_phase;
    assign block_two_stage = (stage != 3'd6);
    assign tw_addr = 7'd64 + (pair_index >> 1);
    assign tw_negate = pair_index[0];
    assign phase_dbg = phase;
    assign pass_dbg = stage[2:1];
    assign op_dbg = ((phase == PH_BASE) || (phase == PH_NORM)) ? pair_index :
                                                                    {1'b0, block_index};

    ntt_2x2_schedule u_2x2_schedule (
        .inverse(inverse_phase),
        .stage(stage),
        .block_index(block_index),
        .addr0(block_addr0), .addr1(block_addr1),
        .addr2(block_addr2), .addr3(block_addr3),
        .tw_addr0(block_tw_addr0), .tw_addr1(block_tw_addr1),
        .tw_addr2(block_tw_addr2), .tw_addr3(block_tw_addr3)
    );

    function automatic [DW-1:0] add_mod_q;
        input [DW-1:0] x;
        input [DW-1:0] y;
        reg [DW:0] sum;
        begin
            sum = x + y;
            if (sum >= Q)
                add_mod_q = sum - Q;
            else
                add_mod_q = sum;
        end
    endfunction

    // RAM ownership and arithmetic selection for the current microstep.
    always @* begin
        core_addr0 = {AW{1'b0}};
        core_addr1 = {AW{1'b0}};
        core_wr_en = 1'b0;
        core_wr_ram_sel = RAM_C;
        core_wr_data0 = {DW{1'b0}};
        core_wr_data1 = {DW{1'b0}};
        mul_a0 = {DW{1'b0}};
        mul_b0 = {DW{1'b0}};
        mul_a1 = {DW{1'b0}};
        mul_b1 = {DW{1'b0}};

        if (transform_phase) begin
            if ((microstep == 4'd0) || (microstep == 4'd1)) begin
                core_addr0 = block_addr0;
                core_addr1 = block_addr1;
            end else if ((microstep == 4'd2) || (microstep == 4'd3)) begin
                core_addr0 = block_addr2;
                core_addr1 = block_addr3;
            end else if (microstep == 4'd7) begin
                core_addr0 = block_addr0;
                core_addr1 = block_addr1;
                core_wr_en = 1'b1;
                core_wr_ram_sel = (phase == PH_NTT_A) ? RAM_A :
                                  (phase == PH_NTT_B) ? RAM_B : RAM_C;
                core_wr_data0 = block_out0;
                core_wr_data1 = block_out1;
            end else if (microstep == 4'd8) begin
                core_addr0 = block_addr2;
                core_addr1 = block_addr3;
                core_wr_en = 1'b1;
                core_wr_ram_sel = (phase == PH_NTT_A) ? RAM_A :
                                  (phase == PH_NTT_B) ? RAM_B : RAM_C;
                core_wr_data0 = block_out2;
                core_wr_data1 = block_out3;
            end
        end else if (phase == PH_BASE) begin
            core_addr0 = pair_addr0;
            core_addr1 = pair_addr1;
            case (microstep)
                4'd2: begin
                    mul_a0 = a0_q; mul_b0 = b0_q;
                    mul_a1 = a1_q; mul_b1 = b1_q;
                end
                4'd3: begin
                    mul_a0 = a0_q; mul_b0 = b1_q;
                    mul_a1 = a1_q; mul_b1 = b0_q;
                end
                4'd4: begin
                    mul_a0 = p11_q; mul_b0 = tw_zeta;
                end
                4'd5: begin
                    core_wr_en = 1'b1;
                    core_wr_ram_sel = RAM_C;
                    core_wr_data0 = add_mod_q(p00_q, p11z_q);
                    core_wr_data1 = add_mod_q(p01_q, p10_q);
                end
                default: begin end
            endcase
        end else if (phase == PH_NORM) begin
            core_addr0 = pair_addr0;
            core_addr1 = pair_addr1;
            if (microstep == 4'd2) begin
                mul_a0 = a0_q; mul_b0 = INV_128;
                mul_a1 = a1_q; mul_b1 = INV_128;
                core_wr_en = 1'b1;
                core_wr_ram_sel = RAM_C;
                core_wr_data0 = mul_result0;
                core_wr_data1 = mul_result1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            phase <= PH_NTT_A;
            stage <= 3'd0;
            microstep <= 4'd0;
            block_index <= 6'd0;
            pair_index <= 7'd0;
            block_in0 <= {DW{1'b0}};
            block_in1 <= {DW{1'b0}};
            block_in2 <= {DW{1'b0}};
            block_in3 <= {DW{1'b0}};
            a0_q <= {DW{1'b0}};
            a1_q <= {DW{1'b0}};
            b0_q <= {DW{1'b0}};
            b1_q <= {DW{1'b0}};
            p00_q <= {DW{1'b0}};
            p11_q <= {DW{1'b0}};
            p01_q <= {DW{1'b0}};
            p10_q <= {DW{1'b0}};
            p11z_q <= {DW{1'b0}};
            busy <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                if (start) begin
                    phase <= PH_NTT_A;
                    stage <= 3'd0;
                    microstep <= 4'd0;
                    block_index <= 6'd0;
                    pair_index <= 7'd0;
                    busy <= 1'b1;
                    error <= 1'b0;
                end
            end else if (transform_phase) begin
                case (microstep)
                    4'd0: microstep <= 4'd1;
                    4'd1: begin
                        if (phase == PH_NTT_A) begin
                            block_in0 <= ram_a_rd0; block_in1 <= ram_a_rd1;
                            if ((ram_a_rd0 >= Q) || (ram_a_rd1 >= Q)) begin
                                busy <= 1'b0; error <= 1'b1;
                            end else microstep <= 4'd2;
                        end else if (phase == PH_NTT_B) begin
                            block_in0 <= ram_b_rd0; block_in1 <= ram_b_rd1;
                            if ((ram_b_rd0 >= Q) || (ram_b_rd1 >= Q)) begin
                                busy <= 1'b0; error <= 1'b1;
                            end else microstep <= 4'd2;
                        end else begin
                            block_in0 <= ram_c_rd0; block_in1 <= ram_c_rd1;
                            if ((ram_c_rd0 >= Q) || (ram_c_rd1 >= Q)) begin
                                busy <= 1'b0; error <= 1'b1;
                            end else microstep <= 4'd2;
                        end
                    end
                    4'd2: microstep <= 4'd3;
                    4'd3: begin
                        if (phase == PH_NTT_A) begin
                            block_in2 <= ram_a_rd0; block_in3 <= ram_a_rd1;
                            if ((ram_a_rd0 >= Q) || (ram_a_rd1 >= Q)) begin
                                busy <= 1'b0; error <= 1'b1;
                            end else microstep <= 4'd4;
                        end else if (phase == PH_NTT_B) begin
                            block_in2 <= ram_b_rd0; block_in3 <= ram_b_rd1;
                            if ((ram_b_rd0 >= Q) || (ram_b_rd1 >= Q)) begin
                                busy <= 1'b0; error <= 1'b1;
                            end else microstep <= 4'd4;
                        end else begin
                            block_in2 <= ram_c_rd0; block_in3 <= ram_c_rd1;
                            if ((ram_c_rd0 >= Q) || (ram_c_rd1 >= Q)) begin
                                busy <= 1'b0; error <= 1'b1;
                            end else microstep <= 4'd4;
                        end
                    end
                    4'd4: microstep <= 4'd5;
                    4'd5: microstep <= 4'd6;
                    4'd6: microstep <= 4'd7;
                    4'd7: microstep <= 4'd8;
                    default: begin
                        microstep <= 4'd0;
                        if (block_index == 6'd63) begin
                            block_index <= 6'd0;
                            if (stage == 3'd6) begin
                                stage <= 3'd0;
                                if (phase == PH_NTT_A)
                                    phase <= PH_NTT_B;
                                else if (phase == PH_NTT_B) begin
                                    phase <= PH_BASE;
                                    pair_index <= 7'd0;
                                end else begin
                                    phase <= PH_NORM;
                                    pair_index <= 7'd0;
                                end
                            end else begin
                                stage <= stage + 3'd2;
                            end
                        end else begin
                            block_index <= block_index + 1'b1;
                        end
                    end
                endcase
            end else if (phase == PH_BASE) begin
                case (microstep)
                    4'd0: microstep <= 4'd1;
                    4'd1: begin
                        a0_q <= ram_a_rd0; a1_q <= ram_a_rd1;
                        b0_q <= ram_b_rd0; b1_q <= ram_b_rd1;
                        if ((ram_a_rd0 >= Q) || (ram_a_rd1 >= Q) ||
                            (ram_b_rd0 >= Q) || (ram_b_rd1 >= Q)) begin
                            busy <= 1'b0; error <= 1'b1;
                        end else microstep <= 4'd2;
                    end
                    4'd2: begin
                        p00_q <= mul_result0; p11_q <= mul_result1;
                        microstep <= 4'd3;
                    end
                    4'd3: begin
                        p01_q <= mul_result0; p10_q <= mul_result1;
                        microstep <= 4'd4;
                    end
                    4'd4: begin
                        p11z_q <= mul_result0;
                        microstep <= 4'd5;
                    end
                    default: begin
                        microstep <= 4'd0;
                        if (pair_index == 7'd127) begin
                            pair_index <= 7'd0;
                            block_index <= 6'd0;
                            stage <= 3'd0;
                            phase <= PH_INTT;
                        end else pair_index <= pair_index + 1'b1;
                    end
                endcase
            end else if (phase == PH_NORM) begin
                case (microstep)
                    4'd0: microstep <= 4'd1;
                    4'd1: begin
                        a0_q <= ram_c_rd0; a1_q <= ram_c_rd1;
                        if ((ram_c_rd0 >= Q) || (ram_c_rd1 >= Q)) begin
                            busy <= 1'b0; error <= 1'b1;
                        end else microstep <= 4'd2;
                    end
                    default: begin
                        microstep <= 4'd0;
                        if (pair_index == 7'd127) begin
                            phase <= PH_DONE;
                        end else pair_index <= pair_index + 1'b1;
                    end
                endcase
            end else begin
                busy <= 1'b0;
                done <= 1'b1;
            end
        end
    end
endmodule
