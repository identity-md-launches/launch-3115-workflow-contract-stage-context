// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {PetView, Stage, Mood} from "./SqueekTypes.sol";
import {SqueekLoot} from "./libraries/SqueekLoot.sol";

/// @title Pure on-chain Squeeklings art and metadata. No storage, external calls, scripts, or remote assets.
contract SqueeklingsArt {
    using Strings for uint256;

    function render(uint256 tokenId, PetView calldata data) external pure returns (string memory) {
        string memory picture = svg(data);
        string memory attributes = string.concat(
            _trait("Stage", _stageName(data.stage)),
            ",",
            _trait("Mood", _moodName(data)),
            ",",
            _trait("Fur", _paletteName(uint256(data.seed) % 6)),
            ",",
            _trait("Location", data.away ? "On expedition" : "Home"),
            ",",
            '{"display_type":"number","trait_type":"Age blocks","value":',
            data.ageBlocks.toString(),
            "},",
            '{"display_type":"number","trait_type":"Pity","value":',
            uint256(data.pity).toString(),
            "},",
            _trait("Head", _itemName(data.equipped[0])),
            ",",
            _trait("Neck", _itemName(data.equipped[1])),
            ",",
            _trait("Hand", _itemName(data.equipped[2])),
            ",",
            _trait("Background", _itemName(data.equipped[3]))
        );
        bytes memory json = bytes(
            string.concat(
                '{"name":"Squeekling #',
                tokenId.toString(),
                '","description":"A free on-chain pet on Sepolia. Naps are adventures too. ',
                'Every trip opens one free Seed Capsule. No payments, prizes, or pressure to run. Testnet with no value.",',
                '"image":"data:image/svg+xml;base64,',
                Base64.encode(bytes(picture)),
                '","attributes":[',
                attributes,
                "]}"
            )
        );
        return string.concat("data:application/json;base64,", Base64.encode(json));
    }

    function svg(PetView calldata data) public pure returns (string memory) {
        (string memory fur, string memory ear) = _palette(uint256(data.seed) % 6);
        string memory scale = data.stage == Stage.Pinky
            ? ".68"
            : data.stage == Stage.Fuzz ? ".82" : data.stage == Stage.Runner ? ".94" : "1";
        bool sleeping = data.mood == Mood.Napping || data.signalLost;
        string memory face = sleeping
            ? '<path d="M124 198q9 9 18 0m36 0q9 9 18 0" fill="none" stroke="#483247" stroke-width="5" stroke-linecap="round"/>'
            : '<g class="blink"><ellipse cx="134" cy="198" rx="6" ry="8" fill="#483247"/><ellipse cx="186" cy="198" rx="6" ry="8" fill="#483247"/><circle cx="136" cy="195" r="2" fill="white"/><circle cx="188" cy="195" r="2" fill="white"/></g>';
        string memory body = string.concat(
            '<g transform="translate(160 258) scale(',
            scale,
            ') translate(-160 -258)"><g class="breathe">',
            '<g fill="',
            fur,
            '" stroke="#644759" stroke-width="4">',
            '<ellipse cx="160" cy="222" rx="64" ry="59"/><circle cx="112" cy="149" r="22"/><circle cx="208" cy="149" r="22"/>',
            '<ellipse cx="160" cy="191" rx="65" ry="55"/></g>',
            '<g fill="',
            ear,
            '"><circle cx="112" cy="149" r="13"/><circle cx="208" cy="149" r="13"/></g>',
            '<ellipse cx="160" cy="231" rx="39" ry="35" fill="#fff1db"/>',
            '<g fill="',
            ear,
            '"><ellipse cx="121" cy="269" rx="17" ry="10"/><ellipse cx="199" cy="269" rx="17" ry="10"/></g>',
            face,
            '<g fill="#f4acb3" opacity=".65"><ellipse cx="115" cy="216" rx="12" ry="7"/><ellipse cx="205" cy="216" rx="12" ry="7"/></g>',
            '<path d="M154 214q6-6 12 0l-6 6z" fill="#ae7184"/><path d="M160 220v4m0 0q-5 5-10 0m10 0q5 5 10 0" stroke="#644759" fill="none" stroke-width="2" stroke-linecap="round"/>',
            data.stage == Stage.Elder
                ? '<path d="m110 220-23-3m25 10-23 4m121-11 23-3m-25 10 23 4" stroke="#fff1db" stroke-width="3"/>'
                : "",
            _neck(data.equipped[1]),
            _head(data.equipped[0]),
            _hand(data.equipped[2]),
            "</g></g>"
        );
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 360" role="img" aria-label="Squeekling: ',
            _moodName(data),
            '">',
            "<style>.breathe{transform-origin:160px 268px;animation:breath 3.8s ease-in-out infinite}.blink{transform-origin:160px 198px;animation:blink 5s infinite}.zzz{animation:drift 3s ease-in-out infinite}.speed{animation:dash .8s ease-in-out infinite}.shimmer{animation:shine 2s ease-in-out infinite}@keyframes breath{50%{transform:scale(1.025,1.035)}}@keyframes blink{0%,43%,47%,100%{transform:scaleY(1)}45%{transform:scaleY(.08)}}@keyframes drift{0%,100%{opacity:.3;transform:translateY(0)}50%{opacity:1;transform:translateY(-10px)}}@keyframes dash{50%{opacity:.25;transform:translateX(-7px)}}@keyframes shine{50%{opacity:.45}}@media(prefers-reduced-motion:reduce){.breathe,.blink,.zzz,.speed,.shimmer{animation:none!important}}</style>",
            '<defs><linearGradient id="sky" x2="0" y2="1"><stop stop-color="#29243e"/><stop offset="1" stop-color="#554262"/></linearGradient><linearGradient id="aurora"><stop stop-color="#82e8c3"/><stop offset=".5" stop-color="#c2a2ec"/><stop offset="1" stop-color="#f3bdcf"/></linearGradient></defs>',
            '<rect width="320" height="360" rx="28" fill="#f4e7cf"/><path d="M20 292V146a140 140 0 0 1 280 0v146z" fill="url(#sky)"/>',
            '<g fill="#f6db9c"><circle cx="57" cy="128" r="2"/><circle cx="256" cy="101" r="2"/><circle cx="208" cy="65" r="2"/><path d="m76 72 2 5 5 2-5 2-2 5-2-5-5-2 5-2z"/></g>',
            _background(data.equipped[3]),
            '<ellipse cx="160" cy="284" rx="106" ry="15" fill="#b4a181" opacity=".5"/>',
            body,
            sleeping
                ? '<g class="zzz" fill="#e6d9fa" font-family="monospace"><text x="229" y="160" font-size="19">Z</text><text x="249" y="139" font-size="14">z</text><text x="265" y="122" font-size="11">z</text></g>'
                : "",
            !sleeping && data.mood == Mood.Zoomies
                ? '<g class="speed" stroke="#eedcaa" stroke-width="4" stroke-linecap="round"><path d="M52 206h29m-37 16h30m167-18h28m-24 17h30"/></g>'
                : "",
            data.away
                ? '<path d="m42 288 21-9 21 9 21-9m110 9 21-9 21 9 21-9" stroke="#d3bc86" stroke-width="3" fill="none"/>'
                : "",
            '<g fill="#584453" text-anchor="middle" font-family="monospace"><text x="160" y="321" font-size="17">',
            _moodName(data),
            '</text><text x="160" y="343" font-size="11">',
            _stageName(data.stage),
            data.away ? " / On expedition" : " / Cozy at home",
            "</text></g></svg>"
        );
    }

    function _head(uint8 id) private pure returns (string memory) {
        if (id == 3) {
            return '<g fill="#a0cb78" stroke="#426c4d" stroke-width="2"><path d="m162 149 4-23"/><circle cx="158" cy="126" r="8"/><circle cx="172" cy="126" r="8"/><circle cx="165" cy="115" r="8"/></g>';
        }
        if (id == 6) {
            return '<path d="M111 172q3-50 49-50t49 50q-49-17-98 0z" fill="#a97953" stroke="#684b40" stroke-width="4"/><path d="M160 125v35m-22-30-6 32m48-32 6 32" stroke="#d5ac78" stroke-width="3"/>';
        }
        if (id == 11) {
            return '<path d="M116 159q18-65 86-50l-15 43z" fill="#9395cf" stroke="#5c5388" stroke-width="3"/><path d="m116 158q36-15 76-5" stroke="#f9e6d9" stroke-width="13"/><circle cx="202" cy="109" r="10" fill="#f9e6d9"/>';
        }
        if (id == 14) {
            return '<path d="m119 151-6-29 23 13 24-29 24 29 23-13-6 29z" fill="#dbbdf3" stroke="#eacb77" stroke-width="3"/><path d="m160 110 3 10 10 3-10 3-3 10-3-10-10-3 10-3z" fill="#fff2bd"/>';
        }
        return "";
    }

    function _neck(uint8 id) private pure returns (string memory) {
        if (id == 4 || id == 12) {
            return string.concat(
                '<g fill="',
                id == 4 ? "#94bc78" : "#a89bcf",
                '" stroke="#655878" stroke-width="2"><path d="M115 236q45 17 90 0l-3 13q-44 15-84 0z"/><path d="m182 250-3 27 18-8-4-23z"/></g>'
            );
        }
        if (id == 8) {
            return '<path d="M121 235q39 36 78 0" stroke="#e6c473" stroke-width="3" fill="none"/><g class="shimmer"><circle cx="160" cy="255" r="12" fill="#f8d776" stroke="#b78048" stroke-width="2"/><path d="m161 245-7 11h7l-2 10 9-13h-7z" fill="#fff8d3"/></g>';
        }
        if (id == 16) {
            return '<path d="M121 235q39 36 78 0" stroke="#e6c473" stroke-width="3" fill="none"/><path class="shimmer" d="m160 242 4 8 10 1-7 7 2 10-9-5-9 5 2-10-7-7 10-1z" fill="#ffe5a3" stroke="#ba8b66" stroke-width="2"/>';
        }
        return "";
    }

    function _hand(uint8 id) private pure returns (string memory) {
        if (id == 1) {
            return '<ellipse cx="210" cy="251" rx="12" ry="16" fill="#b88453" stroke="#6b5145" stroke-width="2"/><path d="M196 246q14-17 28 0z" fill="#735747"/><path d="m210 235 3-6" stroke="#735747" stroke-width="3"/>';
        }
        if (id == 2) {
            return '<path d="M209 230q-22 25 0 38 22-13 0-38z" fill="#554659" stroke="#f1deba" stroke-width="3"/><path d="m209 236-2 24" stroke="#f1deba" stroke-width="2"/>';
        }
        if (id == 9) {
            return '<ellipse cx="210" cy="252" rx="15" ry="12" fill="#babde0" stroke="#7e79a7" stroke-width="2"/><circle cx="205" cy="250" r="3" fill="#999cc2"/><circle cx="216" cy="256" r="2" fill="#999cc2"/>';
        }
        if (id == 10) {
            return '<path d="m210 233 5 11 12 2-9 9 2 12-10-6-10 6 2-12-9-9 12-2z" fill="#f5e3ab" stroke="#be976a" stroke-width="2"/>';
        }
        if (id == 17) {
            return '<circle cx="210" cy="252" r="16" fill="#eee3c1" stroke="#a57e56" stroke-width="4"/><path d="m210 240-5 12 5 12 5-12z" fill="#b88395"/><path d="m210 240-5 12h5z" fill="#675475"/>';
        }
        return "";
    }

    function _background(uint8 id) private pure returns (string memory) {
        if (id == 5 || id == 7) {
            return string.concat(
                '<g fill="none" stroke="',
                id == 5 ? "#b98665" : "#f0ce7b",
                '" opacity=".65" stroke-width="7"><circle cx="160" cy="197" r="94"/><path d="M66 197h188m-94-94v188m-67-161 134 134m0-134L93 264"/></g>'
            );
        }
        if (id == 13) {
            return '<path d="M43 271q-7-24 19-27 5-31 39-17 21-20 43 2 27-25 47-3 35-14 43 13 36-5 38 23z" fill="#d1cce9"/><path d="M46 271q110 25 223-7" stroke="#eee6fa" stroke-width="5" fill="none"/>';
        }
        if (id == 15) {
            return '<path d="M27 153q75-122 139-38t127-17v43q-65 77-127-3T27 190z" fill="url(#aurora)" opacity=".65"/>';
        }
        return "";
    }

    function _palette(uint256 index) private pure returns (string memory fur, string memory ear) {
        if (index == 0) return ("#d9a16b", "#e7b3a1");
        if (index == 1) return ("#f2dcb1", "#e9b4b4");
        if (index == 2) return ("#b7b6c5", "#d6b4cb");
        if (index == 3) return ("#c78665", "#dea5a1");
        if (index == 4) return ("#947466", "#cf9f9f");
        return ("#b7a1ce", "#e0bad7");
    }

    function _paletteName(uint256 index) private pure returns (string memory) {
        if (index == 0) return "Caramel";
        if (index == 1) return "Cream";
        if (index == 2) return "Silver";
        if (index == 3) return "Cinnamon";
        if (index == 4) return "Cocoa";
        return "Lavender";
    }

    function _stageName(Stage value) private pure returns (string memory) {
        if (value == Stage.Pinky) return "Pinky";
        if (value == Stage.Fuzz) return "Fuzz";
        if (value == Stage.Runner) return "Runner";
        return "Elder";
    }

    function _moodName(PetView calldata data) private pure returns (string memory) {
        if (data.signalLost) return "Signal lost";
        if (data.mood == Mood.Napping) return "Napping";
        if (data.mood == Mood.Jogging) return "Jogging";
        return "Zoomies";
    }

    function _itemName(uint8 id) private pure returns (string memory name) {
        if (id == 0 || id > 17) return "None";
        (name,,,) = SqueekLoot.info(id);
    }

    function _trait(string memory name, string memory value) private pure returns (string memory) {
        return string.concat('{"trait_type":"', name, '","value":"', value, '"}');
    }
}
