// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IUpeg.sol";
import "../svg_generation/UpegMetadata.sol";
import "../svg_generation/IImageParams.sol";
import "../library/RandomLib.sol";
import "../library/IRandomSeedProvider.sol";

/// @dev Allows creating and storing Upegs by owner address.
/// @notice Upeg is a set of data that defines the token appearance.
/// @notice To save storage, Upeg is stored as an encoded uint256 (non-zero).
/// @notice A list of Upeg holders is maintained.
/// Each Upeg has a unique non-zero ID.
/// By ID you can get the encoded Upeg and decode it into UpegMetadata.
contract Upeg is IUpeg {
    using RandomLibrary for Random;

    // all Upegs
    mapping(uint upegId => uint256 seed) _upegs; // encoded Upegs by ID

    // Upegs for each owner
    mapping(address owner => uint) _counts; // Upeg count per owner
    mapping(address owner => mapping(uint index => uint256 upegId)) _ownedUpegs; // Upeg by owner index
    mapping(address owner => mapping(uint upegId => uint index)) _ownedUpegsIndexes; // Upeg indices by ID
    mapping(address owner => mapping(uint upegId => bool isOwn)) _owns; // ownership by Upeg ID

    // Upeg holders list
    mapping(uint index => address user) _holderList;
    mapping(address user => uint index) _holderListNumbers; // holder number in list (0 means not a holder)

    uint _upegsTotalCount; // total Upeg count
    uint _holdersCount; // total holder count
    IRandomSeedProvider public randomSeedProvider; // random seed provider

    /// @dev Image parameters provider (element counts and palette sizes).
    IImageParams public imageParams;

    /// @dev Inserts an existing Upeg (by upegId) into the owner's list.
    /// @notice Seed must already exist in _upegs[upegId].
    function _insertExistingUpegToOwner(address owner, uint upegId) internal {
        // add to owner's list
        _ownedUpegs[owner][_counts[owner]] = upegId;
        _ownedUpegsIndexes[owner][upegId] = _counts[owner];
        _counts[owner]++;
        _owns[owner][upegId] = true;

        // add owner to holder list if not present
        if (!IsHolder(owner)) {
            _holderList[_holdersCount] = owner;
            _holderListNumbers[owner] = ++_holdersCount;
        }
    }

    /// @dev Removes Upeg from owner's list (but does NOT delete the seed).
    function _removeUpegFromOwner(address owner, uint upegId) internal {
        // index of the removed item
        uint idx = _ownedUpegsIndexes[owner][upegId];
        uint lastIdx = _counts[owner] - 1;

        if (idx != lastIdx) {
            // swap-with-last to keep list compact
            uint256 lastId = _ownedUpegs[owner][lastIdx];
            _ownedUpegs[owner][idx] = lastId;
            _ownedUpegsIndexes[owner][lastId] = idx;
        }

        // clear last slot and indices
        delete _ownedUpegs[owner][lastIdx];
        delete _ownedUpegsIndexes[owner][upegId];

        _counts[owner]--;
        _owns[owner][upegId] = false;

        // remove owner from holder list if they own none
        if (_counts[owner] == 0 && IsHolder(owner)) {
            _removeHolder(owner);
        }
    }

    /// @dev Restricts function to the Upeg owner.
    modifier onlyUpegOwner(uint upegId) {
        if (!_owns[msg.sender][upegId]) revert NotUpegOwner();
        _;
    }
    /// @dev Ensures index is valid for the caller's Upeg list.
    modifier onlyMyUpegIndex(uint index) {
        if (index >= _counts[msg.sender]) revert UpegIndexOutOfRange();
        _;
    }

    /// @dev Sets the random seed provider.
    /// @param newRandomSeedProvider Contract implementing IRandomSeedProvider
    function _setRandomSeedProvider(address newRandomSeedProvider) internal {
        randomSeedProvider = IRandomSeedProvider(newRandomSeedProvider);
    }

    /// @dev Creates a random generator state struct.
    function createRandom() internal view returns (Random memory) {
        return Random(randomSeedProvider.randomSeed(), 0);
    }

    /// @dev Sets the image parameters provider.
    /// @param imageParamsProvider Contract implementing IImageParams
    function _setImageParamsProvider(address imageParamsProvider) internal {
        imageParams = IImageParams(imageParamsProvider);
    }

    /// @dev Returns true with probability prob% (0..100).
    function _chance(
        uint prob,
        Random memory random
    ) internal pure returns (bool) {
        return (random.next() % 100) < prob;
    }

    /// @dev Picks id in 1..count (0 if count == 0).
    function _pickId(
        uint count,
        Random memory random
    ) internal pure returns (uint8) {
        if (count == 0) return 0;
        return uint8((random.next() % count) + 1);
    }

    /// @dev Picks a color index in 0..(max-1).
    function _pickColor(
        uint8 max,
        Random memory random
    ) internal pure returns (uint8) {
        if (max == 0) return 0;
        return uint8(random.next() % max);
    }

    function IsHolder(address owner) public view returns (bool) {
        return _holderListNumbers[owner] > 0;
    }

    function UpegsTotalCount() external view returns (uint) {
        return _upegsTotalCount;
    }

    function HoldersCount() external view returns (uint) {
        return _holdersCount;
    }

    function OwnerUpegsCount(address owner) public view returns (uint) {
        return _counts[owner];
    }

    function OwnerUpeg(
        address owner,
        uint index
    ) external view returns (UpegSeedData memory) {
        if (index >= _counts[owner]) revert UpegIndexOutOfRange();
        uint256 id = _ownedUpegs[owner][index];
        return UpegSeedData({id: id, seed: _upegs[id]});
    }

    function OwnerUpegIndex(
        address owner,
        uint upegId
    ) external view returns (uint index) {
        if (!_owns[owner][upegId]) revert NotUpegOwner();
        return _ownedUpegsIndexes[owner][upegId];
    }

    function OwnerOwns(
        address owner,
        uint upegId
    ) external view returns (bool) {
        return _owns[owner][upegId];
    }

    function Holder(uint index) external view returns (address) {
        return _holderList[index];
    }

    function HolderNumber(address owner) external view returns (uint) {
        return _holderListNumbers[owner];
    }

    /// @notice returns a page of upeg IDs and seeds for a given owner
    /// @param owner owner address
    /// @param page zero-based page index
    /// @param pageSize number of items per page
    function OwnerUpegsPage(
        address owner,
        uint page,
        uint pageSize
    ) external view override returns (UpegSeedData[] memory upegs) {
        uint count = _counts[owner];
        if (pageSize == 0) return new UpegSeedData[](0);

        uint start = page * pageSize;
        if (start >= count) return new UpegSeedData[](0);

        uint end = start + pageSize;
        if (end > count) end = count;

        uint len = end - start;
        upegs = new UpegSeedData[](len);
        for (uint i = 0; i < len; i++) {
            uint idx = start + i;
            uint256 inscId = _ownedUpegs[owner][idx];
            upegs[i] = UpegSeedData({id: inscId, seed: _upegs[inscId]});
        }
    }

    /// @dev Hook called before any user-initiated Upeg move (transfer or reorder).
    /// Default no-op; subclasses can enforce constraints (e.g. require Upeg is anchored).
    function _beforeUpegMove(uint upegId) internal virtual {}

    /// @dev Reorders caller's Upeg: upegId goes to newIndex, others shift.
    function ReorderUpeg(
        uint upegId,
        uint newIndex
    ) external virtual override onlyUpegOwner(upegId) onlyMyUpegIndex(newIndex) {
        _beforeUpegMove(upegId);
        uint currentIndex = _ownedUpegsIndexes[msg.sender][upegId];
        if (newIndex == currentIndex) return;

        // take out element
        uint256 id = _ownedUpegs[msg.sender][currentIndex];

        // shift based on direction
        if (newIndex < currentIndex) {
            // shift right: [newIndex .. currentIndex-1] -> +1
            for (uint i = currentIndex; i > newIndex; i--) {
                _ownedUpegs[msg.sender][i] = _ownedUpegs[msg.sender][i - 1];
                _ownedUpegsIndexes[msg.sender][_ownedUpegs[msg.sender][i]] = i;
            }
        } else {
            // newIndex > currentIndex: shift left: [currentIndex+1 .. newIndex] -> -1
            for (uint i = currentIndex; i < newIndex; i++) {
                _ownedUpegs[msg.sender][i] = _ownedUpegs[msg.sender][i + 1];
                _ownedUpegsIndexes[msg.sender][_ownedUpegs[msg.sender][i]] = i;
            }
        }

        // place element into new slot
        _ownedUpegs[msg.sender][newIndex] = id;
        _ownedUpegsIndexes[msg.sender][id] = newIndex;
    }

    /// @dev Swaps upegId with the element at newIndex without shifting (gas-optimized).
    function ReorderUpegPair(
        uint upegId,
        uint newIndex
    ) external virtual override onlyUpegOwner(upegId) onlyMyUpegIndex(newIndex) {
        _beforeUpegMove(upegId);
        uint currentIndex = _ownedUpegsIndexes[msg.sender][upegId];
        if (newIndex == currentIndex) return;

        uint256 otherId = _ownedUpegs[msg.sender][newIndex];

        // swap in array
        _ownedUpegs[msg.sender][newIndex] = upegId;
        _ownedUpegs[msg.sender][currentIndex] = otherId;

        // update indices
        _ownedUpegsIndexes[msg.sender][upegId] = newIndex;
        _ownedUpegsIndexes[msg.sender][otherId] = currentIndex;
    }

    /// @notice Creates a new Upeg for the owner.
    /// @param owner Owner address
    /// @param seed Encoded Upeg value
    function _mintUpeg(address owner, uint256 seed) internal {
        UpegSeedData memory seedData = _createUpeg(owner, seed);
        emit OnUpegMinted(owner, seedData.id);
    }

    /// @notice Creates a new Upeg for the owner.
    /// @param owner Owner address
    function _mintUpeg(address owner, Random memory random) internal {
        _mintUpeg(owner, _nextUpeg(random));
    }

    function _createUpeg(
        address owner,
        uint256 seed
    ) private returns (UpegSeedData memory seedData) {
        uint upegId = ++_upegsTotalCount;
        _upegs[upegId] = seed;
        _insertExistingUpegToOwner(owner, upegId);
        return UpegSeedData({id: upegId, seed: seed});
    }

    /// @notice Generates a random Upeg.
    /// @param random Generator state struct
    function _nextUpeg(
        Random memory random
    ) internal view returns (uint256 seed) {
        // get aggregated parameters (element counts and palette sizes)
        ImageParams memory p = imageParams.getImageParams();

        UpegMetadata memory s;

        // background (100%) — index in 0..backgroundColorsCount-1
        s.background = p.backgroundColorsCount == 0
            ? 0
            : uint8(random.next() % p.backgroundColorsCount);

        // ear (20%)
        if (_chance(20, random)) {
            s.ear = _pickId(p.earCount, random);
            if (s.ear > 0) {
                s.earColor = _pickColor(p.colorsCount, random);
            }
        }

        // mouth (30%)
        if (_chance(30, random)) {
            s.mouth = _pickId(p.mouthCount, random);
            if (s.mouth > 0) {
                s.mouthColor = _pickColor(p.colorsCount, random);
            }
        }

        // crown (80%)
        if (_chance(80, random)) {
            s.crown = _pickId(p.crownCount, random);
            if (s.crown > 0) {
                s.crownColor = _pickColor(p.colorsCount, random);
            }
        }

        // cloth (30%) — uses skin color, no separate color
        if (_chance(30, random)) {
            s.cloth = _pickId(p.clothCount, random);
        }

        // tool (80%)
        if (_chance(80, random)) {
            s.tool = _pickId(p.toolCount, random);
            if (s.tool > 0) {
                s.toolColor = _pickColor(p.colorsCount, random);
            }
        }

        // face (100%)
        s.face = _pickId(p.faceCount, random);

        // reserved1 (100%) — unused slot kept for byte-format compatibility
        s.reserved1 = _pickId(p.reserved1Count, random);

        // eyes (100%)
        s.eyes = _pickId(p.eyesCount, random);
        if (s.eyes > 0) {
            s.eyesColor = _pickColor(p.colorsCount, random);
        }

        // skin (100%)
        s.skin = _pickId(p.skinCount, random);
        if (s.skin > 0) {
            s.skinColor = _pickColor(p.colorsCount, random);
        }

        // reserved2 (100%) — unused slot kept for byte-format compatibility
        s.reserved2 = _pickId(p.reserved2Count, random);
        if (s.reserved2 > 0) {
            s.reserved2Color = _pickColor(p.colorsCount, random);
        }

        // encode struct into uint256
        seed = UpegMetadataLibrary.encode(s);
        return seed;
    }

    /// @notice Removes a Upeg from the owner.
    /// @param owner Owner address
    /// @param upegId Upeg ID
    function _burnUpeg(
        address owner,
        uint upegId
    ) internal returns (uint256 seed) {
        uint256 deletedSeed = _deleteUpeg(owner, upegId);
        emit OnUpegBurned(owner, upegId);
        return deletedSeed;
    }

    function _deleteUpeg(
        address owner,
        uint upegId
    ) internal returns (uint256 seed) {
        // remove ownership and delete from owner's list
        _removeUpegFromOwner(owner, upegId);

        // delete seed
        seed = _upegs[upegId];
        delete _upegs[upegId];

        return seed;
    }

    /// @notice Transfers a Upeg from one owner to another.
    /// @param from Sender address
    /// @param to Recipient address
    /// @param upegId Upeg ID
    function _transferUpeg(address from, address to, uint upegId) internal {
        // remove upegId from sender list, keep seed
        _removeUpegFromOwner(from, upegId);
        // insert same upegId into receiver list (ID preserved)
        _insertExistingUpegToOwner(to, upegId);
        emit OnUpegTransfer(from, to, upegId);
    }

    /// @notice Removes a holder from the global holder list.
    /// @param owner Owner address
    function _removeHolder(address owner) internal {
        // _holderListNumbers is 1-based; _holderList indices are 0-based
        uint idx = _holderListNumbers[owner] - 1;
        uint lastIdx = _holdersCount - 1;

        // fill the gap: move the last entry into the removed slot (swap-with-last)
        if (idx != lastIdx) {
            address lastHolder = _holderList[lastIdx];
            _holderList[idx] = lastHolder;
            _holderListNumbers[lastHolder] = idx + 1; // update 1-based slot number
        }

        delete _holderList[lastIdx];
        delete _holderListNumbers[owner];
        _holdersCount--;
    }

    function transferUpeg(
        address to,
        uint upegId
    ) external virtual override onlyUpegOwner(upegId) {
        _beforeUpegMove(upegId);
        _transferUpeg(msg.sender, to, upegId);
        _afterUpegTransferred(msg.sender, to, upegId);
    }

    function transferUpegsList(
        address to,
        uint[] calldata upegIds
    ) external virtual override {
        uint len = upegIds.length;
        if (len == 0) return;

        for (uint i = 0; i < len; ++i) {
            if (!_owns[msg.sender][upegIds[i]]) revert NotUpegOwner();
            _beforeUpegMove(upegIds[i]);
            _transferUpeg(msg.sender, to, upegIds[i]);
        }

        _afterUpegsListTransferred(msg.sender, to, upegIds);
    }

    function _afterUpegTransferred(
        address from,
        address to,
        uint upegId
    ) internal virtual {}

    function _afterUpegsListTransferred(
        address from,
        address to,
        uint[] calldata upegIds
    ) internal virtual {}
}
