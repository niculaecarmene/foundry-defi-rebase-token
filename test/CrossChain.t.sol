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

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract ChrossChain is Test {

    address public owner = makeAddr("OWNER");
    address public user = makeAddr("USER");
    uint256 public constant SEND_VALUE = 1e5;

    CCIPLocalSimulatorFork private ccipLocalSimulatorFork;

    uint256 private sepoliaFork;
    uint256 private arbitrumFork;

    RebaseToken private sepoliaToken;
    RebaseToken private arbitrumToken;

    RebaseTokenPool private sepoliaPool;
    RebaseTokenPool private arbitrumPool;

    Register.NetworkDetails private sepoliaNetwork;
    Register.NetworkDetails private arbitrumNetwork;

    Vault private vault;

    struct BridgeConfig {
        uint256 amount;
        uint256 sourceFork;
        uint256 destFork;
        Register.NetworkDetails sourceNetwork;
        Register.NetworkDetails destNetwork;
        RebaseToken sourceToken;
        RebaseToken destToken;
    }

    function setUp() public {
        sepoliaFork = vm.createSelectFork("eth");
        arbitrumFork = vm.createSelectFork("arb");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Deploy and configure Sepolia
        _setupChain(sepoliaFork, true);
        // Deploy and configure Arbitrum
        _setupChain(arbitrumFork, false);

        // Configure pools after both chains are set up
        _configurePools();
    }

    function _setupChain(uint256 fork, bool isSepolia) private {
        vm.selectFork(fork);
        Register.NetworkDetails memory network = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);
        RebaseToken token = new RebaseToken();
        RebaseTokenPool pool = new RebaseTokenPool(
            IERC20(address(token)),
            new address[](0),
            network.rmnProxyAddress,
            network.routerAddress
        );

        if (isSepolia) {
            vault = new Vault(IRebaseToken(address(token)));
            token.grantMintAndBurnRole(address(vault));
            sepoliaToken = token;
            sepoliaPool = pool;
            sepoliaNetwork = network;
        } else {
            arbitrumToken = token;
            arbitrumPool = pool;
            arbitrumNetwork = network;
        }

        token.grantMintAndBurnRole(address(pool));
        _registerTokenAdmin(address(token), address(pool), network);
        vm.stopPrank();
    }

    function _registerTokenAdmin(address token, address pool, Register.NetworkDetails memory network) private {
        RegistryModuleOwnerCustom(network.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(token);
        TokenAdminRegistry(network.tokenAdminRegistryAddress)
            .acceptAdminRole(token);
        TokenAdminRegistry(network.tokenAdminRegistryAddress)
            .setPool(token, address(pool));
    }

    function _configurePools() private {
        _configurePool(
            sepoliaFork,
            address(sepoliaPool),
            arbitrumNetwork.chainSelector,
            address(arbitrumPool),
            address(arbitrumToken)
        );
        _configurePool(
            arbitrumFork,
            address(arbitrumPool),
            sepoliaNetwork.chainSelector,
            address(sepoliaPool),
            address(sepoliaToken)
        );
    }

    function _configurePool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken
    ) private {
        vm.selectFork(fork);
        vm.prank(owner);
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePool),
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config(false, 0, 0),
            inboundRateLimiterConfig: RateLimiter.Config(false, 0, 0)
        });
        TokenPool(localPool).applyChainUpdates(chains);
    }

    // Helper function to create bridge configuration
    function _createBridgeConfig(
        uint256 amount,
        uint256 sourceFork,
        uint256 destFork,
        Register.NetworkDetails memory sourceNetwork,
        Register.NetworkDetails memory destNetwork,
        RebaseToken sourceToken,
        RebaseToken destToken
    ) private pure returns (BridgeConfig memory) {
        return BridgeConfig({
            amount: amount,
            sourceFork: sourceFork,
            destFork: destFork,
            sourceNetwork: sourceNetwork,
            destNetwork: destNetwork,
            sourceToken: sourceToken,
            destToken: destToken
        });
    }

    // Core bridging logic
    function _bridgeTokens(BridgeConfig memory config) private {
        vm.selectFork(config.sourceFork);

        console.log("bridge user interestrate:", config.sourceToken.getUserInterestRate(user));
        
        // Prepare CCIP message
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(config.sourceToken),
            amount: config.amount
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: config.sourceNetwork.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2(500_000, false))
        });

        console.log("before fee");
        // Handle fees
        uint256 fee = IRouterClient(config.sourceNetwork.routerAddress)
            .getFee(config.destNetwork.chainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        console.log("after faucet");

        vm.startPrank(user);
        IERC20(config.sourceNetwork.linkAddress).approve(config.sourceNetwork.routerAddress, fee);
        console.log("IERC20 approve");
        config.sourceToken.approve(config.sourceNetwork.routerAddress, config.amount);
        console.log("sepolia token approve token amount");
        vm.stopPrank();

        // Execute bridge
        uint256 initialSourceBalance = config.sourceToken.balanceOf(user);
        vm.prank(user);

        IRouterClient(config.sourceNetwork.routerAddress).ccipSend(
            config.destNetwork.chainSelector,
            message
        );

        // Validate source chain
        assertEq(
            config.sourceToken.balanceOf(user),
            initialSourceBalance - config.amount,
            "Source balance mismatch"
        );


        console.log("bridge user interestrate - before selct destFork:", config.sourceToken.getUserInterestRate(user));
        
        // Validate destination chain
        vm.selectFork(config.destFork);
        vm.warp(block.timestamp + 20 minutes); // Simulate time passage
        uint256 remoteBalanceBefore = config.destToken.balanceOf(user);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(config.destFork);
        console.log("bridge user interestrate - after select destFork - source:", config.sourceToken.getUserInterestRate(user));
        console.log("bridge user interestrate - after select destFork - dest:", config.destToken.getUserInterestRate(user));
        

        uint256 remoteBalanceAfter = config.destToken.balanceOf(user);
        uint256 expectedDestBalance = remoteBalanceBefore + config.amount;
        assertEq(
            remoteBalanceAfter,
            expectedDestBalance,
            "Destination balance mismatch"
        );

        // Validate interest rate persistence
        uint256 sourceRate = config.sourceToken.getUserInterestRate(user);
        uint256 destRate = config.destToken.getUserInterestRate(user);
        console.log("bridge source:", sourceRate);
        console.log("bridge dest:", destRate);
        assertEq(sourceRate, destRate, "Interest rate mismatch");
    }

    // Test Cases
    function test_BasicCrossChainTransfer() public {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        vault.deposit{value: SEND_VALUE}();

        BridgeConfig memory bridge = _createBridgeConfig(
            SEND_VALUE,
            sepoliaFork,
            arbitrumFork,
            sepoliaNetwork,
            arbitrumNetwork,
            sepoliaToken,
            arbitrumToken
        );
        _bridgeTokens(bridge);
    }


    function testBridgeAllTokens() public {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value:SEND_VALUE}();
        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE);
        BridgeConfig memory sepoliaToArbitrum = _createBridgeConfig(
                SEND_VALUE,
                sepoliaFork,
                arbitrumFork,
                sepoliaNetwork,
                arbitrumNetwork,
                sepoliaToken,
                arbitrumToken
        );
        _bridgeTokens(sepoliaToArbitrum);

        vm.selectFork(arbitrumFork);
        vm.warp(block.timestamp + 20 minutes);
        BridgeConfig memory arbitrumToSepolia = _createBridgeConfig(
                arbitrumToken.balanceOf(user),
                arbitrumFork,
                sepoliaFork,
                arbitrumNetwork,
                sepoliaNetwork,
                arbitrumToken,
                sepoliaToken
        );
        _bridgeTokens(arbitrumToSepolia);
    }

