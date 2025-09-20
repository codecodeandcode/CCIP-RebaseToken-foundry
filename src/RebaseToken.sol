// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken_CanOnlyBeSetBelow();

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_InterestRate = (5 * PRECISION_FACTOR) / 1e8;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimeStamp;

    event InterestRateSet(uint256 newInterestRate);

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    function setInterestRate(uint256 newInterestRate) external onlyOwner {
        if (newInterestRate >= s_InterestRate) revert RebaseToken_CanOnlyBeSetBelow();
        s_InterestRate = newInterestRate;
        emit InterestRateSet(newInterestRate);
    }

    function mint(address _to, uint256 amount, uint256 userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        userInterestRate = s_InterestRate;
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = userInterestRate;
        _mint(_to, amount);
    }

    function burn(address _from, uint256 amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, amount);
    }

    function balanceOf(address _user) public view override returns (uint256) {
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdated(_user)) / PRECISION_FACTOR;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        _mintAccruedInterest(to);
        _mintAccruedInterest(msg.sender);
        if (value == type(uint256).max) {
            value = balanceOf(msg.sender);
        }
        if (s_userInterestRate[to] == 0) {
            s_userInterestRate[to] = s_userInterestRate[msg.sender];
        }
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        _mintAccruedInterest(to);
        _mintAccruedInterest(from);
        if (value == type(uint256).max) {
            value = balanceOf(from);
        }
        if (s_userInterestRate[to] == 0) {
            s_userInterestRate[to] = s_userInterestRate[from];
        }
        return super.transferFrom(from, to, value);
    }

    function _calculateUserAccumulatedInterestSinceLastUpdated(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimeStamp[_user];
        linearInterest = PRECISION_FACTOR + (timeElapsed * s_userInterestRate[_user]);
    }

    function _mintAccruedInterest(address _to) internal {
        uint256 previousPrincipleBalance = super.balanceOf(_to);
        uint256 currenBalance = balanceOf(_to);
        uint256 increaseBalance = currenBalance - previousPrincipleBalance;
        s_userLastUpdatedTimeStamp[_to] = block.timestamp;
        _mint(_to, increaseBalance);
    }

    function getUserInterestRate(address user) external view returns (uint256) {
        return s_userInterestRate[user];
    }

    function getUserPrincipleBalance(address user) external view returns (uint256) {
        return super.balanceOf(user);
    }

    function getCurrentInterestRate() external view returns (uint256) {
        return s_InterestRate;
    }
}
