`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.01.2026 09:45:48
// Design Name: 
// Module Name: butterfly_FF_wrap
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module butterfly_FF_wrap(
    input  wire        clk,
    input  wire        mode_in,
    input  wire [11:0] u_in,
    input  wire [11:0] v_in,
    input  wire [11:0] tw_scaled,
    output reg  [11:0] out0,
    output reg  [11:0] out1
    );
    
    // register inputs
    reg        mode_r;
    reg [11:0] u_r, v_r, tw_r;

    always @(posedge clk) begin
        mode_r <= mode_in;
        u_r    <= u_in;
        v_r    <= v_in;
        tw_r   <= tw_scaled;
    end

    // combinational butterfly
    wire [11:0] out0_c, out1_c;
    butterfly_k2red_kyber dut (
        .mode(mode_r),
        .u_in(u_r),
        .v_in(v_r),
        .tw_scaled(tw_r),
        .out0(out0_c),
        .out1(out1_c)
    );

    // register outputs
    always @(posedge clk) begin
        out0 <= out0_c;
        out1 <= out1_c;
    end
    
endmodule
