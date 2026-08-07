// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ProfileContractOp} from "../src/ProfileContractOp.sol";

contract DeployProfileContractOp is Script {
    ProfileContractOp profileContractOp;

    function run() public {
        string memory explorerUrl = vm.envString("CORESCAN_TESTNET2");

        vm.startBroadcast();
        profileContractOp = new ProfileContractOp();
        vm.stopBroadcast();

        console.log(
            string.concat(
                "Optimized Profile Contract is deployed to: ", explorerUrl, vm.toString(address(profileContractOp))
            )
        );
    }
}
