// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {Vm} from "./utils/Vm.sol";
import {StrataToken} from "../src/StrataToken.sol";
import {IERC20Errors} from "../src/interfaces/IERC20.sol";

/// @notice Edge inputs the author may not have considered: the zero address as a caller, the sentinel
/// allowance one below unlimited, the maximum value, self-approval, the token itself as a receiver,
/// unknown selectors, and sequences of the same call twice.
/// forge-config: default.fuzz.runs = 1000
contract StrataTokenEdgesTest is TestBase {
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 internal constant UNLIMITED = type(uint256).max;

    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    StrataToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new StrataToken();
    }

    // ------------------------------------------------------------------- the zero address as a caller

    function test_zeroAddressCannotSendEvenNothing() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(ALICE, 0);
    }

    function test_zeroAddressCannotApprove() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(BOB, 1);
        assertEq(token.allowance(address(0), BOB), 0, "the zero address granted an allowance");
    }

    function test_zeroAddressCannotApproveItself() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(address(0), 1);
    }

    function test_nobodyCanPullFromTheZeroAddress() public {
        // No allowance can ever be granted by the zero address, so the allowance check fails first.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(0), BOB, 1);
    }

    function test_zeroValuePullFromTheZeroAddressStillReverts() public {
        // A zero value passes the allowance comparison (0 >= 0), so the spend writes the allowance back
        // through `_approve`, which rejects the zero address as an approver before `_transfer` would
        // reject it as a sender. Either way nothing can be pulled from the zero address.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(BOB);
        token.transferFrom(address(0), BOB, 0);
    }

    function test_zeroAddressAsBothEndsReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(address(0), 0);
    }

    // ------------------------------------------------------------------- allowance sentinel boundaries

    function test_allowanceOneBelowUnlimitedIsFinite() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, UNLIMITED - 1);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 3);
        assertEq(token.allowance(ALICE, BOB), UNLIMITED - 4, "the near-max allowance was not decreased");
    }

    function test_unlimitedAllowanceSurvivesRepeatedSpends() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, UNLIMITED);
        vm.startPrank(BOB);
        token.transferFrom(ALICE, CAROL, 4);
        token.transferFrom(ALICE, CAROL, 6);
        vm.stopPrank();
        assertEq(token.allowance(ALICE, BOB), UNLIMITED, "the unlimited allowance was decreased");
        assertEq(token.balanceOf(ALICE), 0, "the owner was not emptied");
        assertEq(token.balanceOf(CAROL), 10, "the receiver did not get both spends");
    }

    function test_unlimitedAllowanceDoesNotBypassTheBalanceCheck() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, UNLIMITED);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10, 11));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 11);
    }

    function test_unlimitedAllowanceEmitsNoApprovalOnSpend() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, UNLIMITED);
        vm.recordLogs();
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "only a Transfer should be emitted");
        assertEqBytes32(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"), "not a Transfer");
    }

    function test_spentAllowanceCannotBeSpentAgain() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, 5);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 5);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 1);
    }

    function test_zeroValueTransferFromNeedsNoAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, 0), "zero-value transferFrom returned false");
        assertEq(token.balanceOf(ALICE), 10, "the owner lost something");
        assertEq(token.allowance(ALICE, BOB), 0, "an allowance appeared");
    }

    function test_reapprovingAfterAPartialSpendResetsOutright() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, 8);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 3);
        assertEq(token.allowance(ALICE, BOB), 5, "allowance after the spend");
        vm.prank(ALICE);
        token.approve(BOB, 8);
        assertEq(token.allowance(ALICE, BOB), 8, "re-approval did not reset");
        vm.prank(ALICE);
        token.approve(BOB, 0);
        assertEq(token.allowance(ALICE, BOB), 0, "approving zero did not revoke");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 1);
    }

    function test_approveZeroEmitsApproval() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(ALICE, BOB, 0);
        vm.prank(ALICE);
        token.approve(BOB, 0);
    }

    function test_selfApprovalLetsAnOwnerPullFromItself() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.startPrank(ALICE);
        token.approve(ALICE, 4);
        assertTrue(token.transferFrom(ALICE, BOB, 4), "self transferFrom returned false");
        vm.stopPrank();
        assertEq(token.balanceOf(ALICE), 6, "owner balance");
        assertEq(token.balanceOf(BOB), 4, "receiver balance");
        assertEq(token.allowance(ALICE, ALICE), 0, "self allowance spent");
    }

    function test_transferFromBackToTheOwnerSpendsAllowanceWithoutMovingBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, 7);
        vm.prank(BOB);
        token.transferFrom(ALICE, ALICE, 7);
        assertEq(token.balanceOf(ALICE), 10, "a self-directed transferFrom changed the balance");
        assertEq(token.allowance(ALICE, BOB), 0, "the allowance was not spent");
    }

    // ------------------------------------------------------------------------ the maximum as a value

    function test_transferOfMaxValueRevertsWithExactError() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, UNLIMITED)
        );
        vm.prank(DEPLOYER);
        token.transfer(ALICE, UNLIMITED);
    }

    function test_transferFromOfMaxValueWithUnlimitedAllowanceReverts() public {
        vm.prank(DEPLOYER);
        token.approve(BOB, UNLIMITED);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, SUPPLY, UNLIMITED)
        );
        vm.prank(BOB);
        token.transferFrom(DEPLOYER, ALICE, UNLIMITED);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY, "nothing moved");
    }

    function test_balanceCannotBeDoubledByReceivingTheSupplyTwice() public {
        // The receiver side is unchecked arithmetic; the balance check on the sender side bounds it.
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1);
        assertEq(token.balanceOf(ALICE), SUPPLY, "the receiver exceeds the supply");
    }

    // ------------------------------------------------------------ the token itself and unknown input

    function test_tokensSentToTheTokenContractStayThere() public {
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(address(token), 5), "transfer to the token returned false");
        assertEq(token.balanceOf(address(token)), 5, "the token does not hold what was sent");
        assertEq(token.totalSupply(), SUPPLY, "the supply changed");
        // Nothing can move them back: the token never calls transfer on itself and has no rescue path.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 5));
        vm.prank(DEPLOYER);
        token.transferFrom(address(token), DEPLOYER, 5);
        (bool ok,) = address(token).call(abi.encodeWithSignature("rescue(address,uint256)", DEPLOYER, 5));
        assertFalse(ok, "the token has a rescue path");
    }

    function test_unknownSelectorAndEmptyCalldataRevert() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("doesNotExist()"));
        assertFalse(ok, "an unknown selector was answered");
        (ok,) = address(token).call("");
        assertFalse(ok, "empty calldata was answered");
        (ok,) = address(token).call(hex"a9059cbb");
        assertFalse(ok, "a truncated transfer call was answered");
    }

    function test_viewFunctionsAnswerThroughStaticcall() public view {
        (bool ok, bytes memory data) = address(token).staticcall(abi.encodeWithSignature("totalSupply()"));
        assertTrue(ok, "totalSupply is not view");
        assertEq(abi.decode(data, (uint256)), SUPPLY, "totalSupply value");
        (ok, data) = address(token).staticcall(abi.encodeWithSignature("name()"));
        assertTrue(ok, "name is not view");
        assertEqString(abi.decode(data, (string)), "StrataIMD", "name value");
        (ok, data) = address(token).staticcall(abi.encodeWithSignature("decimals()"));
        assertTrue(ok, "decimals is not view");
        assertEq(abi.decode(data, (uint256)), 18, "decimals value");
    }

    function test_transferRejectsValueWithEther() public {
        // The test contract is funded by forge; the token's functions are not payable.
        assertGt(address(this).balance, 0, "the test contract has no ether to send");
        (bool ok,) = address(token).call{value: 1 wei}(abi.encodeWithSelector(token.transfer.selector, ALICE, 0));
        assertFalse(ok, "a payable transfer was accepted");
        (ok,) = address(token).call{value: 1 wei}(abi.encodeWithSelector(token.approve.selector, ALICE, 0));
        assertFalse(ok, "a payable approve was accepted");
        assertEq(address(token).balance, 0, "the token holds ether");
    }

    // ------------------------------------------------------------------------------------- fuzz

    function testFuzz_chainedTransfersConserveTheSupply(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, a);
        c = bound(c, 0, b);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, a);
        vm.prank(ALICE);
        token.transfer(BOB, b);
        vm.prank(BOB);
        token.transfer(CAROL, c);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - a, "deployer");
        assertEq(token.balanceOf(ALICE), a - b, "alice");
        assertEq(token.balanceOf(BOB), b - c, "bob");
        assertEq(token.balanceOf(CAROL), c, "carol");
        assertEq(
            token.balanceOf(DEPLOYER) + token.balanceOf(ALICE) + token.balanceOf(BOB) + token.balanceOf(CAROL),
            SUPPLY,
            "conservation"
        );
    }

    function testFuzz_finiteAllowanceDecreasesByExactlyWhatMoves(uint256 allowed, uint256 first, uint256 second)
        public
    {
        allowed = bound(allowed, 0, UNLIMITED - 1);
        uint256 cap = allowed < SUPPLY ? allowed : SUPPLY;
        first = bound(first, 0, cap);
        second = bound(second, 0, cap - first);
        vm.prank(DEPLOYER);
        token.approve(BOB, allowed);
        vm.startPrank(BOB);
        token.transferFrom(DEPLOYER, ALICE, first);
        token.transferFrom(DEPLOYER, CAROL, second);
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, BOB), allowed - first - second, "allowance");
        assertEq(token.balanceOf(ALICE) + token.balanceOf(CAROL), first + second, "moved");
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - first - second, "remaining");
    }

    function testFuzz_transferFromRevertsWhenBalanceIsTheBindingLimit(uint256 held, uint256 allowed, uint256 excess)
        public
    {
        held = bound(held, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - held);
        uint256 asked = held + excess;
        allowed = bound(allowed, asked, UNLIMITED);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.approve(BOB, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, asked));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, asked);
        assertEq(token.allowance(ALICE, BOB), allowed, "allowance untouched after a revert");
        assertEq(token.balanceOf(ALICE), held, "nothing moved");
    }

    function testFuzz_approveAnyPairAnyValueIsExact(address owner, address spender, uint256 value) public {
        // Both ends are pinned away from the zero address with bound, not assume, so no run is discarded.
        owner = address(uint160(bound(uint256(uint160(owner)), 1, type(uint160).max)));
        spender = address(uint160(bound(uint256(uint160(spender)), 1, type(uint160).max)));
        vm.prank(owner);
        assertTrue(token.approve(spender, value), "approve returned false");
        assertEq(token.allowance(owner, spender), value, "allowance");
        if (owner != spender) assertEq(token.allowance(spender, owner), 0, "the reverse direction changed");
    }

    function testFuzz_transferToAnyNonZeroAddressDeliversExactly(address to, uint256 amount) public {
        to = address(uint160(bound(uint256(uint160(to)), 1, type(uint160).max)));
        amount = bound(amount, 0, SUPPLY);
        uint256 before = token.balanceOf(to);
        vm.prank(DEPLOYER);
        token.transfer(to, amount);
        if (to == DEPLOYER) {
            assertEq(token.balanceOf(to), SUPPLY, "a self transfer changed the balance");
        } else {
            assertEq(token.balanceOf(to), before + amount, "delivered short or long");
            assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount, "sender");
        }
    }
}
