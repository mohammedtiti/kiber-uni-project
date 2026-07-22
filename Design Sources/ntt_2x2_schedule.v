`timescale 1ns / 1ps

// Address and twiddle generator for one integrated Kyber 2x2 operation.
// Every pass contains 64 four-coefficient blocks.  Stages 0, 2, and 4 merge
// two transform stages; stage 6 issues two independent final-stage butterflies.
module ntt_2x2_schedule (
    input  wire       inverse,
    input  wire [2:0] stage,
    input  wire [5:0] block_index,
    output reg  [7:0] addr0,
    output reg  [7:0] addr1,
    output reg  [7:0] addr2,
    output reg  [7:0] addr3,
    output reg  [6:0] tw_addr0,
    output reg  [6:0] tw_addr1,
    output reg  [6:0] tw_addr2,
    output reg  [6:0] tw_addr3
);
    always @* begin
        addr0 = 8'd0;
        addr1 = 8'd0;
        addr2 = 8'd0;
        addr3 = 8'd0;
        tw_addr0 = 7'd1;
        tw_addr1 = 7'd1;
        tw_addr2 = 7'd1;
        tw_addr3 = 7'd1;

        if (inverse) begin
            case (stage)
                3'd0: begin
                    addr0 = {block_index[5:1], 3'b000} + block_index[0];
                    addr1 = {block_index[5:1], 3'b000} + block_index[0] + 8'd2;
                    addr2 = {block_index[5:1], 3'b000} + block_index[0] + 8'd4;
                    addr3 = {block_index[5:1], 3'b000} + block_index[0] + 8'd6;
                    tw_addr0 = 7'd127 - ({2'd0, block_index[5:1]} << 1);
                    tw_addr1 = 7'd126 - ({2'd0, block_index[5:1]} << 1);
                    tw_addr2 = 7'd63 - {2'd0, block_index[5:1]};
                    tw_addr3 = 7'd63 - {2'd0, block_index[5:1]};
                end
                3'd2: begin
                    addr0 = {block_index[5:3], 5'b00000} + {5'd0, block_index[2:0]};
                    addr1 = {block_index[5:3], 5'b00000} + {5'd0, block_index[2:0]} + 8'd8;
                    addr2 = {block_index[5:3], 5'b00000} + {5'd0, block_index[2:0]} + 8'd16;
                    addr3 = {block_index[5:3], 5'b00000} + {5'd0, block_index[2:0]} + 8'd24;
                    tw_addr0 = 7'd31 - ({4'd0, block_index[5:3]} << 1);
                    tw_addr1 = 7'd30 - ({4'd0, block_index[5:3]} << 1);
                    tw_addr2 = 7'd15 - {4'd0, block_index[5:3]};
                    tw_addr3 = 7'd15 - {4'd0, block_index[5:3]};
                end
                3'd4: begin
                    addr0 = {block_index[5], 7'b0000000} + {3'd0, block_index[4:0]};
                    addr1 = {block_index[5], 7'b0000000} + {3'd0, block_index[4:0]} + 8'd32;
                    addr2 = {block_index[5], 7'b0000000} + {3'd0, block_index[4:0]} + 8'd64;
                    addr3 = {block_index[5], 7'b0000000} + {3'd0, block_index[4:0]} + 8'd96;
                    tw_addr0 = 7'd7 - ({6'd0, block_index[5]} << 1);
                    tw_addr1 = 7'd6 - ({6'd0, block_index[5]} << 1);
                    tw_addr2 = 7'd3 - {6'd0, block_index[5]};
                    tw_addr3 = 7'd3 - {6'd0, block_index[5]};
                end
                default: begin
                    addr0 = {1'b0, block_index, 1'b0};
                    addr1 = {1'b0, block_index, 1'b0} + 8'd128;
                    addr2 = {1'b0, block_index, 1'b0} + 8'd1;
                    addr3 = {1'b0, block_index, 1'b0} + 8'd129;
                end
            endcase
        end else begin
            case (stage)
                3'd0: begin
                    addr0 = {2'd0, block_index};
                    addr1 = {2'd0, block_index} + 8'd64;
                    addr2 = {2'd0, block_index} + 8'd128;
                    addr3 = {2'd0, block_index} + 8'd192;
                    tw_addr0 = 7'd1;
                    tw_addr1 = 7'd1;
                    tw_addr2 = 7'd2;
                    tw_addr3 = 7'd3;
                end
                3'd2: begin
                    addr0 = {block_index[5:4], 6'b000000} + {4'd0, block_index[3:0]};
                    addr1 = {block_index[5:4], 6'b000000} + {4'd0, block_index[3:0]} + 8'd16;
                    addr2 = {block_index[5:4], 6'b000000} + {4'd0, block_index[3:0]} + 8'd32;
                    addr3 = {block_index[5:4], 6'b000000} + {4'd0, block_index[3:0]} + 8'd48;
                    tw_addr0 = 7'd4 + {5'd0, block_index[5:4]};
                    tw_addr1 = 7'd4 + {5'd0, block_index[5:4]};
                    tw_addr2 = 7'd8 + ({5'd0, block_index[5:4]} << 1);
                    tw_addr3 = 7'd9 + ({5'd0, block_index[5:4]} << 1);
                end
                3'd4: begin
                    addr0 = {block_index[5:2], 4'b0000} + {6'd0, block_index[1:0]};
                    addr1 = {block_index[5:2], 4'b0000} + {6'd0, block_index[1:0]} + 8'd4;
                    addr2 = {block_index[5:2], 4'b0000} + {6'd0, block_index[1:0]} + 8'd8;
                    addr3 = {block_index[5:2], 4'b0000} + {6'd0, block_index[1:0]} + 8'd12;
                    tw_addr0 = 7'd16 + {3'd0, block_index[5:2]};
                    tw_addr1 = 7'd16 + {3'd0, block_index[5:2]};
                    tw_addr2 = 7'd32 + ({3'd0, block_index[5:2]} << 1);
                    tw_addr3 = 7'd33 + ({3'd0, block_index[5:2]} << 1);
                end
                default: begin
                    addr0 = {block_index, 2'b00};
                    addr1 = {block_index, 2'b00} + 8'd1;
                    addr2 = {block_index, 2'b00} + 8'd2;
                    addr3 = {block_index, 2'b00} + 8'd3;
                    tw_addr0 = 7'd64 + block_index;
                    tw_addr1 = 7'd64 + block_index;
                end
            endcase
        end
    end
endmodule
