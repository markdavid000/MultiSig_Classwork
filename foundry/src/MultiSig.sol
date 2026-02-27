// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract MultiSig {
    address owner;
    address[] signers;
    uint256 public quorum;
    uint256 txCount;

    address nextOwner;

    struct Transaction {
        uint256 id;
        uint256 amount;
        address receiver;
        uint256 signersCount;
        bool isExecuted;
        address txCreator;
    }

    Transaction[] allTransactions;

    // mapping of transaction id to signer address returning bool:
    // this checks if a valid signer has signed a trasaction
    mapping (uint256 => mapping (address => bool)) hasSigned;

    // mapping of transaction id to transaction struct
    // used to track transactions given their ID;
    mapping(uint256 => Transaction) public transactions;

    mapping(address => bool) isValidSigner;

    event TransactionInitiated(uint256 indexed txId, uint256 amount, address indexed receiver, address indexed creator);
    event TransactionApproved(uint256 indexed txId, address indexed signer);
    event TransactionExecuted(uint256 indexed txId, address indexed receiver, uint256 amount);
    event TransactionCancelled(uint256 indexed txId, address indexed canceller);

    event SignerAdded(address indexed newSigner);
    event SignerRemoved(address indexed signer);
    event OwnershipTransferStarted(address indexed oldOwner, address indexed newOwner);
    event OwnershipClaimed(address indexed newOwner);


    constructor(address[] memory _validSigners, uint256 _quorum) {
        owner = msg.sender;
        signers = _validSigners;
        quorum = _quorum;

        for(uint8 i = 0; i < _validSigners.length; i++) {
            require(_validSigners[i] != address(0), "get out");

            isValidSigner[_validSigners[i]] = true;
        }
    }

    function initiateTransaction(uint256 _amount, address _receiver) external {
        require(msg.sender != address(0), "zero address detected");
        require(_amount > 0, "no zero value allowed");

        onlyValidSigner();

        uint256 _txId = txCount + 1;

        Transaction storage tns = transactions[_txId];

        tns.id = _txId;
        tns.amount = _amount;
        tns.receiver = _receiver;
        tns.signersCount = tns.signersCount + 1;
        tns.txCreator = msg.sender;

        allTransactions.push(tns);

        hasSigned[_txId][msg.sender] = true;

        txCount = txCount + 1;

        emit TransactionInitiated(_txId, _amount, _receiver, msg.sender);
    }

    function approveTransaction(uint256 _txId) external {
        require(_txId <= txCount, "invalid transaction id");
        require(msg.sender != address(0), "zero address detected");

        onlyValidSigner();

        require(!hasSigned[_txId][msg.sender], "can't sign twice");

        Transaction storage tns = transactions[_txId];

        require(address(this).balance >= tns.amount, "insufficient contract balance");

        require(!tns.isExecuted, "transaction already executed");
        require(tns.signersCount < quorum, "quorum count reached");

        tns.signersCount = tns.signersCount + 1;

        hasSigned[_txId][msg.sender] = true;

        emit TransactionApproved(_txId, msg.sender);

        if(tns.signersCount == quorum) {
            tns.isExecuted = true;
            for (uint256 i = 0; i < allTransactions.length; i++) {
                if (allTransactions[i].id == _txId) {
                    allTransactions[i].signersCount = tns.signersCount;
                    allTransactions[i].isExecuted = tns.isExecuted;
                    break;
                }
            }
            (bool success, ) = payable(tns.receiver).call{ value: tns.amount }("");
            require(success, "Ether transfer failed");
        }

        emit TransactionExecuted(_txId, tns.receiver, tns.amount);
    }

    function cancelTransaction(uint256 _txId) external {
    require(_txId <= txCount, "invalid transaction id");

    Transaction storage tns = transactions[_txId];

    require(!tns.isExecuted, "tx already executed");

    require(
        msg.sender == tns.txCreator || msg.sender == owner,
        "not authorized to cancel"
    );

    tns.isExecuted = true;

    for (uint256 i = 0; i < allTransactions.length; i++) {
        if (allTransactions[i].id == _txId) {
            allTransactions[i].isExecuted = true;
            break;
        }
    }

    emit TransactionCancelled(_txId, msg.sender);
}

    function transferOwnership(address _newOwner) external {
        onlyOwner();

        nextOwner = _newOwner;

        emit OwnershipTransferStarted(owner, _newOwner);
    }

    function claimOwnership() external {
        require(msg.sender == nextOwner, "not next owner");

        owner = msg.sender;
        
        nextOwner = address(0);

        emit OwnershipClaimed(msg.sender);
    }

    function addValidSigner(address _newSigner) external {
        onlyOwner();

        require(!isValidSigner[_newSigner], "signer already exist");

        isValidSigner[_newSigner] = true;
        signers.push(_newSigner);
        quorum = quorum + 1;

        emit SignerAdded(_newSigner);
    }

    function removeValidSigner(address _signer) external {
    onlyOwner();
    require(isValidSigner[_signer], "signer not found");

    isValidSigner[_signer] = false;

    for (uint256 i = 0; i < signers.length; i++) {
        if (signers[i] == _signer) {
            signers[i] = signers[signers.length - 1];
            signers.pop();
            break;
        }
    }

    quorum = quorum - 1;

    emit SignerRemoved(_signer);
}

    function getAllTransactions() external view returns (Transaction[] memory) {
        return allTransactions;
    }

    function onlyOwner() private view {
        require(msg.sender == owner, "not owner");
    }

    function onlyValidSigner() private view {
        require(isValidSigner[msg.sender], "not valid signer");
    }

    receive() external payable {}

    fallback() external payable {}
}