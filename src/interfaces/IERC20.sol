// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title IERC20
/// @notice The ERC-20 interface (EIP-20) including the optional metadata extension.
interface IERC20 {
    /// @notice Emitted when `value` tokens move from `from` to `to`.
    /// @dev `from` is the zero address for the one-time mint in the constructor.
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when `owner` sets the allowance of `spender` to `value`.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/// @title IERC20Errors
/// @notice The standard ERC-20 custom errors (ERC-6093).
interface IERC20Errors {
    /// @dev `sender` holds `balance` but the transfer needs `needed`.
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    /// @dev Tokens cannot leave the zero address.
    error ERC20InvalidSender(address sender);
    /// @dev Tokens cannot be sent to the zero address.
    error ERC20InvalidReceiver(address receiver);
    /// @dev `spender` was allowed `allowance` but the transfer needs `needed`.
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    /// @dev The zero address cannot grant an allowance.
    error ERC20InvalidApprover(address approver);
    /// @dev The zero address cannot be granted an allowance.
    error ERC20InvalidSpender(address spender);
}
