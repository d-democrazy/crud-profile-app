// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

abstract contract CompareHelper {
    function _isDifferent(string calldata input, string storage current) internal pure returns (bool) {
        return keccak256(bytes(input)) != keccak256(bytes(current));
    }
}
