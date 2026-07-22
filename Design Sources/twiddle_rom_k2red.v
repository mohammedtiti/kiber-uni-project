`timescale 1ns / 1ps

// Kyber zeta table in the exact bit-reversed order used by the reference
// seven-stage NTT.  Both ordinary residues and K2-RED-scaled residues are
// provided so the same table supports butterflies and quadratic base-mul.
module kyber_twiddle_rom (
    input  wire [6:0]  addr,
    input  wire        negate,
    output wire [11:0] zeta,
    output wire [11:0] zeta_scaled
);
    localparam [12:0] Q = 13'd3329;
    reg [11:0] zeta_base;
    reg [11:0] scaled_base;

    always @* begin
        case (addr)
            7'd0: begin zeta_base = 12'd1; scaled_base = 12'd2285; end
            7'd1: begin zeta_base = 12'd1729; scaled_base = 12'd2571; end
            7'd2: begin zeta_base = 12'd2580; scaled_base = 12'd2970; end
            7'd3: begin zeta_base = 12'd3289; scaled_base = 12'd1812; end
            7'd4: begin zeta_base = 12'd2642; scaled_base = 12'd1493; end
            7'd5: begin zeta_base = 12'd630; scaled_base = 12'd1422; end
            7'd6: begin zeta_base = 12'd1897; scaled_base = 12'd287; end
            7'd7: begin zeta_base = 12'd848; scaled_base = 12'd202; end
            7'd8: begin zeta_base = 12'd1062; scaled_base = 12'd3158; end
            7'd9: begin zeta_base = 12'd1919; scaled_base = 12'd622; end
            7'd10: begin zeta_base = 12'd193; scaled_base = 12'd1577; end
            7'd11: begin zeta_base = 12'd797; scaled_base = 12'd182; end
            7'd12: begin zeta_base = 12'd2786; scaled_base = 12'd962; end
            7'd13: begin zeta_base = 12'd3260; scaled_base = 12'd2127; end
            7'd14: begin zeta_base = 12'd569; scaled_base = 12'd1855; end
            7'd15: begin zeta_base = 12'd1746; scaled_base = 12'd1468; end
            7'd16: begin zeta_base = 12'd296; scaled_base = 12'd573; end
            7'd17: begin zeta_base = 12'd2447; scaled_base = 12'd2004; end
            7'd18: begin zeta_base = 12'd1339; scaled_base = 12'd264; end
            7'd19: begin zeta_base = 12'd1476; scaled_base = 12'd383; end
            7'd20: begin zeta_base = 12'd3046; scaled_base = 12'd2500; end
            7'd21: begin zeta_base = 12'd56; scaled_base = 12'd1458; end
            7'd22: begin zeta_base = 12'd2240; scaled_base = 12'd1727; end
            7'd23: begin zeta_base = 12'd1333; scaled_base = 12'd3199; end
            7'd24: begin zeta_base = 12'd1426; scaled_base = 12'd2648; end
            7'd25: begin zeta_base = 12'd2094; scaled_base = 12'd1017; end
            7'd26: begin zeta_base = 12'd535; scaled_base = 12'd732; end
            7'd27: begin zeta_base = 12'd2882; scaled_base = 12'd608; end
            7'd28: begin zeta_base = 12'd2393; scaled_base = 12'd1787; end
            7'd29: begin zeta_base = 12'd2879; scaled_base = 12'd411; end
            7'd30: begin zeta_base = 12'd1974; scaled_base = 12'd3124; end
            7'd31: begin zeta_base = 12'd821; scaled_base = 12'd1758; end
            7'd32: begin zeta_base = 12'd289; scaled_base = 12'd1223; end
            7'd33: begin zeta_base = 12'd331; scaled_base = 12'd652; end
            7'd34: begin zeta_base = 12'd3253; scaled_base = 12'd2777; end
            7'd35: begin zeta_base = 12'd1756; scaled_base = 12'd1015; end
            7'd36: begin zeta_base = 12'd1197; scaled_base = 12'd2036; end
            7'd37: begin zeta_base = 12'd2304; scaled_base = 12'd1491; end
            7'd38: begin zeta_base = 12'd2277; scaled_base = 12'd3047; end
            7'd39: begin zeta_base = 12'd2055; scaled_base = 12'd1785; end
            7'd40: begin zeta_base = 12'd650; scaled_base = 12'd516; end
            7'd41: begin zeta_base = 12'd1977; scaled_base = 12'd3321; end
            7'd42: begin zeta_base = 12'd2513; scaled_base = 12'd3009; end
            7'd43: begin zeta_base = 12'd632; scaled_base = 12'd2663; end
            7'd44: begin zeta_base = 12'd2865; scaled_base = 12'd1711; end
            7'd45: begin zeta_base = 12'd33; scaled_base = 12'd2167; end
            7'd46: begin zeta_base = 12'd1320; scaled_base = 12'd126; end
            7'd47: begin zeta_base = 12'd1915; scaled_base = 12'd1469; end
            7'd48: begin zeta_base = 12'd2319; scaled_base = 12'd2476; end
            7'd49: begin zeta_base = 12'd1435; scaled_base = 12'd3239; end
            7'd50: begin zeta_base = 12'd807; scaled_base = 12'd3058; end
            7'd51: begin zeta_base = 12'd452; scaled_base = 12'd830; end
            7'd52: begin zeta_base = 12'd1438; scaled_base = 12'd107; end
            7'd53: begin zeta_base = 12'd2868; scaled_base = 12'd1908; end
            7'd54: begin zeta_base = 12'd1534; scaled_base = 12'd3082; end
            7'd55: begin zeta_base = 12'd2402; scaled_base = 12'd2378; end
            7'd56: begin zeta_base = 12'd2647; scaled_base = 12'd2931; end
            7'd57: begin zeta_base = 12'd2617; scaled_base = 12'd961; end
            7'd58: begin zeta_base = 12'd1481; scaled_base = 12'd1821; end
            7'd59: begin zeta_base = 12'd648; scaled_base = 12'd2604; end
            7'd60: begin zeta_base = 12'd2474; scaled_base = 12'd448; end
            7'd61: begin zeta_base = 12'd3110; scaled_base = 12'd2264; end
            7'd62: begin zeta_base = 12'd1227; scaled_base = 12'd677; end
            7'd63: begin zeta_base = 12'd910; scaled_base = 12'd2054; end
            7'd64: begin zeta_base = 12'd17; scaled_base = 12'd2226; end
            7'd65: begin zeta_base = 12'd2761; scaled_base = 12'd430; end
            7'd66: begin zeta_base = 12'd583; scaled_base = 12'd555; end
            7'd67: begin zeta_base = 12'd2649; scaled_base = 12'd843; end
            7'd68: begin zeta_base = 12'd1637; scaled_base = 12'd2078; end
            7'd69: begin zeta_base = 12'd723; scaled_base = 12'd871; end
            7'd70: begin zeta_base = 12'd2288; scaled_base = 12'd1550; end
            7'd71: begin zeta_base = 12'd1100; scaled_base = 12'd105; end
            7'd72: begin zeta_base = 12'd1409; scaled_base = 12'd422; end
            7'd73: begin zeta_base = 12'd2662; scaled_base = 12'd587; end
            7'd74: begin zeta_base = 12'd3281; scaled_base = 12'd177; end
            7'd75: begin zeta_base = 12'd233; scaled_base = 12'd3094; end
            7'd76: begin zeta_base = 12'd756; scaled_base = 12'd3038; end
            7'd77: begin zeta_base = 12'd2156; scaled_base = 12'd2869; end
            7'd78: begin zeta_base = 12'd3015; scaled_base = 12'd1574; end
            7'd79: begin zeta_base = 12'd3050; scaled_base = 12'd1653; end
            7'd80: begin zeta_base = 12'd1703; scaled_base = 12'd3083; end
            7'd81: begin zeta_base = 12'd1651; scaled_base = 12'd778; end
            7'd82: begin zeta_base = 12'd2789; scaled_base = 12'd1159; end
            7'd83: begin zeta_base = 12'd1789; scaled_base = 12'd3182; end
            7'd84: begin zeta_base = 12'd1847; scaled_base = 12'd2552; end
            7'd85: begin zeta_base = 12'd952; scaled_base = 12'd1483; end
            7'd86: begin zeta_base = 12'd1461; scaled_base = 12'd2727; end
            7'd87: begin zeta_base = 12'd2687; scaled_base = 12'd1119; end
            7'd88: begin zeta_base = 12'd939; scaled_base = 12'd1739; end
            7'd89: begin zeta_base = 12'd2308; scaled_base = 12'd644; end
            7'd90: begin zeta_base = 12'd2437; scaled_base = 12'd2457; end
            7'd91: begin zeta_base = 12'd2388; scaled_base = 12'd349; end
            7'd92: begin zeta_base = 12'd733; scaled_base = 12'd418; end
            7'd93: begin zeta_base = 12'd2337; scaled_base = 12'd329; end
            7'd94: begin zeta_base = 12'd268; scaled_base = 12'd3173; end
            7'd95: begin zeta_base = 12'd641; scaled_base = 12'd3254; end
            7'd96: begin zeta_base = 12'd1584; scaled_base = 12'd817; end
            7'd97: begin zeta_base = 12'd2298; scaled_base = 12'd1097; end
            7'd98: begin zeta_base = 12'd2037; scaled_base = 12'd603; end
            7'd99: begin zeta_base = 12'd3220; scaled_base = 12'd610; end
            7'd100: begin zeta_base = 12'd375; scaled_base = 12'd1322; end
            7'd101: begin zeta_base = 12'd2549; scaled_base = 12'd2044; end
            7'd102: begin zeta_base = 12'd2090; scaled_base = 12'd1864; end
            7'd103: begin zeta_base = 12'd1645; scaled_base = 12'd384; end
            7'd104: begin zeta_base = 12'd1063; scaled_base = 12'd2114; end
            7'd105: begin zeta_base = 12'd319; scaled_base = 12'd3193; end
            7'd106: begin zeta_base = 12'd2773; scaled_base = 12'd1218; end
            7'd107: begin zeta_base = 12'd757; scaled_base = 12'd1994; end
            7'd108: begin zeta_base = 12'd2099; scaled_base = 12'd2455; end
            7'd109: begin zeta_base = 12'd561; scaled_base = 12'd220; end
            7'd110: begin zeta_base = 12'd2466; scaled_base = 12'd2142; end
            7'd111: begin zeta_base = 12'd2594; scaled_base = 12'd1670; end
            7'd112: begin zeta_base = 12'd2804; scaled_base = 12'd2144; end
            7'd113: begin zeta_base = 12'd1092; scaled_base = 12'd1799; end
            7'd114: begin zeta_base = 12'd403; scaled_base = 12'd2051; end
            7'd115: begin zeta_base = 12'd1026; scaled_base = 12'd794; end
            7'd116: begin zeta_base = 12'd1143; scaled_base = 12'd1819; end
            7'd117: begin zeta_base = 12'd2150; scaled_base = 12'd2475; end
            7'd118: begin zeta_base = 12'd2775; scaled_base = 12'd2459; end
            7'd119: begin zeta_base = 12'd886; scaled_base = 12'd478; end
            7'd120: begin zeta_base = 12'd1722; scaled_base = 12'd3221; end
            7'd121: begin zeta_base = 12'd1212; scaled_base = 12'd3021; end
            7'd122: begin zeta_base = 12'd1874; scaled_base = 12'd996; end
            7'd123: begin zeta_base = 12'd1029; scaled_base = 12'd991; end
            7'd124: begin zeta_base = 12'd2110; scaled_base = 12'd958; end
            7'd125: begin zeta_base = 12'd2935; scaled_base = 12'd1869; end
            7'd126: begin zeta_base = 12'd885; scaled_base = 12'd1522; end
            7'd127: begin zeta_base = 12'd2154; scaled_base = 12'd1628; end
            default: begin zeta_base = 12'd1; scaled_base = 12'd2285; end
        endcase
    end

    assign zeta = (negate && (zeta_base != 0)) ? (Q - zeta_base) : zeta_base;
    assign zeta_scaled = (negate && (scaled_base != 0)) ? (Q - scaled_base) : scaled_base;
endmodule
// Compatibility wrapper for the original synchronous scaled-twiddle port.
// MEMFILE is retained as a parameter so existing project scripts still elaborate,
// but the authoritative Kyber constants are now compiled into the RTL.
module twiddle_rom_k2red #(
    parameter AW = 7,
    parameter DW = 12,
    parameter MEMFILE = ""
)(
    input  wire          clk,
    input  wire [AW-1:0] addr,
    output reg  [DW-1:0] tf
);
    wire [11:0] zeta_unused;
    wire [11:0] scaled;
    kyber_twiddle_rom u_table (
        .addr(addr[6:0]),
        .negate(1'b0),
        .zeta(zeta_unused),
        .zeta_scaled(scaled)
    );
    always @(posedge clk)
        tf <= scaled;
endmodule
