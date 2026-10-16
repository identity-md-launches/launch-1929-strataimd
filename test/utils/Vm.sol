// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Vm
/// @notice The subset of Foundry's cheatcode interface these tests use, declared here so the
/// project needs no vendored library. Every signature matches forge's cheatcode ABI exactly:
/// forge dispatches on the selector of the call made to the cheatcode address.
interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    /// @notice Sets `msg.sender` for the next call only.
    function prank(address msgSender) external;

    /// @notice Sets `msg.sender` for every call until `stopPrank`.
    function startPrank(address msgSender) external;

    function stopPrank() external;

    /// @notice The next call must revert, with any data.
    function expectRevert() external;

    /// @notice The next call must revert with exactly this selector.
    function expectRevert(bytes4 revertData) external;

    /// @notice The next call must revert with exactly this data.
    function expectRevert(bytes calldata revertData) external;

    /// @notice The next call must emit the event emitted right after this one, matching the checked parts.
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;

    /// @notice As above, and the event must come from `emitter`.
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData, address emitter) external;

    /// @notice Discards the fuzz input when `condition` is false.
    function assume(bool condition) external pure;

    function label(address account, string calldata newLabel) external;

    function recordLogs() external;

    function getRecordedLogs() external returns (Log[] memory logs);
}
