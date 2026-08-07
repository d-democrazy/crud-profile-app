// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProfileContractOp} from "../src/ProfileContractOp.sol";
import {ProfileTypes} from "../src/libraries/ProfileTypes.sol";
import {ValidationHelper} from "../src/helpers/ValidationHelper.sol";
import {IProfileContractOp} from "../src/interfaces/IProfileContractOp.sol";

contract ProfileContractOpTest is Test {
    ProfileContractOp profileContractOp;
    address public owner;
    address alice = makeAddr("Alice");
    address bob = makeAddr("Bob");
    address attacker = makeAddr("Attacker");

    function setUp() public {
        owner = address(this);
        profileContractOp = new ProfileContractOp();
    }

    function _makeInput(string memory _name, string memory _profession, string memory _bio, uint8 _experience)
        internal
        pure
        returns (ProfileTypes.ProfileInput memory)
    {
        return ProfileTypes.ProfileInput({name: _name, profession: _profession, bio: _bio, experience: _experience});
    }

    function testQuickSetProfile() public {
        vm.startPrank(alice);
        profileContractOp.setProfile(_makeInput("Alice", "Software Engineer", "Hello from Kediri", 8));

        vm.expectRevert(IProfileContractOp.ProfileAlreadyExists.selector);
        profileContractOp.setProfile(_makeInput("Alice", "UI/UX", "Hello from Kediri", 1));
        vm.stopPrank();
    }

    function testQuickSetProfileRequiresExperience() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(ValidationHelper.RequiredField.selector, ProfileTypes.Field.Experience));
        profileContractOp.setProfile(_makeInput("Alice", "Software Engineer", "Hello from Kediri", 0));
        vm.stopPrank();
    }

    function testQuickUpdateProfile() public {
        vm.startPrank(bob);
        profileContractOp.setProfile(_makeInput("Bob", "AI Engineer", "Hello from Purwokerto", 12));
        profileContractOp.updateProfile(_makeInput("", "", "", 15));
        vm.stopPrank();

        vm.startPrank(attacker);
        vm.expectRevert(IProfileContractOp.ProfileNotFound.selector);
        profileContractOp.updateProfile(_makeInput("", "AI Engineer", "Hello from Purwokerto", 12));
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(IProfileContractOp.NoChanges.selector);
        profileContractOp.updateProfile(_makeInput("Bob", "AI Engineer", "Hello from Purwokerto", 15));
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(IProfileContractOp.NoChanges.selector);
        profileContractOp.updateProfile(_makeInput("", "", "", 0));
        vm.stopPrank();
    }

    function testQuickGetProfile() public {
        vm.startPrank(alice);
        profileContractOp.setProfile(_makeInput("Alice", "Software Engineer", "Hello from Kediri", 8));
        vm.stopPrank();

        vm.startPrank(bob);
        profileContractOp.setProfile(_makeInput("Bob", "Blockchain Engineer", "Hello from England", 8));
        vm.stopPrank();

        profileContractOp.setProfile(_makeInput("Angga", "Smart Contract Developer", "Hello from Isekai", 6));

        vm.startPrank(alice);
        profileContractOp.getProfile(alice);
        vm.stopPrank();

        vm.startPrank(bob);
        profileContractOp.getProfile(bob);
        vm.stopPrank();

        vm.startPrank(bob);
        profileContractOp.getProfile(alice);
        vm.stopPrank();

        vm.startPrank(alice);
        profileContractOp.getProfile(bob);
        profileContractOp.getProfile(owner);
        vm.stopPrank();

        vm.startPrank(alice);
        profileContractOp.getProfile(owner);
        vm.expectRevert(IProfileContractOp.ProfileNotFound.selector);
        profileContractOp.getProfile(attacker);
        vm.stopPrank();

        profileContractOp.getProfile(owner);
    }

    function testQuickGetAllProfiles() public {
        vm.startPrank(alice);
        profileContractOp.setProfile(_makeInput("Alice", "Software Engineer", "Hello from Norway", 8));
        vm.stopPrank();

        vm.startPrank(bob);
        profileContractOp.setProfile(_makeInput("Bob", "Blockchain Engineer", "Hello from England", 8));
        vm.stopPrank();

        profileContractOp.setProfile(_makeInput("Angga", "Smart Contract Developer", "Hello from Isekai", 6));

        profileContractOp.getAllProfiles();

        vm.prank(alice);
        profileContractOp.getAllProfiles();
    }

    function testQuickDeleteProfile() public {
        vm.startPrank(alice);
        profileContractOp.setProfile(_makeInput("Alice", "Software Engineer", "Hello from Kediri", 8));
        vm.stopPrank();

        vm.startPrank(alice);
        profileContractOp.getProfile(alice);
        vm.stopPrank();

        vm.startPrank(alice);
        bool deleted = profileContractOp.deleteProfile();
        assertTrue(deleted);
        vm.stopPrank();

        vm.startPrank(attacker);
        vm.expectRevert(IProfileContractOp.ProfileNotFound.selector);
        profileContractOp.getProfile(alice);
        vm.stopPrank();
    }
}
