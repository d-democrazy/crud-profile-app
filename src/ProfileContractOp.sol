// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IProfileContractOp} from "./interfaces/IProfileContractOp.sol";
import {ProfileTypes} from "./libraries/ProfileTypes.sol";
import {ValidationHelper} from "./helpers/ValidationHelper.sol";
import {CompareHelper} from "./helpers/CompareHelper.sol";

contract ProfileContractOp is IProfileContractOp, ValidationHelper, CompareHelper {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => ProfileTypes.Profile) private profiles;
    EnumerableSet.AddressSet private profileOwners;

    function setProfile(ProfileTypes.ProfileInput calldata input) external {
        if (profiles[msg.sender].exists) {
            revert ProfileAlreadyExists();
        }

        _validateRequiredString(input.name, ProfileTypes.Field.Name, 100);
        _validateRequiredString(input.profession, ProfileTypes.Field.Profession, 50);
        _validateRequiredString(input.bio, ProfileTypes.Field.Bio, 500);
        if (input.experience == 0) revert RequiredField(ProfileTypes.Field.Experience);

        profileOwners.add(msg.sender);
        profiles[msg.sender] = ProfileTypes.Profile({
            name: input.name, profession: input.profession, bio: input.bio, experience: input.experience, exists: true
        });

        emit ProfileSet(msg.sender, profiles[msg.sender]);
    }

    function updateProfile(ProfileTypes.ProfileInput calldata input) external {
        ProfileTypes.Profile storage profile = profiles[msg.sender];
        if (!profile.exists) {
            revert ProfileNotFound();
        }

        string[] memory updatedFields = new string[](4);
        uint8 changedCount;

        if (bytes(input.name).length != 0) {
            _validateRequiredString(input.name, ProfileTypes.Field.Name, 100);
            if (_isDifferent(input.name, profile.name)) {
                profile.name = input.name;
                updatedFields[changedCount++] = "name";
            }
        }
        if (bytes(input.profession).length != 0) {
            _validateRequiredString(input.profession, ProfileTypes.Field.Profession, 50);
            if (_isDifferent(input.profession, profile.profession)) {
                profile.profession = input.profession;
                updatedFields[changedCount++] = "profession";
            }
        }
        if (bytes(input.bio).length != 0) {
            _validateRequiredString(input.bio, ProfileTypes.Field.Bio, 500);
            if (_isDifferent(input.bio, profile.bio)) {
                profile.bio = input.bio;
                updatedFields[changedCount++] = "bio";
            }
        }
        if (input.experience != 0 && input.experience != profile.experience) {
            profile.experience = input.experience;
            updatedFields[changedCount++] = "experience";
        }
        if (changedCount == 0) {
            revert NoChanges();
        }

        assembly {
            mstore(updatedFields, changedCount)
        }

        emit ProfileUpdated(msg.sender, updatedFields);
    }

    function getProfile(address profileOwner) external view returns (ProfileTypes.Profile memory) {
        if (!profiles[profileOwner].exists) {
            revert ProfileNotFound();
        }
        return profiles[profileOwner];
    }

    function getAllProfiles() external view returns (address[] memory, ProfileTypes.Profile[] memory) {
        uint256 length = profileOwners.length();
        address[] memory owners = profileOwners.values();
        ProfileTypes.Profile[] memory allProfiles = new ProfileTypes.Profile[](length);

        for (uint256 i; i < length; i++) {
            allProfiles[i] = profiles[owners[i]];
        }
        return (owners, allProfiles);
    }

    function deleteProfile() external {
        if (!profiles[msg.sender].exists) {
            revert ProfileNotFound();
        }
        delete profiles[msg.sender];
        profileOwners.remove(msg.sender);

        emit ProfileCleared(msg.sender);
    }
}
