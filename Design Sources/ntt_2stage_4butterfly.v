`timescale 1ns / 1ps

// Four-butterfly block for two radix-2 NTT/INTT stages.
//
// mode_in = 0: NTT, CT order
//   stage 0: (in0,in2), (in1,in3)
//   stage 1: (s0,s1),  (s2,s3)
//
// mode_in = 1: INTT, GS order
//   stage 0: (in0,in1), (in2,in3)
//   stage 1: (s0,s2),  (s1,s3)
module ntt_2stage_4butterfly (
    input  wire        clk,
    input  wire        mode_in,

    input  wire [11:0] in0,
    input  wire [11:0] in1,
    input  wire [11:0] in2,
    input  wire [11:0] in3,

    input  wire [11:0] tw_s0_b0,
    input  wire [11:0] tw_s0_b1,
    input  wire [11:0] tw_s1_b0,
    input  wire [11:0] tw_s1_b1,

    output reg  [11:0] out0,
    output reg  [11:0] out1,
    output reg  [11:0] out2,
    output reg  [11:0] out3
);

    reg        mode_r0;
    reg        mode_r1;
    reg [11:0] in0_r, in1_r, in2_r, in3_r;
    reg [11:0] tw_s0_b0_r, tw_s0_b1_r;
    reg [11:0] tw_s1_b0_r0, tw_s1_b1_r0;
    reg [11:0] tw_s1_b0_r1, tw_s1_b1_r1;

    wire [11:0] s0_b0_v = mode_r0 ? in1_r : in2_r;
    wire [11:0] s0_b1_u = mode_r0 ? in2_r : in1_r;

    wire [11:0] s0_b0_out0, s0_b0_out1;
    wire [11:0] s0_b1_out0, s0_b1_out1;

    butterfly_k2red_kyber u_stage0_b0 (
        .mode(mode_r0),
        .u_in(in0_r),
        .v_in(s0_b0_v),
        .tw_scaled(tw_s0_b0_r),
        .out0(s0_b0_out0),
        .out1(s0_b0_out1)
    );

    butterfly_k2red_kyber u_stage0_b1 (
        .mode(mode_r0),
        .u_in(s0_b1_u),
        .v_in(in3_r),
        .tw_scaled(tw_s0_b1_r),
        .out0(s0_b1_out0),
        .out1(s0_b1_out1)
    );

    reg [11:0] mid0, mid1, mid2, mid3;

    wire [11:0] s1_b0_v = mode_r1 ? mid2 : mid1;
    wire [11:0] s1_b1_u = mode_r1 ? mid1 : mid2;

    wire [11:0] s1_b0_out0, s1_b0_out1;
    wire [11:0] s1_b1_out0, s1_b1_out1;

    butterfly_k2red_kyber u_stage1_b0 (
        .mode(mode_r1),
        .u_in(mid0),
        .v_in(s1_b0_v),
        .tw_scaled(tw_s1_b0_r1),
        .out0(s1_b0_out0),
        .out1(s1_b0_out1)
    );

    butterfly_k2red_kyber u_stage1_b1 (
        .mode(mode_r1),
        .u_in(s1_b1_u),
        .v_in(mid3),
        .tw_scaled(tw_s1_b1_r1),
        .out0(s1_b1_out0),
        .out1(s1_b1_out1)
    );

    always @(posedge clk) begin
        mode_r0 <= mode_in;
        in0_r <= in0;
        in1_r <= in1;
        in2_r <= in2;
        in3_r <= in3;
        tw_s0_b0_r <= tw_s0_b0;
        tw_s0_b1_r <= tw_s0_b1;
        tw_s1_b0_r0 <= tw_s1_b0;
        tw_s1_b1_r0 <= tw_s1_b1;

        mode_r1 <= mode_r0;
        tw_s1_b0_r1 <= tw_s1_b0_r0;
        tw_s1_b1_r1 <= tw_s1_b1_r0;

        if (mode_r0) begin
            mid0 <= s0_b0_out0;
            mid1 <= s0_b0_out1;
            mid2 <= s0_b1_out0;
            mid3 <= s0_b1_out1;
        end else begin
            mid0 <= s0_b0_out0;
            mid1 <= s0_b1_out0;
            mid2 <= s0_b0_out1;
            mid3 <= s0_b1_out1;
        end

        if (mode_r1) begin
            out0 <= s1_b0_out0;
            out1 <= s1_b1_out0;
            out2 <= s1_b0_out1;
            out3 <= s1_b1_out1;
        end else begin
            out0 <= s1_b0_out0;
            out1 <= s1_b0_out1;
            out2 <= s1_b1_out0;
            out3 <= s1_b1_out1;
        end
    end

endmodule