/*
    function test_InterestRatePersistence() public {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE+SEND_VALUE);
        vm.prank(user);
        vault.deposit{value: SEND_VALUE}();

        // Change interest rate before bridging
        uint256 newRate = sepoliaToken.getInterestRate() / 2;
        vm.prank(owner);
        sepoliaToken.setInterestRate(newRate);


        console.log("test - interestrate:", sepoliaToken.getInterestRate());
        vm.prank(user);
        vault.deposit{value: SEND_VALUE}();

        console.log("test - user interestrate:", sepoliaToken.getUserInterestRate(user));
        BridgeConfig memory bridge = _createBridgeConfig(
            SEND_VALUE,
            sepoliaFork,
            arbitrumFork,
            sepoliaNetwork,
            arbitrumNetwork,
            sepoliaToken,
            arbitrumToken
        );
        _bridgeTokens(bridge);

        // Validate rate on destination
        vm.selectFork(sepoliaFork);
        assertEq(
            sepoliaToken.getUserInterestRate(user),
            newRate,
            "Interest rate not persisted in sepolia"
        );
        vm.selectFork(arbitrumFork);
        assertEq(
            arbitrumToken.getUserInterestRate(user),
            newRate,
            "Interest rate not persisted in arbitrum"
        );

    }*/
/*
   function test_InsufficientBalanceReverts() public {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        vault.deposit{value: SEND_VALUE}();

        uint256 actualBalance = sepoliaToken.balanceOf(user);

        BridgeConfig memory bridge = _createBridgeConfig(
            SEND_VALUE * 2, // Double the balance
            sepoliaFork,
            arbitrumFork,
            sepoliaNetwork,
            arbitrumNetwork,
            sepoliaToken,
            arbitrumToken
        );

        //vm.expectPartialRevert(IERC20Errors.ERC20InsufficientBalance.selector);


        vm.expectRevert(abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector,
            user,           // Sender address
            SEND_VALUE*2,  // Amount attempted to transfer
            actualBalance     // Actual balance
        ));
        //vm.expectRevert("ERC20: transfer amount exceeds balance");
        _bridgeTokens(bridge);
    }
    
    function test_RoundTripRebasing() public {
        // Deposit and bridge to Arbitrum
        test_BasicCrossChainTransfer();

        // Bridge back to Sepolia
        vm.selectFork(arbitrumFork);
        uint256 arbitrumBalance = arbitrumToken.balanceOf(user);
        
        BridgeConfig memory returnBridge = _createBridgeConfig(
            arbitrumBalance,
            arbitrumFork,
            sepoliaFork,
            arbitrumNetwork,
            sepoliaNetwork,
            arbitrumToken,
            sepoliaToken
        );
        _bridgeTokens(returnBridge);

        // Validate final balance with rebasing
        vm.selectFork(sepoliaFork);
        uint256 expectedBalance = SEND_VALUE * 2; // Initial deposit + bridged back
        assertEq(
            sepoliaToken.balanceOf(user),
            expectedBalance,
            "Round trip balance mismatch"
        );
    }
*/
}