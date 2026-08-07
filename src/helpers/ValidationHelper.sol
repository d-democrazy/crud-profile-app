// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ProfileTypes} from "../libraries/ProfileTypes.sol";

abstract contract ValidationHelper {
    error RequiredField(ProfileTypes.Field field);
    error MaxLengthExceeded(ProfileTypes.Field field, uint256 maxLength);

    function _validateRequiredString(string calldata value, ProfileTypes.Field field, uint256 maxLength) internal pure {
        uint256 length = bytes(value).length;
        if (length == 0) revert RequiredField(field);
        if (length > maxLength) revert MaxLengthExceeded(field, maxLength);
    }
}
