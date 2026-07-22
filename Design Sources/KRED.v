`timescale 1ns / 1ps

// KRED for Kyber (q=3329, k=13, m=8)
// Input:  C[23:0]
// Output: D_raw is SIGNED and satisfies D_raw ≡ 13*C (mod 3329)
//
// D_raw = 13*C_low - C_high
// where C_low  = C[7:0]
//       C_high = C[23:8]

module kred_kyber (
    input  wire [23:0] C,
    output wire signed [17:0] D_raw   // range approx [-65535 .. 3315]
);

    localparam integer K = 13;

    wire [7:0]  C_low  = C[7:0];
    wire [15:0] C_high = C[23:8];

    // 13*x = (x<<3) + (x<<2) + x
    wire [11:0] k_times_low = (C_low << 3) + (C_low << 2) + C_low; // 0..3315

    // Signed subtraction: (13*C_low) - C_high
    assign D_raw = $signed({1'b0, k_times_low}) - $signed({1'b0, C_high});

endmodule
