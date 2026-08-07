// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ProfileTypes} from "../libraries/ProfileTypes.sol";

interface IProfileContractOp {
    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------
    // Note: field-validation errors (RequiredField, MaxLengthExceeded) live
    // on ValidationHelper, not here — ProfileContractOp inherits both this
    // interface and ValidationHelper, and Solidity forbids two parents from
    // declaring an identically-named error. They still show up in the final
    // ABI via inheritance, so callers can decode them the same way.

    error ProfileAlreadyExists();
    error ProfileNotFound();
    error NoChanges();

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event ProfileSet(address indexed profileOwner, ProfileTypes.Profile profile);

    event ProfileUpdated(address indexed profileOwner, string[] updatedFields, ProfileTypes.Profile profile);

    event ProfileCleared(address indexed profileOwner);

    // ---------------------------------------------------------------------
    // External API
    // ---------------------------------------------------------------------

    function setProfile(ProfileTypes.ProfileInput calldata input) external;

    function updateProfile(ProfileTypes.ProfileInput calldata input) external;

    function deleteProfile() external returns (bool);

    function getProfile(address profileOwner) external view returns (ProfileTypes.Profile memory);

    function getAllProfiles() external view returns (address[] memory, ProfileTypes.Profile[] memory);
}
