// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
   
import {Script} from "forge-std/Script.sol";

import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeToken is Script {
    function run(address linkTokenAddress, uint256 amountToSend, address tokenToSendAddress, address receiverAddress, uint64 destinationChainSelector, address ccipRouterAddress) external {
        vm.startBroadcast();

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: tokenToSendAddress,
            amount: amountToSend
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(address(receiverAddress)), // Replace with the actual receiver address
            data: "", // Replace with the actual data
            tokenAmounts: tokenAmounts, // Replace with token amounts if needed
            feeToken: linkTokenAddress, // Replace with the actual fee token address
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit:0})) // Replace with extra arguments if needed
        });

        uint256 fee = IRouterClient(ccipRouterAddress).getFee(destinationChainSelector, message);
        IERC20(linkTokenAddress).approve(ccipRouterAddress, fee);
        IERC20(tokenToSendAddress).approve(ccipRouterAddress, amountToSend);
        IRouterClient(ccipRouterAddress).ccipSend(destinationChainSelector,message);

        vm.stopBroadcast();
    }
}
