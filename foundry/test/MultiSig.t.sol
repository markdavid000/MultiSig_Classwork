// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "../lib/forge-std/src/Test.sol";
import {MultiSig} from "../src/MultiSig.sol";
import {MultiSigFactory} from "../src/MultiSigFactory.sol";

contract MultiSigTest is Test {
    MultiSigFactory factory;
    MultiSig wallet;

    address signer1 = address(101);
    address signer2 = address(102);
    address signer3 = address(103);
    address nonSigner = address(104);
    address receiver = address(105);

    address[] signers;

    function setUp() public {
        vm.deal(address(factory), 100 ether);
        vm.deal(signer1, 100 ether);
        vm.deal(signer2, 100 ether);
        vm.deal(signer3, 100 ether);
        vm.deal(nonSigner, 100 ether);

        signers.push(signer1);
        signers.push(signer2);
        signers.push(signer3);

        factory = new MultiSigFactory();

        vm.prank(address(factory));
        address walletAddr = factory.createMultiSigWallet(signers, 2);
        wallet = MultiSig(payable(walletAddr));

        vm.deal(address(wallet), 20 ether);
    }

    function testInitiateTransaction() public {
        vm.prank(signer1);
        wallet.initiateTransaction(1 ether, receiver);

        MultiSig.Transaction[] memory txs = wallet.getAllTransactions();
        assertEq(txs.length, 1);
        assertEq(txs[0].amount, 1 ether);
        assertEq(txs[0].txCreator, signer1);
        assertEq(txs[0].signersCount, 1);
    }

    function testRevertNonSignerInitiateTx() public {
        vm.prank(nonSigner);
        vm.expectRevert("not valid signer");
        wallet.initiateTransaction(1 ether, receiver);
    }

    function testApproveTransaction() public {
        vm.prank(signer1);
        wallet.initiateTransaction(1 ether, receiver);

        vm.prank(signer2);
        wallet.approveTransaction(1);

        MultiSig.Transaction[] memory txs = wallet.getAllTransactions();
        assertEq(txs[0].signersCount, 2);
        assertEq(txs[0].isExecuted, true);
    }

    function testCannotSignTwice() public {
        vm.prank(signer1);
        wallet.initiateTransaction(1 ether, receiver);

        vm.prank(signer1);
        vm.expectRevert("can't sign twice");
        wallet.approveTransaction(1);
    }

    function testRevertInsufficientBalance() public {
        vm.prank(signer1);
        wallet.initiateTransaction(50 ether, receiver);

        vm.prank(signer2);
        vm.expectRevert("insufficient contract balance");
        wallet.approveTransaction(1);
    }

    function testCreatorCancelTransaction() public {
        vm.prank(signer1);
        wallet.initiateTransaction(1 ether, receiver);

        vm.prank(signer1);
        wallet.cancelTransaction(1);

        MultiSig.Transaction[] memory txs = wallet.getAllTransactions();
        assertEq(txs[0].isExecuted, true);
    }

    function testOwnerCancelTransaction() public {
        vm.prank(signer1);
        wallet.initiateTransaction(1 ether, receiver);

        vm.prank(address(factory));
        wallet.cancelTransaction(1);
    }

    function testRevertNonCreatorCancel() public {
        vm.prank(signer1);
        wallet.initiateTransaction(1 ether, receiver);

        vm.prank(signer2);
        vm.expectRevert("not authorized to cancel");
        wallet.cancelTransaction(1);
    }

    function testOwnershipTransfer() public {
        vm.prank(address(factory));
        wallet.transferOwnership(nonSigner);

        vm.prank(nonSigner);
        wallet.claimOwnership();
    }

    function testRevertInvalidClaim() public {
        vm.prank(address(factory));
        wallet.transferOwnership(nonSigner);

        vm.prank(signer1);
        vm.expectRevert("not next owner");
        wallet.claimOwnership();
    }

    function testAddSigner() public {
        vm.prank(address(factory));
        wallet.addValidSigner(nonSigner);
    }

    function testRemoveSigner() public {
        vm.prank(address(factory));
        wallet.removeValidSigner(signer1);
    }

    function testRevertRemoveNonSigner() public {
        vm.prank(address(factory));
        vm.expectRevert("signer not found");
        wallet.removeValidSigner(nonSigner);
    }
}