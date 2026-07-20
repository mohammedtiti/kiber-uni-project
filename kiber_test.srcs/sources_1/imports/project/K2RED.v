// K2-RED for Kyber (q=3329, k=13, m=8)
// Computes: R ? k^2 * C (mod q)  with k=13, q = k*2^8 + 1
// Input:  C[23:0]  (e.g., product of two values < q, fits in 24 bits)
// Output: R[11:0]  in [0..3328]
//
// Algorithm (from paper's K2-RED idea):
// Step1: C'  = k * Cl - Ch      where Cl=C[7:0],  Ch=C[23:8]
// Step2: R'  = k * C'l - C'h    where C'l = low8(C'), C'h = high8(low16(C'))
// Final: normalize to [0,q)
//
// NOTE: This is NOT two instantiated KRED blocks; it's the fused 2-step version.

module k2red_kyber (
    input  wire [23:0] C,
    output reg  [11:0] R
);
    localparam integer Q = 3329;

    // ---- Split input C into chunks (m=8) ----
    wire [7:0]  Cl = C[7:0];
    wire [15:0] Ch = C[23:8];

    // ---- Step 1: t1 = 13*Cl - Ch (signed) ----
    // 13*x = (x<<3) + (x<<2) + x
    wire [11:0] kCl_1 = (Cl << 3) + (Cl << 2) + Cl;  // 0..3315

    // signed range about [-65535 .. 3315] -> needs 17 bits signed
    wire signed [16:0] t1 = $signed({1'b0, kCl_1}) - $signed({1'b0, Ch});

    // ---- IMPORTANT FIX ----
    // The K2-RED algorithm requires interpreting t1 modulo q BEFORE splitting into bytes.
    // Simply taking t1[15:0] applies mod 2^16, which is wrong for negative t1 values.
    //
    // Normalize t1 into [0, Q) using a small constant-time reduction.
    // t1 range here is roughly [-65535 .. 3315], so adding 20*Q guarantees positivity.
    reg signed [17:0] t1corr;

    always @* begin
        t1corr = t1;

        // make it non-negative
        if (t1corr < 0)
            t1corr = t1corr + (20*Q);

        // reduce to < Q using coarse subtracts (constant-time style)
        if (t1corr >= (16*Q)) t1corr = t1corr - (16*Q);
        if (t1corr >= (8*Q))  t1corr = t1corr - (8*Q);
        if (t1corr >= (4*Q))  t1corr = t1corr - (4*Q);
        if (t1corr >= (2*Q))  t1corr = t1corr - (2*Q);
        if (t1corr >= Q)      t1corr = t1corr - Q;
    end

    // Pack the normalized value (0..3328) into 16 bits, then split into bytes
    wire [15:0] t1_16 = {4'b0, t1corr[11:0]};

    wire [7:0]  t1_l = t1_16[7:0];
    wire [7:0]  t1_h = t1_16[15:8];

    // ---- Step 2: t2 = 13*t1_l - t1_h (signed) ----
    wire [11:0] kCl_2 = (t1_l << 3) + (t1_l << 2) + t1_l; // 0..3315
    // signed range about [-255 .. 3315] -> needs 13 bits signed
    wire signed [12:0] t2 = $signed({1'b0, kCl_2}) - $signed({1'b0, t1_h});

    // ---- Final normalization into [0, Q) ----
    // After step2 range is small enough that at most:
    //   - one add of Q if negative
    //   - one subtract of Q if >= Q
    reg signed [13:0] corr;

    always @* begin
        corr = t2;

        if (corr < 0)
            corr = corr + Q;

        if (corr >= Q)
            corr = corr - Q;

        R = corr[11:0];
    end

endmodule
