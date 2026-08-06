// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProfileContract} from "../src/ProfileContract.sol";

contract ProfileContractTest is Test {
    ProfileContract profileContract;

    address public owner;
    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");
    address attacker = makeAddr("Attacker");

    function setUp() public {
        owner = address(this);
        profileContract = new ProfileContract();
    }

    function testQuickSetProfile() public {
        vm.startPrank(alice);
        profileContract.setProfile("Alice", "Software Engineer", "Hello from Kediri", 8);

        vm.expectRevert("Already registered, use update instead");
        profileContract.setProfile("Alice", "UI/UX Designer", "Hello from Kediri", 1);
        vm.stopPrank();
    }

    function testQuickUpdateProfile() public {
        vm.startPrank(bob);
        profileContract.setProfile("Bob", "AI Engineer", "Hello from Purwokerto", 12);
        profileContract.updateProfile("", "", "", 15);
        vm.stopPrank();

        vm.startPrank(attacker);
        vm.expectRevert("No profile to update");
        profileContract.updateProfile("Attacker", "AI Engineer", "Hello from Purwokerto", 12);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert("No changes provided");
        profileContract.updateProfile("Bob", "AI Engineer", "Hello from Purwokerto", 15);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert("No changes provided");
        profileContract.updateProfile("", "", "", 0);
        vm.stopPrank();
    }

    function testQuickGetProfile() public {
        vm.startPrank(alice);
        profileContract.setProfile("Alice", "Software Engineer", "Hello from Kediri", 8);
        vm.stopPrank();

        vm.startPrank(bob);
        profileContract.setProfile("Bob", "Blockchain Engineer", "Hello from England", 8);
        vm.stopPrank();

        profileContract.setProfile("Angga", "Smart Contract Developer", "Hello from Isekai", 6);

        vm.startPrank(alice);
        profileContract.getProfile(alice);
        vm.stopPrank();

        vm.startPrank(bob);
        profileContract.getProfile(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        profileContract.getProfile(alice);
        vm.stopPrank();

        vm.startPrank(alice);
        profileContract.getProfile(bob);
        profileContract.getProfile(owner);
        vm.stopPrank();

        vm.startPrank(alice);
        profileContract.getProfile(owner);
        vm.expectRevert("No profile for this address");
        profileContract.getProfile(attacker);
        vm.stopPrank();

        profileContract.getProfile(owner);
    }

    function testQuickGetAllProfile() public {
        vm.startPrank(alice);
        profileContract.setProfile("Alice", "Software Engineer", "Hello from Norway", 8);
        vm.stopPrank();

        vm.startPrank(bob);
        profileContract.setProfile("Bob", "Blockchain Engineer", "Hello from England", 8);
        vm.stopPrank();

        profileContract.setProfile("Angga", "Smart Contract Developer", "Hello from Isekai", 6);

        profileContract.getAllProfile();

        vm.prank(alice);
        profileContract.getAllProfile();
    }

    function testQuickDeleteProfile() public {
        vm.startPrank(alice);
        profileContract.setProfile("Alice", "Software Engineer", "Hello from Kediri", 8);
        vm.stopPrank();

        vm.startPrank(alice);
        profileContract.getProfile(alice);
        vm.stopPrank();

        vm.startPrank(alice);
        profileContract.deleteProfile();
        vm.stopPrank();

        vm.startPrank(attacker);
        vm.expectRevert("No profile for this address");
        profileContract.getProfile(alice);
        vm.stopPrank();
    }
}
