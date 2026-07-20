// Reconfigurable butterfly using K2-RED (Kyber q=3329).
//
// mode = 0 : CT butterfly for NTT
//   t    = (v * tw_scaled) reduced by K2RED  -> t ≡ v*omega (mod q)
//   out0 = u + t (mod q)
//   out1 = u - t (mod q)
//
// mode = 1 : GS butterfly for INTT
//   out0 = u + v (mod q)
//   d    = u - v (mod q)
//   out1 = (d * tw_scaled) reduced by K2RED -> out1 ≡ (u-v)*omega (mod q)
//
// IMPORTANT:
// - tw_scaled must be the value you feed to the multiplier *before* K2RED.
//   In a K2RED design, you typically store tw_scaled = k^{-2} * omega (mod q)
//   in ROM, so that K2RED(v*tw_scaled) = v*omega (mod q).
// - If you are using the "ROM reuse" INTT trick (reverse order + sign),
//   handle that in your twiddle generation/addressing (or compute d = v-u, etc.).
//   This butterfly just uses the twiddle value it is given.

module butterfly_k2red_kyber (
    input  wire        mode,        // 0=NTT(CT), 1=INTT(GS)
    input  wire [11:0] u_in,         // 0..3328
    input  wire [11:0] v_in,         // 0..3328
    input  wire [11:0] tw_scaled,    // typically k^{-2}*omega mod q (0..3328)
    output reg  [11:0] out0,         // 0..3328
    output reg  [11:0] out1          // 0..3328
);
    localparam integer Q = 3329;

    // ---------- helpers: modular add/sub in [0, Q) ----------
    function automatic [11:0] add_mod_q(input [11:0] a, input [11:0] b);
        reg [12:0] s;
        begin
            s = a + b;                 // up to 6656 (< 2^13)
            if (s >= Q) s = s - Q;
            add_mod_q = s[11:0];
        end
    endfunction

    function automatic [11:0] sub_mod_q(input [11:0] a, input [11:0] b);
        reg signed [13:0] d;           // enough for [-3328..3328]
        begin
            d = $signed({1'b0,a}) - $signed({1'b0,b});
            if (d < 0) d = d + Q;
            sub_mod_q = d[11:0];
        end
    endfunction

    // ---------- multiplication + K2RED ----------
    // We will multiply either v (CT) or d (GS) by tw_scaled, then apply K2RED.
    wire [11:0] d_gs = sub_mod_q(v_in, u_in);  // v - u mod q
    wire [11:0] mult_in = (mode == 1'b0) ? v_in : d_gs;

    wire [23:0] prod = mult_in * tw_scaled;          // fits in 24 bits for Kyber

    wire [11:0] t_red;
    k2red_kyber u_k2red (
        .C(prod),
        .R(t_red)
    );

    // ---------- outputs ----------
    always @* begin
        if (mode == 1'b0) begin
            // CT (NTT): (u + v*ω), (u - v*ω)
            out0 = add_mod_q(u_in, t_red);
            out1 = sub_mod_q(u_in, t_red);
        end else begin
            // GS (INTT): (u + v), (u - v)*ω
            out0 = add_mod_q(u_in, v_in);
            out1 = t_red; // already reduced ( (u-v)*ω mod q )
        end
    end

endmodule
