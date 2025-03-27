// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

 
import { RebaseToken } from "../src/RebaseToken.sol";
import { RebaseTokenPool } from "../src/RebaseTokenPool.sol";
import { Vault } from "../src/Vault.sol";
import { IRebaseToken } from "../src/interfaces/IRebaseToken.sol";


// We need to have this separated, so we can deploy Token and Pool on both chains
contract TokenAndPoolDeployer is Script {
    function run() external returns (RebaseToken token, RebaseTokenPool pool){
       

        CCIPLocalSimulatorFork ccipLocalFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = 
            ccipLocalFork.getNetworkDetails(block.chainid);
        vm.startBroadcast();

        token = new RebaseToken();
        pool = new RebaseTokenPool(
            IERC20(address(token)), 
            new address[](0), 
            networkDetails.rmnProxyAddress, 
            networkDetails.routerAddress);
        
        token.grantMintAndBurnRole(address(pool));
        RegistryModuleOwnerCustom(networkDetails.
                registryModuleOwnerCustomAddress).
                registerAdminViaOwner(address(token));

        TokenAdminRegistry registry = TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress);
        registry.acceptAdminRole(address(token));
        registry.setPool(address(token), address(pool));

        vm.stopBroadcast();
    }
}

// The Vault will be deployed only on the source chain
contract VaultDeployer is Script {

    function run(IRebaseToken _rebaseToken) external returns(Vault vault){
        vm.startBroadcast();
        vault = new Vault(IRebaseToken(_rebaseToken));
        IRebaseToken(_rebaseToken).grantMintAndBurnRole(address(vault));

        vm.stopBroadcast();
    }
}