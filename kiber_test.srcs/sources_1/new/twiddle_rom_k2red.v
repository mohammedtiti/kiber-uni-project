`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 25.01.2026 10:49:28
// Design Name: 
// Module Name: twiddle_rom_k2red
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


module twiddle_rom_k2red#(
    parameter AW = 7,
    parameter DW = 12,
    parameter MEMFILE = "twiddle_k2red.mem"
)(
    input  wire              clk,
    input  wire [AW-1:0]      addr,
    output reg  [DW-1:0]      tf
);

    (* rom_style = "block" *) reg [DW-1:0] rom [0:(1<<AW)-1];

    initial begin
        $readmemh(MEMFILE, rom);
    end

    always @(posedge clk) begin
        tf <= rom[addr];   // synchronous read (1-cycle latency)
    end

endmodule