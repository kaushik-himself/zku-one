// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

/** 
 * @title Ballot
 * @dev Implements voting process along with vote delegation
 */
contract Ballot {
   
   /* Changed the struct to optimize storage memory.
      Since Solidity compiler only deals with uint256 and bytes32, storing other data types is
      sub-optimal.
      By changing the types to uint64, uint64 and uint128, the first three variables of the struct
      get packed into a single memory slot, thereby reducing gas.
      Address is changed to bytes32 for the same reason.

      When we store less than 256 bits, the solidity compiler packs the end with 0s, leading to
      higher gas cost.

      The caveat here is that for large voter pools, the weight and vote variables might not fit
      into uint64 and uint128, respectively. In that case, we will use uint for all variables,
      including the bool.

      Instead of bool type, we use an integer which is set to 0 if false and 1 if true.
   */ 
    struct Voter {
        uint64 voted;  // if not 0, that person already voted
        uint64 weight; // weight is accumulated by delegation
        uint128 vote;   // index of the voted proposal
        bytes32 delegate; // person delegated to
    }

    struct Proposal {
        // If you can limit the length to a certain number of bytes, 
        // always use one of bytes1 to bytes32 because they are much cheaper
        bytes32 name;   // short name (up to 32 bytes)
        uint voteCount; // number of accumulated votes
    }

    address public chairperson;

    mapping(address => Voter) public voters;

    Proposal[] public proposals;

    /** 
     * @dev Create a new ballot to choose one of 'proposalNames'.
     * @param proposalNames names of proposals
     */
    constructor(bytes32[] memory proposalNames) {
        chairperson = msg.sender;
        voters[chairperson].weight = 1;

        for (uint i = 0; i < proposalNames.length; i++) {
            // 'Proposal({...})' creates a temporary
            // Proposal object and 'proposals.push(...)'
            // appends it to the end of 'proposals'.
            proposals.push(Proposal({
                name: proposalNames[i],
                voteCount: 0
            }));
        }
    }
    
    /** 
     * @dev Give 'voter' the right to vote on this ballot. May only be called by 'chairperson'.
     * @param voter address of voter
     *
     ** OPTIMIZATION **
     * Changed the address type to an array of addresses. Batching the addresses reduces the total
     * number of transactions and reduces the cost of giving rights to a batch of voters.
     */
    function giveRightToVote(address[] memory voter) public {
        require(
            msg.sender == chairperson,
            "Only chairperson can give right to vote."
        );

        for (uint i = 0; i < voter.length; i++) {
            require(
                voters[voter[i]].voted == 0,
                "The voter already voted."
            );
            require(voters[voter[i]].weight == 0);
            voters[voter[i]].weight = 1;
        }
    }

    /**
     * @dev Delegate your vote to the voter 'to'.
     * @param to address to which vote is delegated
     */
    function delegate(address to) public {
        Voter storage sender = voters[msg.sender];
        require(sender.voted == 0, "You already voted.");
        require(to != msg.sender, "Self-delegation is disallowed.");

        address delegate_addr = bytesToAddress(voters[to].delegate);
        while (delegate_addr != address(0)) {
            to = delegate_addr;

            // We found a loop in the delegation, not allowed.
            require(to != msg.sender, "Found loop in delegation.");
        }
        sender.voted = 1;
        sender.delegate = addressToBytes(to);
        Voter storage delegate_ = voters[to];
        if (delegate_.voted != 0) {
            // If the delegate already voted,
            // directly add to the number of votes
            proposals[delegate_.vote].voteCount += sender.weight;
        } else {
            // If the delegate did not vote yet,
            // add to her weight.
            delegate_.weight += sender.weight;
        }
    }

    /**
     * @dev Give your vote (including votes delegated to you) to proposal 'proposals[proposal].name'.
     * @param proposal index of proposal in the proposals array
     */
    function vote(uint128 proposal) public {
        Voter storage sender = voters[msg.sender];
        require(sender.weight != 0, "Has no right to vote");
        require(sender.voted == 0, "Already voted.");
        sender.voted = 1;
        sender.vote = proposal;

        // If 'proposal' is out of the range of the array,
        // this will throw automatically and revert all
        // changes.
        proposals[proposal].voteCount += sender.weight;
    }

    /** 
     * @dev Computes the winning proposal taking all previous votes into account.
     * @return winningProposal_ index of winning proposal in the proposals array
     */
    function winningProposal() public view
            returns (uint winningProposal_)
    {
        uint winningVoteCount = 0;
        for (uint p = 0; p < proposals.length; p++) {
            if (proposals[p].voteCount > winningVoteCount) {
                winningVoteCount = proposals[p].voteCount;
                winningProposal_ = p;
            }
        }
    }

    /** 
     * @dev Calls winningProposal() function to get the index of the winner contained in the proposals array and then
     * @return winnerName_ the name of the winner
     */
    function winnerName() public view
            returns (bytes32 winnerName_)
    {
        winnerName_ = proposals[winningProposal()].name;
    }

    function bytesToAddress(bytes32 data) private pure returns (address) {
        return address(uint160(uint256(data)));
    }

    function addressToBytes(address addr) private pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)) << 96);
    }
}

