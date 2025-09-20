// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./IRebaseToken.sol";

contract Vault {
    error Vault_Transation_Failed();

    IRebaseToken private i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(IRebaseToken rebaseToken) {
        i_rebaseToken = rebaseToken;
    }

    receive() external payable {}

    function deposit() external payable {
        uint256 userInterestRate = i_rebaseToken.getUserInterestRate(msg.sender);
        i_rebaseToken.mint(msg.sender, msg.value, userInterestRate);
        emit Deposit(msg.sender, msg.value);
    }

    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) revert Vault_Transation_Failed();
        emit Redeem(msg.sender, _amount);
    }

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
