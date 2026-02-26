import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("MultiSig", function () {
  async function deployFixture() {
    const [owner, signer1, signer2, signer3, nonSigner, receiver] =
      await hre.ethers.getSigners();

    const MultiSig = await hre.ethers.getContractFactory("MultiSig");
    const multiSig = await MultiSig.deploy(
      [signer1.address, signer2.address, signer3.address],
      2
    );

    await owner.sendTransaction({
      to: await multiSig.getAddress(),
      value: hre.ethers.parseEther("10"),
    });

    return {
      multiSig,
      owner,
      signer1,
      signer2,
      signer3,
      nonSigner,
      receiver,
    };
  }

  describe("Deployment", function () {
    it("Should deploy correctly", async () => {
      const { multiSig } = await loadFixture(deployFixture);
      expect(multiSig).to.exist;
    });
  });

  describe("Initiate Transaction", function () {
    it("Valid signer can initiate a transaction", async () => {
      const { multiSig, signer1, receiver } = await loadFixture(deployFixture);

      await expect(
        multiSig.connect(signer1).initiateTransaction(1000, receiver.address)
      )
        .to.emit(multiSig, "TransactionInitiated")
        .withArgs(1, 1000, receiver.address, signer1.address);

      const txs = await multiSig.getAllTransactions();
      expect(txs.length).to.equal(1);
      expect(txs[0].id).to.equal(1);
      expect(txs[0].signersCount).to.equal(1);
      expect(txs[0].txCreator).to.equal(signer1.address);
    });

    it("Should revert for non-signer", async () => {
      const { multiSig, nonSigner, receiver } = await loadFixture(
        deployFixture
      );

      await expect(
        multiSig.connect(nonSigner).initiateTransaction(1000, receiver.address)
      ).to.be.revertedWith("not valid signer");
    });

    it("Should revert with zero amount", async () => {
      const { multiSig, signer1, receiver } = await loadFixture(deployFixture);

      await expect(
        multiSig.connect(signer1).initiateTransaction(0, receiver.address)
      ).to.be.revertedWith("no zero value allowed");
    });
  });

  describe("Approve Transaction", function () {
    it("Valid signer can approve a transaction", async () => {
      const { multiSig, signer1, signer2, receiver } = await loadFixture(
        deployFixture
      );

      await multiSig
        .connect(signer1)
        .initiateTransaction(1000, receiver.address);

      await expect(multiSig.connect(signer2).approveTransaction(1))
        .to.emit(multiSig, "TransactionApproved")
        .withArgs(1, signer2.address);
    });

    it("Should prevent double signing", async () => {
      const { multiSig, signer1, signer2, receiver } = await loadFixture(
        deployFixture
      );

      await multiSig
        .connect(signer1)
        .initiateTransaction(1000, receiver.address);

      // await multiSig.connect(signer1).approveTransaction(1);

      await expect(
        multiSig.connect(signer1).approveTransaction(1)
      ).to.be.revertedWith("can't sign twice");
    });

    it("Should revert for non-signer approver", async () => {
      const { multiSig, signer1, nonSigner, receiver } = await loadFixture(
        deployFixture
      );

      await multiSig
        .connect(signer1)
        .initiateTransaction(1000, receiver.address);

      await expect(
        multiSig.connect(nonSigner).approveTransaction(1)
      ).to.be.revertedWith("not valid signer");
    });

    it("Should auto-execute at quorum", async () => {
      const { multiSig, signer1, signer2, receiver } = await loadFixture(
        deployFixture
      );

      // Initial receiver balance
      const before = await hre.ethers.provider.getBalance(receiver.address);

      await multiSig
        .connect(signer1)
        .initiateTransaction(5000, receiver.address);

      await expect(multiSig.connect(signer2).approveTransaction(1))
        .to.emit(multiSig, "TransactionExecuted")
        .withArgs(1, receiver.address, 5000);

      const after = await hre.ethers.provider.getBalance(receiver.address);
      expect(after - before).to.equal(5000n);
    });

    it("Should revert if executing without enough contract balance", async () => {
      const { multiSig, signer1, signer2, receiver } = await loadFixture(
        deployFixture
      );

      await multiSig.connect(signer1).initiateTransaction(
        hre.ethers.parseEther("1000"), // too big
        receiver.address
      );

      await expect(
        multiSig.connect(signer2).approveTransaction(1)
      ).to.be.revertedWith("insufficient contract balance");
    });
  });

  describe("Cancel Transaction", function () {
    it("Tx creator can cancel", async () => {
      const { multiSig, signer1, receiver } = await loadFixture(deployFixture);

      await multiSig
        .connect(signer1)
        .initiateTransaction(1000, receiver.address);

      await expect(multiSig.connect(signer1).cancelTransaction(1))
        .to.emit(multiSig, "TransactionCancelled")
        .withArgs(1, signer1.address);
    });

    it("Owner can cancel", async () => {
      const { multiSig, owner, signer1, receiver } = await loadFixture(
        deployFixture
      );

      await multiSig
        .connect(signer1)
        .initiateTransaction(1000, receiver.address);

      await expect(multiSig.connect(owner).cancelTransaction(1))
        .to.emit(multiSig, "TransactionCancelled")
        .withArgs(1, owner.address);
    });

    it("Should revert if non-creator tries cancel", async () => {
      const { multiSig, signer1, signer2, receiver } = await loadFixture(
        deployFixture
      );

      await multiSig
        .connect(signer1)
        .initiateTransaction(1000, receiver.address);

      await expect(
        multiSig.connect(signer2).cancelTransaction(1)
      ).to.be.revertedWith("not authorized to cancel");
    });
  });

  describe("Ownership Transfer", function () {
    it("Owner can start transfer", async () => {
      const { multiSig, owner, signer1 } = await loadFixture(deployFixture);

      await expect(multiSig.connect(owner).transferOwnership(signer1.address))
        .to.emit(multiSig, "OwnershipTransferStarted")
        .withArgs(owner.address, signer1.address);
    });

    it("New owner can claim", async () => {
      const { multiSig, owner, signer1 } = await loadFixture(deployFixture);

      await multiSig.connect(owner).transferOwnership(signer1.address);

      await expect(multiSig.connect(signer1).claimOwnership())
        .to.emit(multiSig, "OwnershipClaimed")
        .withArgs(signer1.address);
    });

    it("Should revert if wrong account claims", async () => {
      const { multiSig, owner, signer1, signer2 } = await loadFixture(
        deployFixture
      );

      await multiSig.connect(owner).transferOwnership(signer1.address);

      await expect(
        multiSig.connect(signer2).claimOwnership()
      ).to.be.revertedWith("not next owner");
    });
  });

  describe("Signer Management", function () {
    it("Owner can add signer", async () => {
      const { multiSig, owner, nonSigner } = await loadFixture(deployFixture);

      await expect(multiSig.connect(owner).addValidSigner(nonSigner.address))
        .to.emit(multiSig, "SignerAdded")
        .withArgs(nonSigner.address);
    });

    it("Owner can remove signer", async () => {
      const { multiSig, owner, signer1 } = await loadFixture(deployFixture);

      await expect(multiSig.connect(owner).removeValidSigner(signer1.address))
        .to.emit(multiSig, "SignerRemoved")
        .withArgs(signer1.address);
    });

    it("Cannot remove non-existent signer", async () => {
      const { multiSig, owner, nonSigner } = await loadFixture(deployFixture);

      await expect(
        multiSig.connect(owner).removeValidSigner(nonSigner.address)
      ).to.be.revertedWith("signer not found");
    });
  });

  describe("View Functions", function () {
    it("Should return all transactions", async () => {
      const { multiSig, signer1, receiver } = await loadFixture(deployFixture);

      await multiSig
        .connect(signer1)
        .initiateTransaction(1000, receiver.address);

      const txs = await multiSig.getAllTransactions();
      expect(txs.length).to.equal(1);
      expect(txs[0].id).to.equal(1);
    });
  });
});
