// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Squeeklings} from "../src/Squeeklings.sol";
import {SqueeklingsArt} from "../src/SqueeklingsArt.sol";

contract FactoryProbe {
    function deploy(bytes memory artCode, bytes memory gameCode, address core, address owner)
        external
        returns (SqueeklingsArt art, Squeeklings game)
    {
        address created;
        assembly ("memory-safe") { created := create2(0, add(artCode, 32), mload(artCode), 1) }
        require(created != address(0), "art deployment failed");
        art = SqueeklingsArt(created);
        bytes memory init = bytes.concat(gameCode, abi.encode(core, created, owner));
        assembly ("memory-safe") { created := create2(0, add(init, 32), mload(init), 2) }
        require(created != address(0), "game deployment failed");
        game = Squeeklings(created);
    }
}

contract DeploymentTest is Test {
    function testFactoryDeploymentUsesExplicitOwnerAndBoundedRuntimes() public {
        FactoryProbe factory = new FactoryProbe();
        address owner = 0x60731C2F051dA8708E405f64e803F3c8D1059dee;
        address core = 0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4;
        (SqueeklingsArt art, Squeeklings game) =
            factory.deploy(type(SqueeklingsArt).creationCode, type(Squeeklings).creationCode, core, owner);
        assertEq(game.owner(), owner);
        assertNotEq(game.owner(), address(factory));
        assertEq(game.art(), address(art));
        _checkCode(address(art).code);
        _checkCode(address(game).code);
        assertLe(type(Squeeklings).creationCode.length + 96, 49_152);
        assertLe(type(SqueeklingsArt).creationCode.length, 49_152);
    }

    function _checkCode(bytes memory code) private pure {
        assertGt(code.length, 0);
        assertLe(code.length, 24_576);
        bool reachable = true;
        for (uint256 i; i < code.length; ++i) {
            uint8 op = uint8(code[i]);
            if (op == 0x5b) reachable = true;
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            if (reachable) assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
            if (op == 0x00 || op == 0x56 || op == 0xf3 || op == 0xfd || op == 0xfe || op == 0xff) {
                reachable = false;
            }
        }
    }
}
