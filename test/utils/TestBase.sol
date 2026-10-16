// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "./Vm.sol";

/// @title TestBase
/// @notice A minimal forge-compatible test base: the cheatcode handle and assertions that revert
/// with a readable message. Forge marks a test failed when it reverts, so a failed assertion here
/// fails the test exactly as forge-std's would.
abstract contract TestBase {
    /// @dev Forge's cheatcode address, derived the same way forge-std derives it.
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertTrue(bool condition, string memory err) internal pure {
        if (!condition) revert(err);
    }

    function assertFalse(bool condition, string memory err) internal pure {
        if (condition) revert(err);
    }

    function assertEq(uint256 a, uint256 b, string memory err) internal pure {
        if (a != b) revert(string.concat(err, " [", _toString(a), " != ", _toString(b), "]"));
    }

    function assertEqAddress(address a, address b, string memory err) internal pure {
        if (a != b) revert(err);
    }

    function assertEqBytes32(bytes32 a, bytes32 b, string memory err) internal pure {
        if (a != b) revert(err);
    }

    function assertEqString(string memory a, string memory b, string memory err) internal pure {
        if (keccak256(bytes(a)) != keccak256(bytes(b))) revert(string.concat(err, " [", a, " != ", b, "]"));
    }

    function assertLe(uint256 a, uint256 b, string memory err) internal pure {
        if (a > b) revert(string.concat(err, " [", _toString(a), " > ", _toString(b), "]"));
    }

    function assertGt(uint256 a, uint256 b, string memory err) internal pure {
        if (a <= b) revert(string.concat(err, " [", _toString(a), " <= ", _toString(b), "]"));
    }

    /// @dev Maps a fuzzed value into `[min, max]`. `max - min` must be below `type(uint256).max`.
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (min >= max) return min;
        return min + (x % (max - min + 1));
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 length;
        for (uint256 rest = value; rest != 0; rest /= 10) {
            ++length;
        }
        bytes memory buffer = new bytes(length);
        for (uint256 rest = value; rest != 0; rest /= 10) {
            --length;
            buffer[length] = bytes1(uint8(48 + rest % 10));
        }
        return string(buffer);
    }
}
