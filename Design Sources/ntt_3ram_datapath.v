`timescale 1ns / 1ps

// Three true-dual-port coefficient memories with explicit ownership.
// While core_active is high the controller owns all ports.  Otherwise the
// ports are available for loading or host reads.  During base multiplication
// the common core address pair reads A and B concurrently.
module ntt_3ram_datapath #(
    parameter AW = 8,
    parameter DW = 12,
    parameter RAM_A_MEMFILE = "",
    parameter RAM_B_MEMFILE = "",
    parameter RAM_C_MEMFILE = ""
)(
    input  wire              clk,

    input  wire              core_active,
    input  wire [AW-1:0]     core_addr0,
    input  wire [AW-1:0]     core_addr1,
    input  wire              core_wr_en,
    input  wire [1:0]        core_wr_ram_sel,
    input  wire [DW-1:0]     core_wr_data0,
    input  wire [DW-1:0]     core_wr_data1,

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

    output wire [DW-1:0]     ram_a_rd0,
    output wire [DW-1:0]     ram_a_rd1,
    output wire [DW-1:0]     ram_b_rd0,
    output wire [DW-1:0]     ram_b_rd1,
    output wire [DW-1:0]     ram_c_rd0,
    output wire [DW-1:0]     ram_c_rd1,
    output wire [DW-1:0]     host_rd_data0,
    output wire [DW-1:0]     host_rd_data1
);
    localparam [1:0] RAM_A = 2'd0;
    localparam [1:0] RAM_B = 2'd1;
    localparam [1:0] RAM_C = 2'd2;

    wire idle_load = !core_active && load_en;
    wire idle_read = !core_active && !load_en && host_rd_en;

    wire [AW-1:0] selected_addr0 = core_active ? core_addr0 :
                                        idle_load ? load_addr0 :
                                        idle_read ? host_rd_addr0 : {AW{1'b0}};
    wire [AW-1:0] selected_addr1 = core_active ? core_addr1 :
                                        idle_load ? load_addr1 :
                                        idle_read ? host_rd_addr1 : {AW{1'b0}};

    wire [DW-1:0] selected_data0 = core_active ? core_wr_data0 : load_data0;
    wire [DW-1:0] selected_data1 = core_active ? core_wr_data1 : load_data1;

    wire wr_a = (core_active && core_wr_en && core_wr_ram_sel == RAM_A) ||
                (idle_load && load_ram_sel == RAM_A);
    wire wr_b = (core_active && core_wr_en && core_wr_ram_sel == RAM_B) ||
                (idle_load && load_ram_sel == RAM_B);
    wire wr_c = (core_active && core_wr_en && core_wr_ram_sel == RAM_C) ||
                (idle_load && load_ram_sel == RAM_C);

    RAM1 #(.AW(AW), .DW(DW), .MEMFILE(RAM_A_MEMFILE)) u_ram_a (
        .clk(clk), .we_a(wr_a), .addr_a(selected_addr0), .din_a(selected_data0), .dout_a(ram_a_rd0),
        .we_b(wr_a), .addr_b(selected_addr1), .din_b(selected_data1), .dout_b(ram_a_rd1)
    );

    RAM1 #(.AW(AW), .DW(DW), .MEMFILE(RAM_B_MEMFILE)) u_ram_b (
        .clk(clk), .we_a(wr_b), .addr_a(selected_addr0), .din_a(selected_data0), .dout_a(ram_b_rd0),
        .we_b(wr_b), .addr_b(selected_addr1), .din_b(selected_data1), .dout_b(ram_b_rd1)
    );

    RAM1 #(.AW(AW), .DW(DW), .MEMFILE(RAM_C_MEMFILE)) u_ram_c (
        .clk(clk), .we_a(wr_c), .addr_a(selected_addr0), .din_a(selected_data0), .dout_a(ram_c_rd0),
        .we_b(wr_c), .addr_b(selected_addr1), .din_b(selected_data1), .dout_b(ram_c_rd1)
    );

    reg [1:0] host_sel_q;
    always @(posedge clk) begin
        if (idle_read)
            host_sel_q <= host_rd_ram_sel;
    end

    assign host_rd_data0 = (host_sel_q == RAM_A) ? ram_a_rd0 :
                           (host_sel_q == RAM_B) ? ram_b_rd0 :
                           (host_sel_q == RAM_C) ? ram_c_rd0 : {DW{1'b0}};
    assign host_rd_data1 = (host_sel_q == RAM_A) ? ram_a_rd1 :
                           (host_sel_q == RAM_B) ? ram_b_rd1 :
                           (host_sel_q == RAM_C) ? ram_c_rd1 : {DW{1'b0}};
endmodule
