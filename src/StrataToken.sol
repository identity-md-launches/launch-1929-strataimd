// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20, IERC20Errors} from "./interfaces/IERC20.sol";

/// @title StrataIMD (STRATA)
/// @notice A plain, fixed-supply ERC-20. The whole supply of 1,000,000,000 STRATA (18 decimals) is
/// minted once, in the constructor, to the deployer. There is no owner, no minter, no pause,
/// no blocklist, no fee and no burn: the supply can never grow and nobody but a holder can move
/// a holder's balance.
/// @dev The Solidity name `StrataToken` is the launch's record name (at most 32 characters); the
/// token's own name and symbol are what `name()` and `symbol()` return. The contract is
/// self-contained: it follows the ERC-20 semantics and ERC-6093 errors of OpenZeppelin's ERC20 v5
/// without importing a library, so it has no external or linked code.
contract StrataToken is IERC20, IERC20Errors {
    /// @dev The token name returned by `name()`.
    string private constant TOKEN_NAME = "StrataIMD";

    /// @dev The token symbol returned by `symbol()`.
    string private constant TOKEN_SYMBOL = "STRATA";

    /// @dev The number of decimals returned by `decimals()`.
    uint8 private constant TOKEN_DECIMALS = 18;

    /// @notice The whole supply, minted once in the constructor: 1,000,000,000 tokens in minor
    /// units (18 decimals), 1_000_000_000_000_000_000_000_000_000.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    uint256 private immutable _totalSupply;

    mapping(address account => uint256 balance) private _balances;

    mapping(address owner => mapping(address spender => uint256 value)) private _allowances;

    /// @notice Mints the whole supply to the deployer. The IMD factory deploys the token, so the
    /// factory receives the supply and pays it out as the launch directs.
    constructor() {
        _totalSupply = INITIAL_SUPPLY;
        _balances[msg.sender] = INITIAL_SUPPLY;
        emit Transfer(address(0), msg.sender, INITIAL_SUPPLY);
    }

    /// @inheritdoc IERC20
    function name() external pure returns (string memory) {
        return TOKEN_NAME;
    }

    /// @inheritdoc IERC20
    function symbol() external pure returns (string memory) {
        return TOKEN_SYMBOL;
    }

    /// @inheritdoc IERC20
    function decimals() external pure returns (uint8) {
        return TOKEN_DECIMALS;
    }

    /// @inheritdoc IERC20
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @inheritdoc IERC20
    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @inheritdoc IERC20
    /// @dev Reverts with `ERC20InvalidReceiver` for the zero address and `ERC20InsufficientBalance`
    /// when the caller holds less than `value`.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @inheritdoc IERC20
    /// @dev Sets the allowance outright. Reverts with `ERC20InvalidSpender` for the zero address.
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value, true);
        return true;
    }

    /// @inheritdoc IERC20
    /// @dev Spends the caller's allowance from `from` first, so an unapproved caller reverts with
    /// `ERC20InsufficientAllowance` before any balance is read. An allowance of `type(uint256).max`
    /// is treated as unlimited and is not decreased.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) revert ERC20InsufficientBalance(from, fromBalance, value);
        unchecked {
            // The sum of all balances is the fixed total supply, so neither side can overflow.
            _balances[from] = fromBalance - value;
            _balances[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent) private {
        if (owner == address(0)) revert ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        _allowances[owner][spender] = value;
        if (emitEvent) emit Approval(owner, spender, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) private {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}
