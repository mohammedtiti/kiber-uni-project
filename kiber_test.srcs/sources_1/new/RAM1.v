`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 04.02.2026
// Design Name:
// Module Name: dual_port_ram
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//   True Dual-Port RAM (2x Read/Write ports)
//   - Port A: addr_a, din_a, we_a, dout_a
//   - Port B: addr_b, din_b, we_b, dout_b
//   - Synchronous read (1-cycle latency) on both ports (BRAM-friendly)
//   - Optional memory initialization from MEMFILE using $readmemh
//
// Notes:
//   - Avoid writing the same address from both ports in the same cycle.
//   - Read-during-write behavior (same port writes and reads same addr) here is
//     "read-first" style: dout <= old mem[addr].
//
//////////////////////////////////////////////////////////////////////////////////

module RAM1 #(
    parameter AW      = 8,
    parameter DW      = 12,
    parameter MEMFILE = "RAM1.mem"
)(
    input  wire              clk,

    // Port A
    input  wire              we_a,
    input  wire [AW-1:0]     addr_a,
    input  wire [DW-1:0]     din_a,
    output reg  [DW-1:0]     dout_a,

    // Port B
    input  wire              we_b,
    input  wire [AW-1:0]     addr_b,
    input  wire [DW-1:0]     din_b,
    output reg  [DW-1:0]     dout_b
);

    (* ram_style = "block" *) reg [DW-1:0] ram [0:(1<<AW)-1];

    // Optional init (useful in sim; synthesis support depends on tool/device)
    initial begin
        if (MEMFILE != "") begin
            $readmemh(MEMFILE, ram);
        end
    end

    always @(posedge clk) begin
        dout_a <= ram[addr_a];
        if (we_a)
            ram[addr_a] <= din_a;
    end

    always @(posedge clk) begin
        dout_b <= ram[addr_b];
        if (we_b)
            ram[addr_b] <= din_b;
    end

endmodule
