// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ProfileContract} from "../src/ProfileContract.sol";

contract DeployProfileContract is Script {
    ProfileContract public profileContract;

    function run() public {
        string memory explorerUrl = vm.envString("CORESCAN_TESTNET2");
        vm.startBroadcast();
        profileContract = new ProfileContract();
        vm.stopBroadcast();

        console.log(
            string.concat(
                "ProfileApp is successfully deployed to: ", explorerUrl, vm.toString(address(profileContract))
            )
        );
    }
}
