// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MultiSig.sol";

contract MultiSigFactory {
    address[] multiSigClones;

    function createMultiSigWallet(address[] memory _validSigners, uint256 _quorum) external returns (address) {
        MultiSig newMulSig_ = new MultiSig(_validSigners, _quorum);

        multiSigClones.push(address(newMulSig_));

        return (address(newMulSig_));
    }
}