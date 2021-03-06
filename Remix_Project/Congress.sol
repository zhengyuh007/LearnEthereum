pragma solidity ^0.4.16;
// Decentralized Autonomous Organization
// The Blockchain Congress

contract owned {
    address public owner;
    // constructor
    function owned() public {
        owner = msg.sender;
    }
    
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
    
    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}
//--------------------------------------------------------------------------------

interface Token {
    function transferFrom(address _from, address _to, uint256 _value) public returns(bool success);
}
//--------------------------------------------------------------------------------

contract tokenRecipient {
    event receivedEther(address sender, uint amount);
    event receivedTokens(address _from, uint256 _value, address _token, bytes _extraData);
    
    function receiveApproval(address _from, uint256 _value, address _token, bytes _extraData) public {
        Token t = Token(_token);
        require(t.transferFrom(_from, this, _value));
        receivedTokens(_from, _value, _token, _extraData);
    }
    
    function() payable public {
        receivedEther(msg.sender, msg.value);
    }
}
//--------------------------------------------------------------------------------

// main contract
contract Congress is owned, tokenRecipient {
    // INNER STRUCTURE
    struct Proposal {
        address recipient;
        uint amount;
        string description;
        uint votingDeadline;
        bool executed;
        bool proposalPassed;
        uint numberOfVotes;
        int currentResult;
        bytes32 proposalHash;
        Vote[] votes;
        mapping(address => bool) voted;
    }
    
    struct Member {
        address member;
        string name;
        uint memberSince;
    }
    
    struct Vote {
        bool inSupport;
        address voter;
        string justification;
    }
    //************************************************************************
    
    // INNER VARIABLS 
    uint public minimumQuorum;
    uint public debatingPeriodInMinutes;
    int public majorityMargin;
    Proposal[] public proposals;
    uint public numProposals;
    mapping(address => uint) public memberId;
    Member[] public members;
    //***********************************************************************
    
    // events and modifier
    modifier onlyMembers {
        require(memberId[msg.sender] != 0);
        _;
    }
    
    event ProposalAdded(uint proposalID, address recipient, uint amount, string description);
    event Voted(uint proposalID, bool position, address voter, string justification);
    event ProposalTallied(uint proposalID, int result, uint quorum, bool active);
    event MembershipChanged(address member, bool isMember);
    event ChangeOfRules(uint newMinimumQuorum, uint newDebatingPeriodInMinutes, int newMajorityMargin);
    // this event used as debugger for execute proposal
    event debugExecute(bool cond1, bool cond2, bool cond3, bool cond4);
    //************************************************************************
    
    // constructor
     function Congress ( uint minimumQuorumForProposals, uint minutesForDebate, 
         int marginOfVotesForMajority)  payable public {
        changeVotingRules(minimumQuorumForProposals, minutesForDebate, marginOfVotesForMajority);
        // It’s necessary to add an empty first member
        addMember(0, "");
        // and let's add the founder, to save a step later
        addMember(owner, 'founder');
    }
    //************************************************************************
    
    // PUBLIC FUNCTION(s)
    /**
     * Add member
     *
     * Make `targetMember` a member named `memberName`
     *
     * @param targetMember ethereum address to be added
     * @param memberName public name for that member
    */
    function addMember(address targetMember, string memberName) onlyOwner public {
        uint id = memberId[targetMember];
        if(id == 0) {
            memberId[targetMember] = members.length;
            id = members.length++;
        }
        members[id] = Member({member : targetMember, memberSince : now, name : memberName});
        MembershipChanged(targetMember, true);
    }
    
    /**
     * Remove member
     *
     * @notice Remove membership from `targetMember`
     *
     * @param targetMember ethereum address to be removed
    */
    function removeMember(address targetMember) onlyOwner public {
        require(memberId[targetMember]!=0);
        for(uint i = memberId[targetMember]; i < members.length-1; i++) {
            members[i] = members[i+1];
        }
        delete members[members.length-1];
        members.length--;
        // modify member id
        memberId[targetMember] = 0;
    }
    
    /**
     * Change voting rules
     *
     * Make so that proposals need to be discussed for at least `minutesForDebate/60` hours,
     * have at least `minimumQuorumForProposals` votes, and have 50% + `marginOfVotesForMajority` votes to be executed
     *
     * @param minimumQuorumForProposals how many members must vote on a proposal for it to be executed
     * @param minutesForDebate the minimum amount of delay between when a proposal is made and when it can be executed
     * @param marginOfVotesForMajority the proposal needs to have 50% plus this number
    */
    function changeVotingRules(uint minimumQuorumForProposals, uint minutesForDebate,
        int marginOfVotesForMajority) onlyOwner public { 
        minimumQuorum = minimumQuorumForProposals;
        debatingPeriodInMinutes = minutesForDebate;
        majorityMargin = marginOfVotesForMajority;
        // call events to notify
        ChangeOfRules(minimumQuorum, debatingPeriodInMinutes, majorityMargin);
    }
    
    /**
     * Add Proposal
     *
     * Propose to send `weiAmount / 1e18` ether to `beneficiary` for `jobDescription`.
     * `transactionBytecode ? Contains : Does not contain` code.
     *
     * @param beneficiary who to send the ether to
     * @param weiAmount amount of ether to send, in wei
     * @param jobDescription Description of job
     * @param transactionBytecode bytecode of transaction
    */
    function newProposal(address beneficiary, uint weiAmount, string jobDescription, bytes transactionBytecode) 
        onlyMembers public returns (uint proposalID) {
        proposalID = proposals.length++;
        Proposal storage p = proposals[proposalID];
        p.recipient = beneficiary;
        p.amount = weiAmount;
        p.description = jobDescription;
        p.proposalHash = keccak256(beneficiary, weiAmount, transactionBytecode);
        p.votingDeadline = now + debatingPeriodInMinutes * 1 minutes;
        p.executed = false;
        p.numberOfVotes = 0;
        ProposalAdded(proposalID, beneficiary, weiAmount, jobDescription);
        numProposals = proposalID+1;
        return proposalID;
    }
    
    /**
     * Add proposal in Ether
     *
     * Propose to send `etherAmount` ether to `beneficiary` for `jobDescription`. 
     * `transactionBytecode ? Contains : Does not contain` code.
     * This is a convenience function to use if the amount to be given is in round number of ether units.
     *
     * @param beneficiary who to send the ether to
     * @param etherAmount amount of ether to send
     * @param jobDescription Description of job
     * @param transactionBytecode bytecode of transaction
    */
    function newProposalInEther(address beneficiary, uint etherAmount, string jobDescription, bytes transactionBytecode)
        onlyMembers public returns (uint proposalID) {
        return newProposal(beneficiary, etherAmount * 1 ether, jobDescription, transactionBytecode);
    }
    
    /**
     * Log a vote for a proposal
     *
     * Vote `supportsProposal? in support of : against` proposal #`proposalNumber`
     *
     * @param proposalNumber number of proposal
     * @param supportsProposal either in favor or against it
     * @param justificationText optional justification text
    */
    function vote(uint proposalNumber, bool supportsProposal, string justificationText) 
        onlyMembers public returns (uint voteID) {
        Proposal storage p = proposals[proposalNumber];
        require(!p.voted[msg.sender]);
        p.voted[msg.sender] = true;
        p.numberOfVotes++;
        if(supportsProposal) {
            // add one support vote
            p.currentResult++;
        }
        else {
            // decrease the supporting score
            p.currentResult--;
        }
        Voted(proposalNumber, supportsProposal, msg.sender, justificationText);
        return p.numberOfVotes;
    }
    
    /**
     * Check if a proposal code matches
     *
     * @param proposalNumber ID number of the proposal to query
     * @param beneficiary who to send the ether to
     * @param weiAmount amount of ether to send
     * @param transactionBytecode bytecode of transaction
    */
    function checkProposalCode(uint proposalNumber, address beneficiary, uint weiAmount, bytes transactionBytecode) 
        constant public returns(bool codechecksOut) {
        Proposal storage p = proposals[proposalNumber];
        return p.proposalHash == keccak256(beneficiary, weiAmount, transactionBytecode);
    }
    
    /**
     * Finish vote
     *
     * Count the votes proposal #`proposalNumber` and execute it if approved
     *
     * @param proposalNumber proposal number
     * @param transactionBytecode optional: if the transaction contained a bytecode, you need to send it
    */
    function executeProposal(uint proposalNumber, bytes transactionBytecode) public {
        Proposal storage p = proposals[proposalNumber];
        debugExecute(now > p.votingDeadline, !p.executed, 
            p.proposalHash==keccak256(p.recipient, p.amount, transactionBytecode), p.numberOfVotes >= minimumQuorum);
        require(now > p.votingDeadline && !p.executed && p.proposalHash==keccak256(p.recipient, p.amount, transactionBytecode)
            && p.numberOfVotes >= minimumQuorum);
        // execute result
        if(p.currentResult > majorityMargin) {
            p.executed = true;
            // This line will have some bugs to terminate the function in Remix test mode
            // require(p.recipient.call.value(p.amount)(transactionBytecode));
            p.proposalPassed = true;
        }
        else {
            p.proposalPassed = false;
        }
        ProposalTallied(proposalNumber, p.currentResult, p.numberOfVotes, p.proposalPassed);
    }
    
    // this function is to debug executeProposal
    function debugExecuteProposal(uint proposalNumber, bytes transactionBytecode) public {
        Proposal storage p = proposals[proposalNumber];
        debugExecute(now > p.votingDeadline, !p.executed, 
            p.proposalHash==keccak256(p.recipient, p.amount, transactionBytecode), p.numberOfVotes >= minimumQuorum);
    }
    
}
//--------------------------------------------------------------------------------










