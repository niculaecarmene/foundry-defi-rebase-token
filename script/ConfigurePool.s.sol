// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";


contract ConfigurePool is Script {
    function run(
        address localPool,
        uint64 remoteChainSelector,
        address remotePoolAddress,
        address remoteTokenAddress,
        bool outboundRateLimiterIsEnable,
        uint128 outboundRateLimiterCapacity,
        uint128 outboundRateLimiterRate,
        bool inboundRateLimiterIsEnable,
        uint128 inboundRateLimiterCapacity,
        uint128 inboundRateLimiterRate
    ) external {
        vm.startBroadcast();

        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePoolAddress),
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({
                    isEnabled:outboundRateLimiterIsEnable, 
                    capacity: outboundRateLimiterCapacity, 
                    rate: outboundRateLimiterRate}),
            inboundRateLimiterConfig: RateLimiter.Config({
                    isEnabled: inboundRateLimiterIsEnable, 
                    capacity: inboundRateLimiterCapacity, 
                    rate: inboundRateLimiterRate })
        });
        TokenPool(localPool).applyChainUpdates(chainsToAdd);

        vm.stopBroadcast();
    }
}
