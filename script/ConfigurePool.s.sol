// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {TokenPool} from "lib/ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "lib/ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

contract ConfigurePoolScript is Script {
    function run(
        address tokenPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken,
        bool outBoundRateLimiterIsEnabled,
        uint128 outBoundRateLimiterCapacity,
        uint128 outBoundRateLimiterRate,
        bool inBoundRateLimiterIsEnabled,
        uint128 inBoundRateLimiterCapacity,
        uint128 inBoundRateLimiterRate
    ) public {
        vm.startBroadcast();
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePool),
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: outBoundRateLimiterIsEnabled,
                capacity: outBoundRateLimiterCapacity,
                rate: outBoundRateLimiterRate
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: inBoundRateLimiterIsEnabled,
                capacity: inBoundRateLimiterCapacity,
                rate: inBoundRateLimiterRate
            })
        });
        TokenPool(tokenPool).applyChainUpdates(chainsToAdd);
        vm.stopBroadcast();
    }
}
