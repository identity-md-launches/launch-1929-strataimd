// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {StrataToken} from "../src/StrataToken.sol";
import {IERC20Errors} from "../src/interfaces/IERC20.sol";

/// @notice Drives the token with random, bounded call sequences from a small cast of actors and keeps a
/// ghost ledger of what every balance and allowance must be. Every expected revert is caught and checked
/// here, so a revert that escapes this handler is itself a failure (`fail_on_revert` is on).
contract StrataTokenHandler is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 internal constant UNLIMITED = type(uint256).max;

    StrataToken public immutable token;

    /// @dev Every address that may ever hold a balance: the deployer, the actors and the token itself
    /// (tokens sent there are stuck but still part of the supply).
    address[] public accounts;
    address[] public actors;

    /// @dev What the ledger says each account should hold and each pair should be allowed.
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    /// @dev Cumulative flow through transfer and transferFrom, for the "nobody moves more than held" check.
    mapping(address => uint256) public ghostIn;
    mapping(address => uint256) public ghostOut;
    mapping(address => uint256) public ghostInitial;

    uint256 public ghostTransfers;
    uint256 public ghostTransferFroms;
    uint256 public ghostApprovals;
    uint256 public ghostRejectedTransfers;
    uint256 public ghostRejectedTransferFroms;
    uint256 public ghostRejectedZeroReceivers;
    uint256 public ghostRejectedAdminCalls;

    constructor(address deployer) {
        vm.prank(deployer);
        token = new StrataToken();

        actors.push(deployer);
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA201));
        actors.push(address(0xDA7E));
        actors.push(address(0xE4E));
        for (uint256 i = 0; i < actors.length; i++) {
            accounts.push(actors[i]);
        }
        accounts.push(address(token));

        ghostBalance[deployer] = SUPPLY;
        ghostInitial[deployer] = SUPPLY;
    }

    function accountCount() external view returns (uint256) {
        return accounts.length;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // ------------------------------------------------------------------------------- happy-path drivers

    /// @notice An actor sends part (possibly none, possibly all) of its balance to any account.
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _account(toSeed);
        uint256 amount = bound(amountSeed, 0, token.balanceOf(from));

        vm.prank(from);
        bool ok = token.transfer(to, amount);
        assertTrue(ok, "handler: transfer returned false");

        _moved(from, to, amount);
        ghostTransfers++;
    }

    /// @notice An actor sets an allowance for another actor. One value in sixteen is the unlimited sentinel.
    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = amountSeed % 16 == 0 ? UNLIMITED : bound(amountSeed, 0, SUPPLY * 2);

        vm.prank(owner);
        bool ok = token.approve(spender, amount);
        assertTrue(ok, "handler: approve returned false");

        ghostAllowance[owner][spender] = amount;
        ghostApprovals++;
    }

    /// @notice A spender moves what it is allowed, and what the owner has, to any account.
    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 amountSeed) external {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _account(toSeed);
        uint256 allowed = token.allowance(owner, spender);
        uint256 cap = token.balanceOf(owner);
        if (allowed < cap) cap = allowed;
        uint256 amount = bound(amountSeed, 0, cap);

        vm.prank(spender);
        bool ok = token.transferFrom(owner, to, amount);
        assertTrue(ok, "handler: transferFrom returned false");

        _moved(owner, to, amount);
        if (allowed != UNLIMITED) ghostAllowance[owner][spender] = allowed - amount;
        ghostTransferFroms++;
    }

    // ----------------------------------------------------------------------------- failure-path drivers

    /// @notice An actor tries to send more than it holds: it must revert with the exact ERC-6093 error
    /// and leave every balance alone.
    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 excessSeed) external {
        address from = _actor(fromSeed);
        address to = _account(toSeed);
        uint256 held = token.balanceOf(from);
        uint256 excess = bound(excessSeed, 1, SUPPLY);
        uint256 asked = held + excess;

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, asked));
        vm.prank(from);
        token.transfer(to, asked);

        assertEq(token.balanceOf(from), held, "handler: a rejected transfer changed the sender");
        ghostRejectedTransfers++;
    }

    /// @notice A spender tries to pull more than its allowance (or, when unlimited, more than the owner
    /// holds): it must revert with the exact error and change nothing, including the allowance.
    function transferFromAboveLimit(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, uint256 excessSeed)
        external
    {
        address spender = _actor(spenderSeed);
        address owner = _actor(ownerSeed);
        address to = _account(toSeed);
        uint256 allowed = token.allowance(owner, spender);
        uint256 held = token.balanceOf(owner);
        uint256 excess = bound(excessSeed, 1, SUPPLY);

        uint256 asked;
        if (allowed == UNLIMITED) {
            asked = held + excess;
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, asked));
        } else if (allowed < held) {
            asked = allowed + excess;
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, asked)
            );
        } else {
            // allowed >= held and finite: the allowance check passes only up to `allowed`, so ask for
            // something above the balance but within the allowance when there is room, else above both.
            asked = held + excess;
            if (asked <= allowed) {
                vm.expectRevert(
                    abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, asked)
                );
            } else {
                vm.expectRevert(
                    abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, asked)
                );
            }
        }
        vm.prank(spender);
        token.transferFrom(owner, to, asked);

        assertEq(token.balanceOf(owner), held, "handler: a rejected transferFrom changed the owner");
        assertEq(token.allowance(owner, spender), allowed, "handler: a rejected transferFrom spent allowance");
        ghostRejectedTransferFroms++;
    }

    /// @notice Sending to the zero address is never a burn: it reverts and the supply stays whole.
    function transferToZero(uint256 fromSeed, uint256 amountSeed, bool viaTransferFrom) external {
        address from = _actor(fromSeed);
        uint256 amount = bound(amountSeed, 0, token.balanceOf(from));
        if (viaTransferFrom) {
            vm.prank(from);
            token.approve(from, amount);
            ghostAllowance[from][from] = amount;
            ghostApprovals++;
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(from);
            token.transferFrom(from, address(0), amount);
            assertEq(token.allowance(from, from), amount, "handler: a rejected burn spent allowance");
        } else {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(from);
            token.transfer(address(0), amount);
        }
        ghostRejectedZeroReceivers++;
    }

    /// @notice Any actor, including the deployer, tries a privileged selector: none exists, so every one
    /// reverts and nothing changes.
    function adminCall(uint256 callerSeed, uint256 targetSeed, uint256 selectorSeed, uint256 amountSeed) external {
        address caller = _actor(callerSeed);
        address target = _actor(targetSeed);
        string[12] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "freeze(address)",
            "seize(address)",
            "transferOwnership(address)",
            "setMinter(address)",
            "upgradeTo(address)"
        ];
        string memory signature = signatures[selectorSeed % signatures.length];
        uint256 supplyBefore = token.totalSupply();
        uint256 heldBefore = token.balanceOf(target);

        vm.prank(caller);
        (bool ok,) = address(token).call(abi.encodeWithSignature(signature, target, amountSeed));
        assertFalse(ok, string.concat("handler: reached ", signature));

        assertEq(token.totalSupply(), supplyBefore, "handler: an admin call changed the supply");
        assertEq(token.balanceOf(target), heldBefore, "handler: an admin call moved a balance");
        ghostRejectedAdminCalls++;
    }

    // ---------------------------------------------------------------------------------------- internals

    function _moved(address from, address to, uint256 amount) private {
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostOut[from] += amount;
        ghostIn[to] += amount;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _account(uint256 seed) private view returns (address) {
        return accounts[seed % accounts.length];
    }
}

