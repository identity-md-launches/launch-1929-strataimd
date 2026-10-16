// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {TestBase} from "./utils/TestBase.sol";
import {StrataToken} from "../src/StrataToken.sol";
import {IERC20Errors} from "../src/interfaces/IERC20.sol";

/// @notice Stands in for the IMD ProjectFactory: a contract deploys the token, so the constructor's
/// `msg.sender` is a contract, and it pays the supply out the way the launch does.
contract FactoryProbe {
    StrataToken public immutable token;

    constructor() {
        token = new StrataToken();
    }

    function move(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

/// @notice The launch flows the custom-token floor checks, run against a factory-like deployer:
/// the supply is minted whole to the deployer, the swarm's share arrives and is claimable whole,
/// the pool and remainder shares add up exactly, and nothing can grow the supply afterwards.
contract StrataTokenLaunchTest is TestBase {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 internal constant SWARM_BPS = 1_000;
    uint256 internal constant POOL_BPS = 8_000;
    uint256 internal constant BPS = 10_000;

    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant CLAIMANT = address(0xC1A1);
    address internal constant POOL = address(0x9001);
    address internal constant REMAINDER_TO = address(0x2E3);

    FactoryProbe internal factory;
    StrataToken internal token;

    function setUp() public {
        factory = new FactoryProbe();
        token = factory.token();
    }

    function test_contractDeployerReceivesTheWholeSupply() public view {
        assertEq(token.totalSupply(), SUPPLY, "manifest supply");
        assertEq(token.balanceOf(address(factory)), SUPPLY, "the factory holds the whole supply");
        assertEq(token.balanceOf(address(this)), 0, "the test contract holds nothing");
        assertEq(uint256(token.decimals()), 18, "decimals");
    }

    function test_theSwarmShareArrivesWholeAndIsClaimableWhole() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / BPS;
        assertTrue(factory.move(DISTRIBUTOR, swarm), "the transfer to the distributor returned false");
        assertEq(token.balanceOf(DISTRIBUTOR), swarm, "the swarm's share arrived short");
        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(CLAIMANT, swarm), "the claim transfer returned false");
        assertEq(token.balanceOf(CLAIMANT), swarm, "a claim arrived short");
        assertEq(token.balanceOf(DISTRIBUTOR), 0, "the distributor kept something back");
        assertEq(token.totalSupply(), SUPPLY, "the launch flows changed the supply");
    }

    function test_launchSharesAddUpExactly() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / BPS;
        uint256 pool = (SUPPLY * POOL_BPS) / BPS;
        uint256 remainder = SUPPLY - swarm - pool;
        assertTrue(factory.move(DISTRIBUTOR, swarm), "swarm transfer");
        assertTrue(factory.move(POOL, pool), "pool transfer");
        assertTrue(factory.move(REMAINDER_TO, remainder), "remainder transfer");
        assertEq(token.balanceOf(DISTRIBUTOR), swarm, "swarm share");
        assertEq(token.balanceOf(POOL), pool, "pool share");
        assertEq(token.balanceOf(REMAINDER_TO), remainder, "remainder share");
        assertEq(token.balanceOf(address(factory)), 0, "the factory paid everything out");
        assertEq(swarm + pool + remainder, SUPPLY, "the shares are the supply");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_theFactoryCannotPayOutMoreThanTheSupply() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(factory), SUPPLY, SUPPLY + 1)
        );
        factory.move(POOL, SUPPLY + 1);
        assertEq(token.balanceOf(address(factory)), SUPPLY, "nothing moved");
    }

    function test_theFactoryHasNoPowerOverHoldersAfterPayout() public {
        uint256 held = SUPPLY / 1_000;
        factory.move(CLAIMANT, held);
        // The factory, the most plausibly trusted address, cannot pull tokens back.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        vm.prank(address(factory));
        token.transferFrom(CLAIMANT, address(factory), 1);
        assertEq(token.balanceOf(CLAIMANT), held, "the holder's balance is intact");
        // And it cannot mint more to itself or anyone.
        vm.prank(address(factory));
        (bool ok,) = address(token).call(abi.encodeWithSignature("mint(address,uint256)", address(factory), 1));
        assertFalse(ok, "the factory reached a mint");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function testFuzz_anySplitOfTheSupplyIsExact(uint256 swarmBps, uint256 poolBps) public {
        swarmBps = bound(swarmBps, 0, BPS);
        poolBps = bound(poolBps, 0, BPS - swarmBps);
        uint256 swarm = (SUPPLY * swarmBps) / BPS;
        uint256 pool = (SUPPLY * poolBps) / BPS;
        uint256 remainder = SUPPLY - swarm - pool;
        factory.move(DISTRIBUTOR, swarm);
        factory.move(POOL, pool);
        factory.move(REMAINDER_TO, remainder);
        assertEq(token.balanceOf(DISTRIBUTOR), swarm, "swarm share");
        assertEq(token.balanceOf(POOL), pool, "pool share");
        assertEq(token.balanceOf(REMAINDER_TO), remainder, "remainder share");
        assertEq(token.balanceOf(address(factory)), 0, "the factory paid everything out");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }
}
