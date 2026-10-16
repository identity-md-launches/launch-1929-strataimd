// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {Vm} from "./utils/Vm.sol";
import {StrataToken} from "../src/StrataToken.sol";
import {IERC20Errors} from "../src/interfaces/IERC20.sol";

/// @notice Unit tests for the StrataIMD token: metadata, the one-time mint, every ERC-20 path's
/// success and failure cases, fuzzed conservation of balances, and the absence of any admin surface.
contract StrataTokenTest is TestBase {
    // Declared locally (same signatures as the token's) so `emit` inside `expectEmit` blocks compiles
    // without depending on qualified event access.
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    StrataToken internal token;

    function setUp() public {
        vm.label(DEPLOYER, "deployer");
        vm.label(ALICE, "alice");
        vm.label(BOB, "bob");
        vm.label(CAROL, "carol");
        vm.prank(DEPLOYER);
        token = new StrataToken();
        vm.label(address(token), "STRATA");
    }

    // ---------------------------------------------------------------- metadata and the one-time mint

    function test_metadata() public view {
        assertEqString(token.name(), "StrataIMD", "name");
        assertEqString(token.symbol(), "STRATA", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
    }

    function test_constructorMintsTheWholeSupplyToTheDeployer() public view {
        assertEq(token.INITIAL_SUPPLY(), SUPPLY, "INITIAL_SUPPLY constant");
        assertEq(token.totalSupply(), SUPPLY, "total supply");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "deployer balance");
        assertEq(token.balanceOf(address(this)), 0, "the test contract received nothing");
        assertEq(token.balanceOf(address(0)), 0, "the zero address holds nothing");
    }

    function test_constructorEmitsASingleMintTransfer() public {
        vm.recordLogs();
        vm.prank(ALICE);
        StrataToken fresh = new StrataToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event in the constructor");
        assertEqAddress(logs[0].emitter, address(fresh), "emitted by the token");
        assertEq(logs[0].topics.length, 3, "Transfer has two indexed topics");
        assertEqBytes32(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"), "Transfer signature");
        assertEqBytes32(logs[0].topics[1], bytes32(0), "minted from the zero address");
        assertEqBytes32(logs[0].topics[2], bytes32(uint256(uint160(ALICE))), "minted to the deployer");
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY, "minted the whole supply");
        assertEq(fresh.balanceOf(ALICE), SUPPLY, "this deployer holds the whole supply");
        assertEq(fresh.balanceOf(DEPLOYER), 0, "a second token does not touch the first deployer");
    }

    function test_eachDeploymentHasItsOwnFixedSupply() public {
        StrataToken second = new StrataToken();
        assertEq(second.totalSupply(), SUPPLY, "second total supply");
        assertEq(second.balanceOf(address(this)), SUPPLY, "second deployer balance");
        assertEq(token.totalSupply(), SUPPLY, "first token unchanged");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "first deployer unchanged");
    }

    // ------------------------------------------------------------------------------------- transfer

    function test_transferMovesBalanceAndEmits() public {
        uint256 amount = 1_234 ether;
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(DEPLOYER, ALICE, amount);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount), "transfer returned false");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount, "sender balance");
        assertEq(token.balanceOf(ALICE), amount, "receiver balance");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transferWholeBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0, "sender emptied");
        assertEq(token.balanceOf(ALICE), SUPPLY, "receiver holds everything");
    }

    function test_transferZeroSucceedsAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0), "zero transfer returned false");
        assertEq(token.balanceOf(ALICE), 0, "alice still empty");
        assertEq(token.balanceOf(BOB), 0, "bob still empty");
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100);
        vm.prank(ALICE);
        token.transfer(ALICE, 60);
        assertEq(token.balanceOf(ALICE), 100, "self transfer leaves the balance alone");
    }

    function test_transferRevertsWhenBalanceIsInsufficient() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 100, 101));
        vm.prank(ALICE);
        token.transfer(BOB, 101);
        assertEq(token.balanceOf(ALICE), 100, "nothing moved");
        assertEq(token.balanceOf(BOB), 0, "nothing arrived");
    }

    function test_transferRevertsFromAnEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transfer(ALICE, 1);
    }

    function test_transferRevertsToTheZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "nothing left the deployer");
        assertEq(token.totalSupply(), SUPPLY, "nothing was burned");
    }

    // -------------------------------------------------------------------------------------- approve

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(ALICE, BOB, 500);
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 500), "approve returned false");
        assertEq(token.allowance(ALICE, BOB), 500, "allowance set");
        assertEq(token.allowance(BOB, ALICE), 0, "the reverse direction is untouched");
    }

    function test_approveOverwritesRatherThanAccumulates() public {
        vm.startPrank(ALICE);
        token.approve(BOB, 500);
        token.approve(BOB, 20);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, BOB), 20, "allowance replaced");
    }

    function test_approveDoesNotNeedABalance() public {
        vm.prank(CAROL);
        token.approve(BOB, SUPPLY * 2);
        assertEq(token.allowance(CAROL, BOB), SUPPLY * 2, "allowance may exceed any balance");
    }

    function test_approveRevertsForTheZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(ALICE);
        token.approve(address(0), 1);
    }

    // --------------------------------------------------------------------------------- transferFrom

    function test_transferFromSpendsAllowanceAndEmits() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1_000);
        vm.prank(ALICE);
        token.approve(BOB, 600);

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, CAROL, 400);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, 400), "transferFrom returned false");

        assertEq(token.balanceOf(ALICE), 600, "owner balance");
        assertEq(token.balanceOf(CAROL), 400, "receiver balance");
        assertEq(token.balanceOf(BOB), 0, "the spender holds nothing");
        assertEq(token.allowance(ALICE, BOB), 200, "allowance decreased");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transferFromDoesNotEmitApprovalWhenSpending() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1_000);
        vm.prank(ALICE);
        token.approve(BOB, 600);

        vm.recordLogs();
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 100);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "only the Transfer event");
        assertEqBytes32(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"), "it is a Transfer");
    }

    function test_transferFromWithUnlimitedAllowanceKeepsIt() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1_000);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 1_000);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max, "unlimited allowance untouched");
        assertEq(token.balanceOf(CAROL), 1_000, "receiver balance");
    }

    function test_transferFromExactAllowanceLeavesZero() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1_000);
        vm.prank(ALICE);
        token.approve(BOB, 1_000);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 1_000);
        assertEq(token.allowance(ALICE, BOB), 0, "allowance spent");
        assertEq(token.balanceOf(ALICE), 0, "owner emptied");
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1_000);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 1);
        assertEq(token.balanceOf(ALICE), 1_000, "nothing moved");
    }

    function test_transferFromRevertsBeyondAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1_000);
        vm.prank(ALICE);
        token.approve(BOB, 600);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 600, 601));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 601);
        assertEq(token.allowance(ALICE, BOB), 600, "allowance untouched after a revert");
    }

    function test_transferFromRevertsBeyondBalanceEvenWithAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100);
        vm.prank(ALICE);
        token.approve(BOB, 1_000);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 100, 101));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 101);
        assertEq(token.allowance(ALICE, BOB), 1_000, "allowance untouched after a revert");
    }

    function test_transferFromRevertsToTheZeroAddress() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100);
        vm.prank(ALICE);
        token.approve(BOB, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(ALICE, address(0), 1);
    }

    function test_transferFromByTheOwnerStillNeedsAnAllowance() public {
        // ERC-20 has no self-allowance shortcut: an owner spending through transferFrom approves itself.
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(ALICE, BOB, 1);
    }

    // ---------------------------------------------------------------------- no admin surface at all

    function test_noMintOrOwnershipCallIncreasesSupply() public {
        address attacker = address(0xBEEF);
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("a stranger reached ", signatures[i]));
            vm.prank(DEPLOYER);
            (ok,) = address(token).call(data);
            assertFalse(ok, string.concat("the deployer reached ", signatures[i]));
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
    }

    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY / 1_000);
        uint256 held = token.balanceOf(ALICE);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], ALICE, true));
            assertFalse(ok, string.concat("the deployer reached ", signatures[i]));
        }
        vm.prank(DEPLOYER);
        (bool moved,) = address(token).call(abi.encodeWithSelector(token.transferFrom.selector, ALICE, DEPLOYER, 1));
        assertFalse(moved, "the deployer pulled from a holder without an allowance");
        assertEq(token.balanceOf(ALICE), held, "the holder's balance is intact");
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, held / 2), "the holder can still transfer");
        assertEq(token.balanceOf(BOB), held / 2, "the transfer delivered in full");
    }

    function test_noOwnerAndNoEtherAccepted() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok, "the token has an owner()");
        (ok,) = address(token).call{value: 1 wei}("");
        assertFalse(ok, "the token accepted ether");
        (ok,) = address(token).call(abi.encodeWithSignature("burn(uint256)", 1));
        assertFalse(ok, "the token has a burn");
    }

    function test_runtimeCodeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0, "the token has no runtime code");
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
            assertTrue(op != 0xF2, "runtime code contains CALLCODE");
            assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
        }
    }

    // ------------------------------------------------------------------------------------------ fuzz

    function testFuzz_transferConservesBalances(address to, uint256 seed) public {
        vm.assume(to != address(0) && to != DEPLOYER);
        uint256 amount = bound(seed, 0, SUPPLY);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(to, amount), "transfer returned false");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount, "sender balance");
        assertEq(token.balanceOf(to), toBefore + amount, "receiver balance");
        assertEq(token.balanceOf(DEPLOYER) + token.balanceOf(to), SUPPLY, "balances sum to the supply");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 excess) public {
        held = bound(held, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - held);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, held + excess)
        );
        vm.prank(ALICE);
        token.transfer(BOB, held + excess);
        assertEq(token.balanceOf(ALICE), held, "nothing moved");
    }

    function testFuzz_transferFromSpendsExactlyWhatMoves(uint256 held, uint256 allowed, uint256 spent) public {
        held = bound(held, 0, SUPPLY);
        allowed = bound(allowed, 0, type(uint256).max - 1); // keep below the unlimited sentinel
        spent = bound(spent, 0, held);
        vm.assume(spent <= allowed);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.approve(BOB, allowed);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, spent), "transferFrom returned false");
        assertEq(token.balanceOf(ALICE), held - spent, "owner balance");
        assertEq(token.balanceOf(CAROL), spent, "receiver balance");
        assertEq(token.allowance(ALICE, BOB), allowed - spent, "allowance decreased by exactly the amount");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function testFuzz_transferFromAboveAllowanceReverts(uint256 allowed, uint256 excess) public {
        allowed = bound(allowed, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - allowed);
        vm.prank(DEPLOYER);
        token.approve(BOB, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, allowed, allowed + excess)
        );
        vm.prank(BOB);
        token.transferFrom(DEPLOYER, CAROL, allowed + excess);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "nothing moved");
        assertEq(token.allowance(DEPLOYER, BOB), allowed, "allowance untouched");
    }

    function testFuzz_approveSetsExactly(address spender, uint256 value) public {
        vm.assume(spender != address(0));
        vm.prank(ALICE);
        assertTrue(token.approve(spender, value), "approve returned false");
        assertEq(token.allowance(ALICE, spender), value, "allowance");
    }
}
