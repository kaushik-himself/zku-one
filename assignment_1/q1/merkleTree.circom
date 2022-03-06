pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/mimcsponge.circom";

// Helper template that computes hashes of the next tree layer
template TreeLayer(height) {
  var nItems = 1 << height;
  signal input ins[nItems * 2];
  signal output outs[nItems];

  component hash[nItems];
  for(var i = 0; i < nItems; i++) {
    hash[i] = MiMCSponge(2, 220, 1);
    hash[i].ins[0] <== ins[i * 2];
    hash[i].ins[1] <== ins[i * 2 + 1];
    hash[i].k <== 0;
    hash[i].outs[0] ==> outs[i];
  }
}

// Builds a merkle tree from leaf array
template MerkleTree(levels) {
  signal input leaves[1 << levels];
  signal output root;

  component layers[levels];
  for(var level = levels - 1; level >= 0; level--) {
    layers[level] = TreeLayer(level);
    for(var i = 0; i < (1 << (level + 1)); i++) {
      layers[level].ins[i] <== level == levels - 1 ? leaves[i] : layers[level + 1].outs[i];
    }
  }

  root <== levels > 0 ? layers[0].outs[0] : leaves[0];
}

component main = MerkleTree(3);