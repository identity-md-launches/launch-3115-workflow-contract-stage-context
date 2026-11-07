// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SqueekTestBase, Squeeklings, Pet, Expedition} from "./TestBase.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract HatchReceiver is IERC721Receiver {
    Squeeklings public game;
    bool public reject;
    bytes4 public reentryError;
    uint256 public observedSupply;
    bool public observedHatched;

    constructor(Squeeklings game_) {
        game = game_;
    }

    function start(bool reject_) external {
        reject = reject_;
        game.hatch();
    }

    function onERC721Received(address, address, uint256 id, bytes calldata) external returns (bytes4) {
        observedSupply = game.totalSupply();
        observedHatched = game.hasHatched(address(this));
        require(game.pet(id).seed != bytes32(0), "pet not initialized");
        try game.hatch() {
            revert("reentered");
        } catch (bytes memory reason) {
            reentryError = bytes4(reason);
        }
        return reject ? bytes4(0) : IERC721Receiver.onERC721Received.selector;
    }
}

contract HatchAndOwnershipTest is SqueekTestBase {
    function testHatchIsFreeUniqueAndHasExpectedSeed() public {
        vm.setBlockhash(99, keccak256("previous block"));
        uint256 id = hatch(alice);
        assertEq(id, 1);
        assertEq(game.name(), "Squeeklings");
        assertEq(game.symbol(), "SQLING");
        assertEq(game.totalSupply(), 1);
        assertEq(game.balanceOf(alice), 1);
        assertEq(game.ownerOf(id), alice);
        assertEq(game.pet(id).seed, keccak256(abi.encode(blockhash(99), alice, id)));
        assertTrue(game.hasHatched(alice));
        assertEq(game.pet(id).birthUnits, 0);
        assertEq(game.pet(id).pity, 0);
        assertTrue(game.supportsInterface(0x80ac58cd));
        assertTrue(game.supportsInterface(0x5b5e139f));
        assertTrue(game.supportsInterface(0x01ffc9a7));
        assertFalse(game.supportsInterface(0xffffffff));
        vm.prank(alice);
        vm.expectRevert(Squeeklings.AlreadyHatched.selector);
        game.hatch();
    }

    function testTransferDoesNotResetHatchEligibilityOrBlockRecipientsHatch() public {
        uint256 id = hatch(alice);
        vm.prank(alice);
        game.transferFrom(alice, bob, id);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.AlreadyHatched.selector);
        game.hatch();
        assertEq(hatch(bob), 2);
        assertEq(game.balanceOf(bob), 2);
    }

    function testCapAllowsLastPetThenRejects() public {
        game.setSupply(88_887);
        assertEq(hatch(alice), 88_888);
        vm.prank(bob);
        vm.expectRevert(Squeeklings.SupplyCap.selector);
        game.hatch();
        assertFalse(game.hasHatched(bob));
    }

    function testNoPayableEntrypointsOrFallback() public {
        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        (bool hatchOk,) = address(game).call{value: 1}(abi.encodeCall(Squeeklings.hatch, ()));
        (bool sendOk,) = address(game).call{value: 1}("");
        vm.stopPrank();
        assertFalse(hatchOk);
        assertFalse(sendOk);
        assertEq(address(game).balance, 0);
        assertEq(game.totalSupply(), 0);
    }

    function testSafeMintStatePrecedesCallbackAndReentryIsRejected() public {
        HatchReceiver receiver = new HatchReceiver(game);
        receiver.start(false);
        assertEq(receiver.observedSupply(), 1);
        assertTrue(receiver.observedHatched());
        assertEq(receiver.reentryError(), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(game.balanceOf(address(receiver)), 1);
    }

    function testRejectingReceiverRollsBackHatch() public {
        HatchReceiver receiver = new HatchReceiver(game);
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(receiver))
        );
        receiver.start(true);
        assertEq(game.totalSupply(), 0);
        assertFalse(game.hasHatched(address(receiver)));
        receiver.start(false);
        assertEq(game.ownerOf(1), address(receiver));
    }

    function testApprovalCanTransferAtHomeButCannotManagePet() public {
        uint256 id = hatch(alice);
        vm.prank(alice);
        game.approve(bob, id);
        vm.startPrank(bob);
        vm.expectRevert(Squeeklings.NotPetOwner.selector);
        game.embark(id, 0);
        vm.expectRevert(Squeeklings.NotPetOwner.selector);
        game.unequip(id, 0);
        game.transferFrom(alice, bob, id);
        vm.stopPrank();
        assertEq(game.ownerOf(id), bob);
        assertEq(game.getApproved(id), address(0));
    }

    function testUnknownPetUsesERC721Error() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        game.pet(1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        game.tokenURI(1);
    }

    function testConstructorsNeedNoDependencyCodeAndOwnerIsExplicit() public {
        address suppliedCore = 0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4;
        address suppliedOwner = 0x60731C2F051dA8708E405f64e803F3c8D1059dee;
        Squeeklings deployed = new Squeeklings(suppliedCore, address(art), suppliedOwner);
        assertEq(deployed.owner(), suppliedOwner);
        assertEq(deployed.core(), suppliedCore);
        assertEq(deployed.coreEpoch(), 1);
        vm.expectRevert(Squeeklings.CoreUnavailable.selector);
        deployed.hatch();
    }

    function testConstructorRejectsMissingDependenciesAndOwner() public {
        vm.expectRevert(Squeeklings.InvalidAddress.selector);
        new Squeeklings(address(0), address(art), admin);
        vm.expectRevert(Squeeklings.InvalidAddress.selector);
        new Squeeklings(address(core), address(0), admin);
        vm.expectRevert(Squeeklings.InvalidAddress.selector);
        new Squeeklings(address(core), address(art), address(0));
    }
}
