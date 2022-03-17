/*
A card is represented simply by a number from [0-51] (inclusive).
Each consecutive set of 13 numbers can indicate cards of a single suit.
For example, 0-12 (inclusive) can be spades,
13-25 clubs,
26-38 diamonds,
39-51 hearts.

Prove that the 2 cards passed belong to the same suit - i.e. they are
bound by the same multiple of 13.

E.g. 14 and 20 belong to the same suit.
     9 and 16 belong to different suits.
*/
pragma circom 2.0.0;

include "../../node_modules/circomlib/circuits/mimcsponge.circom";
include "../../node_modules/circomlib/circuits/comparators.circom";

/*
Returns 1 if rangeStart <= val < rangeEnd.
Else returns 0.
*/
template IsInRange() {
    signal input val;
    signal input rangeStart;
    signal input rangeEnd;

    signal output out;

    component lowerBound = GreaterEqThan(32);
    lowerBound.in[0] <== val;
    lowerBound.in[1] <== rangeStart;

    component upperBound = LessThan(32);
    upperBound.in[0] <== val;
    upperBound.in[1] <== rangeEnd;

    // If both upper bound and lower bound are true, the val is in range.
    // out will be set to 1 if and only if both upperBound and lowerBound check return 1's.
    out <== lowerBound.out * upperBound.out;
}

// Sets output to 1 for the range to which val belongs
template MarkSuit() {
    signal input val;

    // Add one entry in 'out' for each suit.
    // if out[i] is 1 => the value belongs to the i'th suit.
    signal output out[4];

    // Check for each range of 13 if the value falls in that range.
    // If it does, set the corresponding out to 1.
    // Else, set the corresponding out to 0.
    component inRange1 = IsInRange();
    inRange1.val <== val;
    inRange1.rangeStart <== 0;
    inRange1.rangeEnd <== 13;
    out[0] <== inRange1.out;

    component inRange2 = IsInRange();
    inRange2.val <== val;
    inRange2.rangeStart <== 13;
    inRange2.rangeEnd <== 26;
    out[1] <== inRange2.out;

    component inRange3 = IsInRange();
    inRange3.val <== val;
    inRange3.rangeStart <== 26;
    inRange3.rangeEnd <== 39;
    out[2] <== inRange3.out;

    component inRange4 = IsInRange();
    inRange4.val <== val;
    inRange4.rangeStart <== 39;
    inRange4.rangeEnd <== 52;
    out[3] <== inRange4.out;
}

/*
Checks that card1 and card2 belong to the same suit.
*/
template IsSameSuit() {
    signal input card1;
    signal input card2;
    signal input seed;

    signal output hashedCard1;

    // Both the cards should have a valid value, [0-51].
    assert(card1 >= 0);
    assert(card2 >= 0);
    assert(card1 < 52);
    assert(card2 < 52);

    // Mark the suit for both the cards.
    component multiRange1 = MarkSuit();
    multiRange1.val <== card1;

    component multiRange2 = MarkSuit();
    multiRange2.val <== card2;

    // Check that the suit matches.
    for (var i = 0; i < 4; i++) {
        multiRange1.out[i] === multiRange2.out[i];
    }

    /* Output the value of the first card hashed with the secret seed.
      
       - Hashing with a secret seed ensures that the card's value is not revealed.
       - The output is verified by the smart contract with the card value stored by it
       to ensure that the player has not spoofed the value of the first card while
       generating the proof.
    */
    component mimc = MiMCSponge(2, 220, 1);
    mimc.ins[0] <== card1;
    mimc.ins[1] <== seed;
    mimc.k <== 1;

    hashedCard1 <== mimc.outs[0];
}

component main = IsSameSuit();