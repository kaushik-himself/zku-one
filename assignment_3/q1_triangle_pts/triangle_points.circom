/*
Prove that:
1. A(x1, y1), B(x2, y2) and C(x3, y3) lie on a triangle/are not on a straight line.
2. Verify that the jumps are within the energy range
*/

include "../../node_modules/circomlib/circuits/mimcsponge.circom";
include "../../node_modules/circomlib/circuits/comparators.circom";

template TrianglePoints() {
    signal input x1;
    signal input y1;
    signal input x2;
    signal input y2;
    signal input x3;
    signal input y3;
    signal input energy;

    signal output pub1;
    signal output pub2;
    signal output pub3;

    /* check (x1-x2)^2 + (y1-y2)^2 <= energy^2 */

    signal diff1X;
    diff1X <== x1 - x2;
    signal diff1Y;
    diff1Y <== y1 - y2;

    component ltDist1 = LessThan(32);
    signal firstDistSquare1;
    signal secondDistSquare1;
    firstDistSquare1 <== diff1X * diff1X;
    secondDistSquare1 <== diff1Y * diff1Y;
    ltDist1.in[0] <== firstDistSquare1 + secondDistSquare1;
    ltDist1.in[1] <== energy * energy + 1;
    ltDist1.out === 1;

    /* check (x3-x2)^2 + (y3-y2)^2 <= energy^2 */
    signal diff2X;
    diff2X <== x3 - x2;
    signal diff2Y;
    diff2Y <== y3 - y2;

    component ltDist2 = LessThan(32);
    signal firstDistSquare2;
    signal secondDistSquare2;
    firstDistSquare2 <== diff2X * diff2X;
    secondDistSquare2 <== diff2Y * diff2Y;
    ltDist2.in[0] <== firstDistSquare2 + secondDistSquare2;
    ltDist2.in[1] <== energy * energy + 1;
    ltDist2.out === 1;

    /*
    Check that the three points are not in a straigh line by comparing their slopes.
    if (y2 - y1) * (x3 - x2) == (y3 - y2) * (x2 - x1), the 3 points are in a straight line.
    */
    signal s1;
    s1 <== (y2 - y1) * (x3 - x2);
    signal s2;
    s2 <== (y3 - y2) * (x2 - x1);

    component eq = IsEqual();
    eq.in[0] <== s1;
    eq.in[1] <== s2;
    eq.out === 0; // Checks not equal
    
    /* check MiMCSponge(x1,y1) = pub1, MiMCSponge(x2,y2) = pub2 */
    /*
        220 = 2 * ceil(log_5 p), as specified by mimc paper, where
        p = 21888242871839275222246405745257275088548364400416034343698204186575808495617
    */
    component mimc1 = MiMCSponge(2, 220, 1);
    component mimc2 = MiMCSponge(2, 220, 1);
    component mimc3 = MiMCSponge(2, 220, 1);

    mimc1.ins[0] <== x1;
    mimc1.ins[1] <== y1;
    mimc1.k <== 0;
    mimc2.ins[0] <== x2;
    mimc2.ins[1] <== y2;
    mimc2.k <== 0;
    mimc3.ins[0] <== x3;
    mimc3.ins[1] <== y3;
    mimc3.k <== 0;

    pub1 <== mimc1.outs[0];
    pub2 <== mimc2.outs[0];
    pub3 <== mimc3.outs[0];
}

component main = TrianglePoints();