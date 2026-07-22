`timescale 1ns / 1ps

// K2-RED for Kyber q=3329 with k=13 and byte-sized reduction steps.
// The result is 13^2*C = 169*C (mod q), canonicalized to [0,3328].
module k2red_kyber (
    input  wire [23:0] C,
    output wire [11:0] R
);
    localparam integer Q = 3329;

    function automatic [11:0] normalize_step1;
        input signed [16:0] value_in;
        reg signed [17:0] value;
        begin
            value = value_in;
            if (value < 0)       value = value + (20*Q);
            if (value >= 16*Q)   value = value - (16*Q);
            if (value >= 8*Q)    value = value - (8*Q);
            if (value >= 4*Q)    value = value - (4*Q);
            if (value >= 2*Q)    value = value - (2*Q);
            if (value >= Q)      value = value - Q;
            normalize_step1 = value[11:0];
        end
    endfunction

    function automatic [11:0] normalize_step2;
        input signed [12:0] value_in;
        reg signed [13:0] value;
        begin
            value = value_in;
            if (value < 0)  value = value + Q;
            if (value >= Q) value = value - Q;
            normalize_step2 = value[11:0];
        end
    endfunction

    wire [7:0] cl = C[7:0];
    wire [15:0] ch = C[23:8];
    wire [11:0] k_cl_1 = (cl << 3) + (cl << 2) + cl;
    wire signed [16:0] step1 = $signed({1'b0, k_cl_1}) -
                               $signed({1'b0, ch});
    wire [11:0] step1_mod_q = normalize_step1(step1);

    wire [7:0] step1_low = step1_mod_q[7:0];
    wire [7:0] step1_high = {4'b0, step1_mod_q[11:8]};
    wire [11:0] k_cl_2 = (step1_low << 3) +
                          (step1_low << 2) + step1_low;
    wire signed [12:0] step2 = $signed({1'b0, k_cl_2}) -
                               $signed({1'b0, step1_high});

    assign R = normalize_step2(step2);
endmodule
