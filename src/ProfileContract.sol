// SPDX-license-Identifier: MIT

pragma solidity 0.8.24;

contract ProfileContract {
    struct Profile {
        string name;
        string profession;
        string bio;
        uint8 experience;
        bool exists;
    }

    mapping(address => Profile) private profiles;
    address[] private profileOwners;
    mapping(address => uint256) private ownerIndex;

    event ProfileSet(address indexed profileOwner, Profile profile);
    event ProfileUpdated(address indexed profileOwner, string[] updatedFields);
    event ProfileCleared(address indexed profileOwner);

    function setProfile(string calldata _name, string calldata _profession, string calldata _bio, uint8 _experience)
        external
    {
        require(!profiles[msg.sender].exists, "Already registered, use update instead");
        require(
            bytes(_name).length != 0 && bytes(_profession).length != 0 && bytes(_bio).length != 0 && _experience != 0,
            "All fields must be filled"
        );
        require(bytes(_name).length <= 100, "Name too long");
        require(bytes(_profession).length <= 100, "Profession too long");
        require(bytes(_bio).length <= 500, "Bio too long");

        ownerIndex[msg.sender] = profileOwners.length;
        profileOwners.push(msg.sender);

        profiles[msg.sender] =
            Profile({name: _name, profession: _profession, bio: _bio, experience: _experience, exists: true});

        emit ProfileSet(msg.sender, profiles[msg.sender]);
    }

    function updateProfile(string calldata _name, string calldata _profession, string calldata _bio, uint8 _experience)
        external
    {
        require(profiles[msg.sender].exists, "No profile to update");

        bool nameProvided =
            bytes(_name).length > 0 && keccak256(bytes(_name)) != keccak256(bytes(profiles[msg.sender].name));
        bool professionProvided = bytes(_profession).length > 0
            && keccak256(bytes(_profession)) != keccak256(bytes(profiles[msg.sender].profession));
        bool bioProvided =
            bytes(_bio).length > 0 && keccak256(bytes(_bio)) != keccak256(bytes(profiles[msg.sender].bio));
        bool experienceProvided = _experience != 0 && _experience != profiles[msg.sender].experience;

        require(nameProvided || professionProvided || bioProvided || experienceProvided, "No changes provided");

        if (nameProvided) {
            require(bytes(_name).length <= 100, "Name too long");
            profiles[msg.sender].name = _name;
        }
        if (professionProvided) {
            require(bytes(_profession).length <= 100, "profession too long");
            profiles[msg.sender].profession = _profession;
        }
        if (bioProvided) {
            require(bytes(_bio).length <= 500, "bio too long");
            profiles[msg.sender].bio = _bio;
        }
        if (experienceProvided) {
            profiles[msg.sender].experience = _experience;
        }

        uint8 changedCount = 0;
        if (nameProvided) changedCount++;
        if (professionProvided) changedCount++;
        if (bioProvided) changedCount++;
        if (experienceProvided) changedCount++;

        string[] memory UpdatedFields = new string[](changedCount);
        uint8 i = 0;
        if (nameProvided) UpdatedFields[i++] = string.concat("name: ", profiles[msg.sender].name);
        if (professionProvided) UpdatedFields[i++] = string.concat("profession: ", profiles[msg.sender].profession);
        if (bioProvided) UpdatedFields[i++] = string.concat("bio: ", profiles[msg.sender].bio);
        if (experienceProvided) {
            UpdatedFields[i++] = "experience";
        }

        emit ProfileUpdated(msg.sender, UpdatedFields);
    }

    function getProfile(address profileOwner) external view returns (Profile memory) {
        require(profiles[profileOwner].exists, "No profile for this address");
        return profiles[profileOwner];
    }

    function getAllProfile() external view returns (address[] memory, Profile[] memory) {
        uint256 totalProfiles = profileOwners.length;
        address[] memory profileOwnersCopy = profileOwners;
        Profile[] memory profilesCopy = new Profile[](totalProfiles);

        for (uint256 i; i < totalProfiles; i++) {
            profileOwnersCopy[i] = profileOwners[i];
            profilesCopy[i] = profiles[profileOwners[i]];
        }

        return (profileOwnersCopy, profilesCopy);
    }

    function deleteProfile() external returns (bool) {
        require(profiles[msg.sender].exists, "Nothing to delete");
        delete profiles[msg.sender];

        uint256 idx = ownerIndex[msg.sender];
        uint256 lastIndx = profileOwners.length - 1;

        if (idx != lastIndx) {
            address lastOwner = profileOwners[lastIndx];
            profileOwners[idx] = lastOwner;
            ownerIndex[lastOwner] = idx;
        }

        profileOwners.pop();
        delete ownerIndex[msg.sender];

        emit ProfileCleared(msg.sender);
        return (true);
    }
}
