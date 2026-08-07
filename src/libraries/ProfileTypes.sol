// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

library ProfileTypes {
    enum Field {
        Name,
        Profession,
        Bio,
        Experience
    }

    struct Profile {
        string name;
        string profession;
        string bio;
        uint8 experience;
        bool exists;
    }

    struct ProfileInput {
        string name;
        string profession;
        string bio;
        uint8 experience;
    }
}
