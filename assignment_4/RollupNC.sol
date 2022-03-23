pragma solidity ^0.5.0;

import "../build/Update_verifier.sol";
import "../build/Withdraw_verifier.sol";

contract IMiMC {
    function MiMCpe7(uint256, uint256) public pure returns (uint256) {}
}

contract IMiMCMerkle {
    uint256[16] public zeroCache;

    function getRootFromProof(
        uint256,
        uint256[] memory,
        uint256[] memory
    ) public view returns (uint256) {}

    function hashMiMC(uint256[] memory) public view returns (uint256) {}
}

contract ITokenRegistry {
    address public coordinator;
    uint256 public numTokens;
    mapping(address => bool) public pendingTokens;
    mapping(uint256 => address) public registeredTokens;
    modifier onlyCoordinator() {
        assert(msg.sender == coordinator);
        _;
    }

    function registerToken(address tokenContract) public {}

    function approveToken(address tokenContract) public onlyCoordinator {}
}

contract IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public returns (bool) {}

    function transfer(address recipient, uint256 value) public returns (bool) {}
}

// ==== k15n ==== //
// Achieves higher scale on Ethereum by having a coordinator periodically batch
// txns and publish their merkle proof along with the merkle proof to the L1 chain.
//
// There are 2 merkle trees -
// 1. For storing the txns.
// 2. For storing the balances.
//
// Since only the merkle proofs are stored on the base chain, the L2 RollupNC needs
// to ensure data availability. It can do so by setting up a Data Availability
// Committee.
// In addition, the coordinator is relatively quite centralised when compared to
// Ethereum. Considerable investment in both security and miner/staker incentives is
// required to decentralise the blockchain.
//
// PS. Optimizations/improvements to the smart contract are preceded by 'Note:'.
// ==== k15n ==== //
contract RollupNC is Update_verifier, Withdraw_verifier {
    IMiMC public mimc;
    IMiMCMerkle public mimcMerkle;
    ITokenRegistry public tokenRegistry;
    IERC20 public tokenContract;

    uint256 public currentRoot;
    address public coordinator;
    uint256[] public pendingDeposits;
    uint256 public queueNumber;
    uint256 public depositSubtreeHeight;
    uint256 public updateNumber;

    uint256 public BAL_DEPTH = 4;
    uint256 public TX_DEPTH = 2;

    // (queueNumber => [pubkey_x, pubkey_y, balance, nonce, token_type])
    mapping(uint256 => uint256) public deposits; //leaf idx => leafHash
    mapping(uint256 => uint256) public updates; //txRoot => update idx

    event RegisteredToken(uint256 tokenType, address tokenContract);
    event RequestDeposit(uint256[2] pubkey, uint256 amount, uint256 tokenType);
    event UpdatedState(uint256 currentRoot, uint256 oldRoot, uint256 txRoot);
    event Withdraw(uint256[9] accountInfo, address recipient);

    constructor(
        address _mimcContractAddr,
        address _mimcMerkleContractAddr,
        address _tokenRegistryAddr
    ) public {
        mimc = IMiMC(_mimcContractAddr);
        mimcMerkle = IMiMCMerkle(_mimcMerkleContractAddr);
        tokenRegistry = ITokenRegistry(_tokenRegistryAddr);
        currentRoot = mimcMerkle.zeroCache(BAL_DEPTH);
        coordinator = msg.sender;
        queueNumber = 0;
        depositSubtreeHeight = 0;
        updateNumber = 0;
    }

    modifier onlyCoordinator() {
        assert(msg.sender == coordinator);
        _;
    }

    // ==== k15n ==== //
    // The inputs are the SNARK prover inputs that can be generated by calling
    // `snarkjs generatecall`.
    // ==== k15n ==== //
    function updateState(
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[3] memory input
    ) public onlyCoordinator {
        // ==== k15n ==== //
        // Can only be called by the coordinator
        // Check that the output of the circuit matches the current root of the
        // balance merkle tree. By doing so, the smart contract ensures that the
        // circuit was called with the right intial merkle root.
        // ==== k15n ==== //
        require(currentRoot == input[2], "input does not match current root");
        //validate proof
        require(update_verifyProof(a, b, c, input), "SNARK proof is invalid");

        // ==== k15n ==== //
        // The circuit outputs the new balance merkle root after updating the state.
        // The smart contract stores this as the current root after validating the output and
        // verifying the proof.
        // ==== k15n ==== //
        //
        // update merkle root
        currentRoot = input[0];
        // ==== k15n ==== //
        // Updates a count of the number of updates.
        // ==== k15n ====/ /
        updateNumber++;
        // ==== k15n ==== //
        // sets the transaction merkle root as the key of the updates map.
        // this is later used at the time of withdrawal to check that the txRoot passed is valid.
        // ==== k15n ====//
        updates[input[1]] = updateNumber;
        emit UpdatedState(input[0], input[1], input[2]); //newRoot, txRoot, oldRoot
    }

    // ==== k15n ==== //
    // User sends their public key, amount to be deposited and the tokenType.
    // This is a `payable` smart contract, which means that the user needs to pay an
    // amount at least equal to the amount to be deposited.
    //
    // The deposit is done in 2 steps:
    // 1. The user calls the deposit smart contract and sends their funds.
    // 2. Periodically, the coordinator processes the deposits and updates the
    //    merkle roots with the new deposits.
    // ==== k15n ==== //
    //
    // user tries to deposit ERC20 tokens
    function deposit(
        uint256[2] memory pubkey,
        uint256 amount,
        uint256 tokenType
    ) public payable {
        if (tokenType == 0) {
            // ==== k15n ==== //
            // the tokenType 0 is used to fill the merkle leaves to create a full merkle tree.
            // only the coordinator is allowed to transact using this token.
            // in addition, the txn amount needs to be set to 0 as the token has no value.
            // ==== k15n ==== //
            require(
                msg.sender == coordinator,
                "tokenType 0 is reserved for coordinator"
            );
            require(
                amount == 0 && msg.value == 0,
                "tokenType 0 does not have real value"
            );
        } else if (tokenType == 1) {
            // ==== k15n ==== //
            // Ethereum token.
            // ==== k15n ==== //
            require(
                msg.value > 0 && msg.value >= amount,
                "msg.value must at least equal stated amount in wei"
            );
        } else if (tokenType > 1) {
            // ==== k15n ==== //
            // Other ERC20 token.
            // Uses the token's registered smart contract to perform the deposit.
            // ==== k15n ==== //
            require(amount > 0, "token deposit must be greater than 0");
            address tokenContractAddress = tokenRegistry.registeredTokens(
                tokenType
            );
            tokenContract = IERC20(tokenContractAddress);
            require(
                tokenContract.transferFrom(msg.sender, address(this), amount),
                "token transfer not approved"
            );
        }

        uint256[] memory depositArray = new uint256[](5);
        depositArray[0] = pubkey[0];
        depositArray[1] = pubkey[1];
        depositArray[2] = amount;
        depositArray[3] = 0;
        depositArray[4] = tokenType;

        // ==== k15n ==== //
        // Creates a deposit hash using the elements of the deposit array.
        //
        // Note: Uses a MiMC hash for doing this, which is quite expensive on-chain
        // and consumes a lot of gas.
        // However, MiMC is one of the hash functions optimized for SNARK execution.
        // If replaced by a EVM friendly hash like SHA256, the transaction would
        // cost less gas, but it would be more expensive to compute the SNARK proof.
        // ==== k15n ==== //
        uint256 depositHash = mimcMerkle.hashMiMC(depositArray);

        // ==== k15n ==== //
        // Pushes the deposit hash to a queue of pending deposits.
        // ==== k15n ==== //
        pendingDeposits.push(depositHash);
        emit RequestDeposit(pubkey, amount, tokenType);

        // ==== k15n ==== //
        // Increments the queue number by 1.
        // ==== k15n ==== //
        queueNumber++;
        uint256 tmpDepositSubtreeHeight = 0;
        uint256 tmp = queueNumber;

        // ==== k15n ==== //
        // The deposit array is hashed.
        // The number of times the hashing is done is equal to the number of times
        // the deposit number can be divided by 2.
        // This is done in order to create a merkle root of the deposit.
        // The deposits which are hashed together are deleted and replaced with
        // their hash.
        //
        // Note: This is somewhat unfair to users depositing later in the queue.
        // Their transaction fee is considerably higher than users who deposited
        // at the beginning of the queue as they have to execute the expensive MiMC
        // hash function more number of times to get the merkle root.
        // Ideally, this cost should be evenly distributed amongst all the users.
        //
        // One way of doing this is to have the coordinator compute the merkle root
        // rather than doing this as a part of the deposit function.
        // The coordinator can amortize the cost over each transaction and charge a
        // premium from each depositor to recover the gas fees they have to pay to
        // perform the computation.
        // ==== k15n ==== //
        while (tmp % 2 == 0) {
            uint256[] memory array = new uint256[](2);
            array[0] = pendingDeposits[pendingDeposits.length - 2];
            array[1] = pendingDeposits[pendingDeposits.length - 1];
            pendingDeposits[pendingDeposits.length - 2] = mimcMerkle.hashMiMC(
                array
            );
            removeDeposit(pendingDeposits.length - 1);
            tmp = tmp / 2;
            tmpDepositSubtreeHeight++;
        }

        // ==== k15n ==== //
        // If the number of transactions exceed the next power of 2, the height of
        // the merkle tree is updated to equal the new height.
        // ==== k15n ==== //
        if (tmpDepositSubtreeHeight > depositSubtreeHeight) {
            depositSubtreeHeight = tmpDepositSubtreeHeight;
        }
    }

    // coordinator adds certain number of deposits to balance tree
    // coordinator must specify subtree index in the tree since the deposits
    // are being inserted at a nonzero height
    function processDeposits(
        uint256 subtreeDepth,
        uint256[] memory subtreePosition,
        uint256[] memory subtreeProof
    ) public onlyCoordinator returns (uint256) {
        uint256 emptySubtreeRoot = mimcMerkle.zeroCache(subtreeDepth); //empty subtree of height 2
        // ==== k15n ==== //
        // Check that the position where the deposit is being inserted is empty,
        // i.e. has a emptySubtreeRoot.
        // ==== k15n ==== //
        require(
            currentRoot ==
                mimcMerkle.getRootFromProof(
                    emptySubtreeRoot,
                    subtreePosition,
                    subtreeProof
                ),
            "specified subtree is not empty"
        );

        // ==== k15n ==== //
        // Inserts the deposit subtree into the tree and computes the new merkle
        // root of the balance merkle tree.
        // The 0th element of the pendingDeposits array is the root of the deposit
        // subtree.
        // ==== k15n ==== //
        currentRoot = mimcMerkle.getRootFromProof(
            pendingDeposits[0],
            subtreePosition,
            subtreeProof
        );

        // ==== k15n ==== //
        // Removes the deposit from the queue and updates the queueNumber.
        // ==== k15n ==== //
        removeDeposit(0);
        queueNumber = queueNumber - 2**depositSubtreeHeight;
        return currentRoot;
    }

    // ==== k15n ==== //
    // User calls withdraw passing the transaction info, position, proof of the
    // txn's inclusion in the txn merkle tree.
    // The user EdDSA signs a message specifying the recipient's Eth address.
    // The user also submits the SNARK proof of the EdDSA signature which is
    // verified before withdrawal to the recipient address.
    //
    // Note: Use calldata instead of memory for the params to save gas cost.
    // ==== k15n ==== //
    function withdraw(
        uint256[9] memory txInfo, //[pubkeyX, pubkeyY, index, toX ,toY, nonce, amount, token_type_from, txRoot]
        uint256[] memory position,
        uint256[] memory proof,
        address payable recipient,
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c
    ) public {
        // ==== k15n ==== //
        // Checks that the token type is valid (not 0) and that the transaction root
        // exists in the updates map.
        // ==== k15n ==== //
        require(txInfo[7] > 0, "invalid tokenType");
        require(updates[txInfo[8]] > 0, "txRoot does not exist");

        // ==== k15n ==== //
        // Note: copying the array to memory costs gas.
        // Using calldata as noted above will save gas.
        // Another gas optimization that can be made is to use the txInfo array as
        // is instead of copying it to another array.
        // ==== k15n ==== //
        uint256[] memory txArray = new uint256[](8);
        for (uint256 i = 0; i < 8; i++) {
            txArray[i] = txInfo[i];
        }

        // ==== k15n ==== //
        // MiMC hash the txn details to generate the leaf and check its proof of
        // existence in the txn merkle tree.
        // ==== k15n ==== //
        uint256 txLeaf = mimcMerkle.hashMiMC(txArray);
        require(
            txInfo[8] == mimcMerkle.getRootFromProof(txLeaf, position, proof),
            "transaction does not exist in specified transactions root"
        );

        // ==== k15n ==== //
        // Hashes the nonce and the recipient address and verifies the validity of
        // the user's EdDSA sign using the SNARK proof passed.
        //
        // Note: The array needs to be copied to pass it to the MiMC hash function.
        // This can be avoided by modifying the signature of the hash function to
        // take a couple of inputs instead of an array. Avoiding copying will reduce
        // some gas fees.
        // ==== k15n ==== //
        // message is hash of nonce and recipient address
        uint256[] memory msgArray = new uint256[](2);
        msgArray[0] = txInfo[5];
        msgArray[1] = uint256(recipient);

        require(
            withdraw_verifyProof(
                a,
                b,
                c,
                [txInfo[0], txInfo[1], mimcMerkle.hashMiMC(msgArray)]
            ),
            "eddsa signature is not valid"
        );

        // ==== k15n ==== //
        // After all the above checks pass, the actual transfer to the recipient
        // address is done.
        // Supports ETH or other ERC20 token which has previously been registered
        // with the smart contract.
        // ==== k15n ==== //
        // transfer token on tokenContract
        if (txInfo[7] == 1) {
            // ETH
            recipient.transfer(txInfo[6]);
        } else {
            // ERC20
            address tokenContractAddress = tokenRegistry.registeredTokens(
                txInfo[7]
            );
            tokenContract = IERC20(tokenContractAddress);
            require(
                tokenContract.transfer(recipient, txInfo[6]),
                "transfer failed"
            );
        }

        emit Withdraw(txInfo, recipient);
    }

    //call methods on TokenRegistry contract

    function registerToken(address tokenContractAddress) public {
        tokenRegistry.registerToken(tokenContractAddress);
    }

    function approveToken(address tokenContractAddress) public onlyCoordinator {
        tokenRegistry.approveToken(tokenContractAddress);
        emit RegisteredToken(tokenRegistry.numTokens(), tokenContractAddress);
    }

    // helper functions
    function removeDeposit(uint256 index) internal returns (uint256[] memory) {
        require(index < pendingDeposits.length, "index is out of bounds");

        for (uint256 i = index; i < pendingDeposits.length - 1; i++) {
            pendingDeposits[i] = pendingDeposits[i + 1];
        }
        delete pendingDeposits[pendingDeposits.length - 1];
        pendingDeposits.length--;
        return pendingDeposits;
    }
}