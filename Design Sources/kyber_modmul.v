`timescale 1ns / 1ps

// Canonical modular multiplication for Kyber q=3329 using the existing
// K2-RED primitive.  K2-RED returns 169*C (mod q), so the first reduction
// pre-scales b by inverse(169^2); the second reduction cancels the remaining
// Montgomery factor and returns a*b (mod q).
module kyber_modmul (
    input  wire [11:0] a,
    input  wire [11:0] b,
    output wire [11:0] r
);
    localparam [11:0] INV_169_SQUARED = 12'd1353;

    wire [23:0] scale_product = b * INV_169_SQUARED;
    wire [11:0] b_over_169;

    k2red_kyber u_scale (
        .C(scale_product),
        .R(b_over_169)
    );

    wire [23:0] product = a * b_over_169;

    k2red_kyber u_product (
        .C(product),
        .R(r)
    );
endmodule
