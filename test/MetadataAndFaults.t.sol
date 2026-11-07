// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SqueekTestBase, Squeeklings, Expedition, PetView, Mood, Stage, Slot} from "./TestBase.sol";
import {ISqueekCoreV3} from "../src/interfaces/ISqueekCoreV3.sol";
import {GasBurner, LargeReturn} from "./mocks/Harnesses.sol";

contract MetadataAndFaultsTest is SqueekTestBase {
    function testTokenURIDecodesToJSONAndSelfContainedAnimatedSVG() public {
        uint256 id = hatch(alice);
        string memory uri = game.tokenURI(id);
        assertEq(uri, art.render(id, game.displayData(id)));
        string memory json = decodeDataURI(uri);
        assertEq(vm.parseJsonString(json, ".name"), "Squeekling #1");
        assertEq(vm.parseJsonString(json, ".attributes[0].value"), "Pinky");
        assertEq(vm.parseJsonString(json, ".attributes[1].value"), "Napping");
        assertEq(vm.parseJsonUint(json, ".attributes[4].value"), 0);
        assertEq(vm.parseJsonUint(json, ".attributes[5].value"), 0);
        string memory svg = decodeDataURI(vm.parseJsonString(json, ".image"));
        assertEq(svg, art.svg(game.displayData(id)));
        assertTrue(contains(svg, '<svg xmlns="http://www.w3.org/2000/svg"'));
        assertTrue(contains(svg, "@keyframes breath"));
        assertTrue(contains(svg, "@keyframes blink"));
        assertTrue(contains(svg, "prefers-reduced-motion:reduce"));
        assertFalse(contains(svg, "<script"));
        assertFalse(contains(svg, "<animate"));
        assertFalse(contains(svg, "href="));
    }

    function testSixPalettesAndStageSizesAreDifferent() public view {
        PetView memory data;
        bytes32[6] memory hashes;
        for (uint256 i; i < 6; ++i) {
            data.seed = bytes32(i);
            hashes[i] = keccak256(bytes(art.svg(data)));
            for (uint256 j; j < i; ++j) {
                assertNotEq(hashes[i], hashes[j]);
            }
        }
        bytes32 previous;
        for (uint8 i; i < 4; ++i) {
            data.stage = Stage(i);
            bytes32 hash = keccak256(bytes(art.svg(data)));
            assertNotEq(hash, previous);
            previous = hash;
        }
    }

    function testEachEquipmentItemHasVisibleArtAndCorrectMetadataName() public {
        uint256 id = hatch(alice);
        bytes32 plain = keccak256(bytes(art.svg(game.displayData(id))));
        for (uint8 item = 1; item <= 17; ++item) {
            game.giveItem(id, item);
            vm.prank(alice);
            game.equip(id, item);
            (string memory itemName, Slot slot,,) = game.itemInfo(item);
            PetView memory data = game.displayData(id);
            assertNotEq(keccak256(bytes(art.svg(data))), plain);
            string memory json = decodeDataURI(art.render(id, data));
            assertTrue(contains(json, itemName));
            if (item == 8 || item == 16) assertTrue(contains(art.svg(data), 'class="shimmer"'));
            vm.prank(alice);
            game.unequip(id, uint8(slot));
        }
    }

    function testMoodAndAwayArtFollowContractState() public {
        uint256 id = hatch(alice);
        core.append(500, 1e9, bytes32("run"));
        assertTrue(contains(art.svg(game.displayData(id)), 'class="speed"'));
        embark(id, 1);
        string memory json = decodeDataURI(game.tokenURI(id));
        assertEq(vm.parseJsonString(json, ".attributes[3].value"), "On expedition");
        assertEq(vm.parseJsonString(json, ".attributes[1].value"), "Zoomies");
    }

    function testStateConfigAndPagingOutagesReturnSignalLost() public {
        uint256 id = hatch(alice);
        core.setFaults(true, false, false);
        _assertSignalLost(id);
        vm.prank(bob);
        vm.expectRevert(Squeeklings.CoreUnavailable.selector);
        game.hatch();
        core.setFaults(false, true, false);
        _assertSignalLost(id);
        vm.prank(alice);
        vm.expectRevert(Squeeklings.CoreUnavailable.selector);
        game.embark(id, 0);
        core.setFaults(false, false, true);
        _assertSignalLost(id);
        core.setFaults(false, false, false);
        assertFalse(game.displayData(id).signalLost);
    }

    function testMalformedShortAndNonCanonicalStatesCannotBreakMetadata() public {
        uint256 id = hatch(alice);
        bytes memory selector = abi.encodeCall(ISqueekCoreV3.state, ());
        vm.mockCall(address(core), selector, hex"1234");
        _assertSignalLost(id);
        vm.mockCall(address(core), selector, abi.encode(uint256(1) << 64, 0, 0, 0, 0, 0, 0, 0));
        _assertSignalLost(id);
        vm.mockCall(address(core), selector, abi.encode(0, 0, 0, 0, 0, 0, 0, 2));
        _assertSignalLost(id);
        vm.clearMockedCalls();
        vm.mockCall(address(core), abi.encodeCall(ISqueekCoreV3.configuration, ()), hex"1234");
        _assertSignalLost(id);
        vm.clearMockedCalls();
    }

    function testGasBurningAndOversizedCoreResponsesAreBounded() public {
        uint256 id = hatch(alice);
        GasBurner burner = new GasBurner();
        vm.etch(address(core), address(burner).code);
        _assertSignalLost(id);
        LargeReturn large = new LargeReturn();
        vm.etch(address(core), address(large).code);
        _assertSignalLost(id);
    }

    function testMissingBrokenAndMalformedArtUsesEmbeddedFallback() public {
        uint256 id = hatch(alice);
        vm.etch(address(art), hex"");
        _assertArtFallback(id);
        GasBurner burner = new GasBurner();
        vm.etch(address(art), address(burner).code);
        _assertArtFallback(id);
        LargeReturn large = new LargeReturn();
        vm.etch(address(art), address(large).code);
        _assertArtFallback(id);
        vm.mockCall(address(art), bytes(""), abi.encode(uint256(32), type(uint256).max));
        _assertArtFallback(id);
        vm.mockCall(address(art), bytes(""), abi.encode(uint256(1), uint256(1), bytes32("x")));
        _assertArtFallback(id);
        vm.clearMockedCalls();
    }

    function testMalformedPageABIIsRejectedBeforeDecode() public {
        uint256 id = hatch(alice);
        Expedition memory trip = embark(id, 0);
        settleEmpty(trip.endRound);
        bytes memory query = abi.encodeCall(ISqueekCoreV3.roundPage, (uint64(1), trip.endRound, uint256(16)));
        bytes memory response = abi.encode(
            uint256(trip.endRound),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(256),
            type(uint256).max
        );
        vm.mockCall(address(core), query, response);
        vm.expectRevert(Squeeklings.InvalidHistory.selector);
        game.returnHome(id);
        assertTrue(game.expedition(id).away);
        vm.clearMockedCalls();
        game.returnHome(id);
    }

    function testFuzzMalformedCoreResponsesCannotRevertDisplay(bytes memory response, uint8 choice) public {
        uint256 id = hatch(alice);
        bytes4 selector = choice % 3 == 0
            ? ISqueekCoreV3.state.selector
            : choice % 3 == 1 ? ISqueekCoreV3.configuration.selector : ISqueekCoreV3.roundPage.selector;
        vm.mockCall(address(core), abi.encodePacked(selector), response);
        // The property is totality of the view, including malformed narrow integers and array offsets.
        PetView memory data = game.displayData(id);
        assertEq(data.seed, game.pet(id).seed);
        assertEq(data.pity, 0);
        vm.clearMockedCalls();
    }

    function _assertSignalLost(uint256 id) private view {
        PetView memory data = game.displayData(id);
        assertTrue(data.signalLost);
        string memory json = decodeDataURI(game.tokenURI(id));
        assertEq(vm.parseJsonString(json, ".attributes[1].value"), "Signal lost");
        assertTrue(contains(decodeDataURI(vm.parseJsonString(json, ".image")), "Signal lost"));
        assertEq(game.ownerOf(id), alice);
    }

    function _assertArtFallback(uint256 id) private view {
        string memory json = decodeDataURI(game.tokenURI(id));
        assertEq(vm.parseJsonString(json, ".name"), "Squeekling #1");
        assertTrue(contains(vm.parseJsonString(json, ".description"), "Signal lost"));
        assertTrue(contains(decodeDataURI(vm.parseJsonString(json, ".image")), "Signal lost"));
    }
}