/// @notice Invariants that must hold after every random call sequence the handler drives.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract StrataTokenInvariantTest is TestBase {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant DEPLOYER = address(0xFAC7);

    StrataTokenHandler internal handler;
    StrataToken internal token;

    function setUp() public {
        handler = new StrataTokenHandler(DEPLOYER);
        token = handler.token();
    }

    /// @dev Forge reads these to decide what the invariant runner may call: only the handler.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.transferAboveBalance.selector;
        selectors[4] = handler.transferFromAboveLimit.selector;
        selectors[5] = handler.transferToZero.selector;
        selectors[6] = handler.adminCall.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    /// @dev The supply is fixed at deployment: no sequence of calls grows or shrinks it.
    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), SUPPLY, "total supply drifted");
        assertEq(token.INITIAL_SUPPLY(), SUPPLY, "INITIAL_SUPPLY changed");
    }

    /// @dev Conservation: everything the token says it holds, across every account that can hold
    /// anything, is exactly the supply. Nothing leaks to or from unknown addresses.
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        uint256 n = handler.accountCount();
        for (uint256 i = 0; i < n; i++) {
            sum += token.balanceOf(handler.accounts(i));
        }
        assertEq(sum, SUPPLY, "balances do not sum to the supply");
    }

    /// @dev Each account holds exactly what the ghost ledger says, and never more than the supply.
    function invariant_balancesMatchTheLedger() public view {
        uint256 n = handler.accountCount();
        for (uint256 i = 0; i < n; i++) {
            address account = handler.accounts(i);
            uint256 held = token.balanceOf(account);
            assertEq(held, handler.ghostBalance(account), "a balance disagrees with the ledger");
            assertLe(held, SUPPLY, "a balance exceeds the supply");
            assertEq(
                handler.ghostInitial(account) + handler.ghostIn(account),
                held + handler.ghostOut(account),
                "flow accounting is broken"
            );
            assertLe(
                handler.ghostOut(account),
                handler.ghostInitial(account) + handler.ghostIn(account),
                "an account sent more than it ever received"
            );
        }
    }

    /// @dev Allowances are exactly what was approved minus what was spent, and the unlimited sentinel
    /// is never decreased.
    function invariant_allowancesMatchTheLedger() public view {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            address owner = handler.actors(i);
            for (uint256 j = 0; j < n; j++) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.ghostAllowance(owner, spender),
                    "an allowance disagrees with the ledger"
                );
            }
        }
    }

    /// @dev The zero address never holds anything: there is no burn and no mint after the constructor.
    function invariant_zeroAddressHoldsNothing() public view {
        assertEq(token.balanceOf(address(0)), 0, "the zero address holds tokens");
        assertEq(token.balanceOf(address(this)), 0, "the test contract holds tokens");
        assertEq(token.balanceOf(address(handler)), 0, "the handler holds tokens");
    }

    /// @dev Metadata is constant.
    function invariant_metadataIsConstant() public view {
        assertEqString(token.name(), "StrataIMD", "name");
        assertEqString(token.symbol(), "STRATA", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
    }

    /// @dev Whatever the sequence, a holder can still move what it holds: no call froze anyone.
    function invariant_everyHolderCanStillTransfer() public {
        uint256 n = handler.actorCount();
        for (uint256 i = 0; i < n; i++) {
            address actor = handler.actors(i);
            uint256 held = token.balanceOf(actor);
            address peer = handler.actors((i + 1) % n);
            uint256 peerHeld = token.balanceOf(peer);
            vm.prank(actor);
            assertTrue(token.transfer(peer, held), "a holder can no longer transfer");
            assertEq(token.balanceOf(peer), peerHeld + held, "the transfer arrived short");
            assertEq(token.balanceOf(actor), 0, "the transfer did not leave");
            // Undo so the ledger still matches for the invariants that run after this one.
            vm.prank(peer);
            assertTrue(token.transfer(actor, held), "the peer can no longer transfer");
            assertEq(token.balanceOf(actor), held, "the return trip arrived short");
        }
    }
}
