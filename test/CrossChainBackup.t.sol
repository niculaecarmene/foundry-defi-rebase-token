/**
 * 
 // SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract ChrossChain is Test {

    address public owner = makeAddr("OWNER");
    address public user = makeAddr("USER");
    uint256 public SEND_VALUE = 1e5;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    uint256 sepoliaFork;
    uint256 arbitrumFork;

    RebaseToken sepoliaToken;
    RebaseToken arbitrumToken;

    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbitrumPool;

    Register.NetworkDetails sepoliaNetwork;
    Register.NetworkDetails arbitrumNetwork;

    Vault vault;

    function setUp() public{
        sepoliaFork = vm.createSelectFork("eth");
        arbitrumFork = vm.createSelectFork("arb");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 1. Deploy and configure SEPOLIA
        vm.selectFork(sepoliaFork);
        sepoliaNetwork = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(IERC20(address(sepoliaToken)), 
                            new address[](0), 
                            sepoliaNetwork.rmnProxyAddress, 
                            sepoliaNetwork.routerAddress);
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        RegistryModuleOwnerCustom(sepoliaNetwork.registryModuleOwnerCustomAddress).
                                        registerAdminViaOwner(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetwork.tokenAdminRegistryAddress).
                                        acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetwork.tokenAdminRegistryAddress).
                                        setPool(address(sepoliaToken), address(sepoliaPool));
        vm.stopPrank();

        console.log("sepolia - chainid",block.chainid);

        // 2. Deploy and configure ARBITRUM
        vm.selectFork(arbitrumFork);
        arbitrumNetwork = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        arbitrumToken = new RebaseToken();
        arbitrumPool = new RebaseTokenPool(IERC20(address(arbitrumToken)), 
                            new address[](0), 
                            arbitrumNetwork.rmnProxyAddress, 
                            arbitrumNetwork.routerAddress);
        arbitrumToken.grantMintAndBurnRole(address(arbitrumPool));
        RegistryModuleOwnerCustom(arbitrumNetwork.registryModuleOwnerCustomAddress).
                                        registerAdminViaOwner(address(arbitrumToken));
        TokenAdminRegistry(arbitrumNetwork.tokenAdminRegistryAddress).
                                        acceptAdminRole(address(arbitrumToken));
        TokenAdminRegistry(arbitrumNetwork.tokenAdminRegistryAddress).
                                        setPool(address(arbitrumToken), address(arbitrumPool));
        vm.stopPrank();

        console.log("arbitrum - chainid",block.chainid);

        configureTokenPool(sepoliaFork, 
                address(sepoliaPool),
                arbitrumNetwork.chainSelector,
                address(arbitrumPool),
                address(arbitrumToken));

        console.log("sepolia pool config");

        configureTokenPool(arbitrumFork, 
                address(arbitrumPool),
                sepoliaNetwork.chainSelector,
                address(sepoliaPool),
                address(sepoliaToken));

        console.log("arbitrum pool config");
        
    }

    function configureTokenPool(uint256 fork, address localPool, 
                    uint64 remoteChainSelector, address remotePool,
                    address remoteTokenAddress) public {
        vm.selectFork(fork);
        vm.prank(owner);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
 
        chainsToAdd[0] = TokenPool.ChainUpdate({
                remoteChainSelector: remoteChainSelector,
                allowed: true,
                remotePoolAddress: abi.encode(remotePool),
                remoteTokenAddress: abi.encode(remoteTokenAddress),
                outboundRateLimiterConfig:
                    RateLimiter.Config({
                        isEnabled: false,
                        capacity: 0,
                        rate:0
                    }),
                inboundRateLimiterConfig:
                    RateLimiter.Config({
                        isEnabled: false,
                        capacity: 0,
                        rate: 0
                    })
        });

        TokenPool(localPool).applyChainUpdates(chainsToAdd);
        console.log("configPool - after applyChainUpdates");
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
 
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
                token: address(localToken),
                amount: amountToBridge
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
                receiver: abi.encode(user),
                data: "",
                tokenAmounts: tokenAmounts,
                feeToken: localNetworkDetails.linkAddress,
                extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({gasLimit:500_000, allowOutOfOrderExecution: false}))
        });

        uint256 fee = IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        uint256 localBalanceBefore = localToken.balanceOf(user);

        vm.prank(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        uint256 localBalanceAfter = localToken.balanceOf(user);
        assertEq(localBalanceAfter, localBalanceBefore-amountToBridge);
        uint256 localUserInterestRate = localToken.getUserInterestRate(user);

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);

        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        assertEq(remoteBalanceAfter, remoteBalanceBefore+amountToBridge);
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);
        assertEq(localUserInterestRate, remoteUserInterestRate);

    }

    function testBridgeAllTokens() public {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value:SEND_VALUE}();
        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE);
        bridgeTokens(SEND_VALUE,
                sepoliaFork,
                arbitrumFork,
                sepoliaNetwork,
                arbitrumNetwork,
                sepoliaToken,
                arbitrumToken
        );

        vm.selectFork(arbitrumFork);
        vm.warp(block.timestamp + 20 minutes);
        bridgeTokens(arbitrumToken.balanceOf(user),
                arbitrumFork,
                sepoliaFork,
                arbitrumNetwork,
                sepoliaNetwork,
                arbitrumToken,
                sepoliaToken
        );
    }
}
 */