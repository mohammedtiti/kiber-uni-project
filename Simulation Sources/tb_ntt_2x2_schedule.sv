`timescale 1ns/1ps

module tb_ntt_2x2_schedule;
  logic inverse;
  logic [2:0] stage;
  logic [5:0] block_index;
  wire [7:0] addr0, addr1, addr2, addr3;
  wire [6:0] tw_addr0, tw_addr1, tw_addr2, tw_addr3;
  integer inv_i, stage_i, block_i;
  integer len0, half_len, group_no, offset_no, base_no;
  integer e0, e1, e2, e3, t0, t1, t2, t3;

  ntt_2x2_schedule dut (
    .inverse(inverse), .stage(stage), .block_index(block_index),
    .addr0(addr0), .addr1(addr1), .addr2(addr2), .addr3(addr3),
    .tw_addr0(tw_addr0), .tw_addr1(tw_addr1),
    .tw_addr2(tw_addr2), .tw_addr3(tw_addr3)
  );

  task automatic fail(input string message);
    begin
      $display("FAIL inverse=%0d stage=%0d block=%0d: %s", inverse, stage, block_index, message);
      $fatal(1);
    end
  endtask

  initial begin
    for (inv_i = 0; inv_i < 2; inv_i = inv_i + 1) begin
      inverse = inv_i;
      for (stage_i = 0; stage_i <= 6; stage_i = stage_i + 2) begin
        stage = stage_i[2:0];
        for (block_i = 0; block_i < 64; block_i = block_i + 1) begin
          block_index = block_i[5:0];
          if (!inv_i) begin
            len0 = 128 >> stage_i;
            half_len = len0 >> 1;
            group_no = block_i / half_len;
            offset_no = block_i % half_len;
            base_no = group_no * 2 * len0 + offset_no;
            e0 = base_no; e1 = base_no + half_len;
            e2 = base_no + len0; e3 = base_no + len0 + half_len;
            t0 = (1 << stage_i) + group_no;
            t1 = t0;
            if (stage_i < 6) begin
              t2 = (2 << stage_i) + 2*group_no;
              t3 = t2 + 1;
            end else begin
              t2 = 1; t3 = 1;
            end
          end else if (stage_i < 6) begin
            len0 = 2 << stage_i;
            group_no = block_i / len0;
            offset_no = block_i % len0;
            base_no = group_no * 4 * len0 + offset_no;
            e0 = base_no; e1 = base_no + len0;
            e2 = base_no + 2*len0; e3 = base_no + 3*len0;
            t0 = (127 >> stage_i) - 2*group_no;
            t1 = t0 - 1;
            t2 = (127 >> (stage_i+1)) - group_no;
            t3 = t2;
          end else begin
            e0 = 2*block_i; e1 = e0 + 128;
            e2 = e0 + 1; e3 = e0 + 129;
            t0 = 1; t1 = 1; t2 = 1; t3 = 1;
          end
          #1;
          if (addr0 !== e0 || addr1 !== e1 || addr2 !== e2 || addr3 !== e3)
            fail("address mismatch");
          if (tw_addr0 !== t0 || tw_addr1 !== t1 ||
              tw_addr2 !== t2 || tw_addr3 !== t3)
            fail("twiddle-address mismatch");
        end
      end
    end
    $display("PASS: all 512 forward/inverse 2x2 schedule entries verified.");
    $finish;
  end
endmodule
