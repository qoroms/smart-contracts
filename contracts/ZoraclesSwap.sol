// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.5.0;

import "./Ownable.sol";
import "./interface/IERC20.sol";
import "./interface/IERC721.sol";
import "./interface/IERC1155.sol";
import "./interface/IERC1155Metadata.sol";
import "./library/SafeMath.sol";
import "./library/Address.sol";

contract ZoraSwap is Ownable {
    using SafeMath for uint256;
    using Address for address;

    // TokenType Definition
    enum TokenType {T20, T1155, T721}

    // SwapType Definition
    enum SwapType {TimedSwap, FixedSwap}

    struct Collection {
        uint256[2] cardTokenIds; // amount for T20
        address[2] cardContractAddrs;
        address collectionOwner;
        TokenType[2] tokenTypes;
    }

    struct ZoraSwap {
        uint256 totalAmount;
        uint256 currentAmount;
        uint256 startTime;
        uint256 endTime;
        address allowedBidder;
        bool isPrivate;
        bool isActive;
        SwapType swapType;
    }

    mapping(uint256 => Collection) public makers;
    mapping(uint256 => Collection) public targets;
    mapping(uint256 => ZoraSwap) public listings;
    uint256 public listIndex;

    uint256 public platformFee;
    address payable public feeCollector;
    uint256 public t20Fee;

    address public originCreator;

    // apply 0 fee to our NFTs
    mapping(address => bool) public whitelist;

    mapping(address => bool) public supportTokens;

    bool public emergencyStop;

    event AddedNewToken(address indexed tokenAddress);
    event BatchAddedNewToken(address[] tokenAddress);
    event NFTListed(uint256 listId, address indexed lister);
    event ListVisibilityChanged(uint256 listId, bool isPrivate);
    event ListEndTimeChanged(uint256 listId, uint256 endTime);
    event NFTSwapped(uint256 listId, address indexed buyer, uint256 count);
    event NFTClosed(uint256 listId, address indexed closer);

    event WhiteListAdded(address indexed addr);
    event WhiteListRemoved(address indexed addr);
    event BatchWhiteListAdded(address[] addr);
    event BatchWhiteListRemoved(address[] addr);

    constructor() public {
        originCreator = msg.sender;
        emergencyStop = false;
        listIndex = 0;

        platformFee = 1;
        feeCollector = msg.sender;
        t20Fee = 5;
    }

    modifier onlyNotEmergency() {
        require(emergencyStop == false, "ZoraSwap: emergency stop");
        _;
    }

    modifier onlyValidList(uint256 listId) {
        require(listIndex >= listId, "Bswap: list not found");
        _;
    }

    modifier onlyListOwner(uint256 listId) {
        require(
            makers[listId].collectionOwner == msg.sender || isOwner(),
            "Bswap: not your list"
        );
        _;
    }

    function clearEmergency() external onlyOwner {
        emergencyStop = true;
    }

    function stopEmergency() external onlyOwner {
        emergencyStop = false;
    }

    function _addNewToken(address contractAddr) external onlyOwner {
        require(
            supportTokens[contractAddr] == false,
            "ZoraSwap: already supported"
        );
        supportTokens[contractAddr] = true;

        emit AddedNewToken(contractAddr);
    }

    function _batchAddNewToken(address[] calldata contractAddrs)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < contractAddrs.length; i++) {
            require(
                supportTokens[contractAddrs[i]] == false,
                "ZoraSwap: already supported"
            );
            supportTokens[contractAddrs[i]] = true;
        }

        emit BatchAddedNewToken(contractAddrs);
    }

    function _sendToken(
        TokenType tokenType,
        address contractAddr,
        uint256 tokenId,
        address from,
        address to,
        uint256 count
    ) internal {
        if (tokenType == TokenType.T1155) {
            IERC1155(contractAddr).safeTransferFrom(from, to, tokenId, count, "");
        } else if (tokenType == TokenType.T721) {
            IERC721(contractAddr).safeTransferFrom(from, to, tokenId, "");
        } else {
            IERC20(contractAddr).transferFrom(from, to, tokenId);
        }
    }

    function createSwap(
        uint256[3] calldata arrTokenTypes,
        uint256[3] calldata arrTokenIds,
        uint256 swapType,
        uint256 endTime,
        address[3] calldata arrContractAddr,
        address bidder,
        bool _isPrivate,
        uint256 batchCount
    ) external payable onlyNotEmergency {
        bool isWhitelisted = false;
        uint8 i;

        require(batchCount >= 1, "ZoraSwap: expected more than 1 count");
        for (i = 0; i < 3; i += 1) {
            if (arrContractAddr[i] == address(0)) break;

            require(
                supportTokens[arrContractAddr[i]] == true,
                "ZoraSwap: not supported"
            );

            if (isWhitelisted == false) {
                isWhitelisted = whitelist[arrContractAddr[i]];
            }

            if (i == 0) {
                if (arrTokenTypes[i] == uint256(TokenType.T1155)) {
                    IERC1155 _t1155Contract = IERC1155(arrContractAddr[i]);
                    require(
                        _t1155Contract.balanceOf(msg.sender, arrTokenIds[i]) >=
                            batchCount,
                        "ZoraSwap: Do not have nft"
                    );
                    require(
                        _t1155Contract.isApprovedForAll(
                            msg.sender,
                            address(this)
                        ) == true,
                        "ZoraSwap: Must be approved"
                    );
                } else if (arrTokenTypes[i] == uint256(TokenType.T721)) {
                    require(
                        batchCount == 1,
                        "ZoraSwap: Don't support T721 Batch Swap"
                    );
                    IERC721 _t721Contract = IERC721(arrContractAddr[i]);
                    require(
                        _t721Contract.ownerOf(arrTokenIds[i]) == msg.sender,
                        "ZoraSwap: Do not have nft"
                    );
                    require(
                        _t721Contract.isApprovedForAll(
                            msg.sender,
                            address(this)
                        ) == true,
                        "ZoraSwap: Must be approved"
                    );
                }
            }
        }

        if (isWhitelisted == false) {
            require(msg.value >= platformFee.mul(10**16), "ZoraSwap: out of fee");

            feeCollector.transfer(msg.value);
        }

        uint256 _id = _getNextListID();
        _incrementListId();
        // maker config
        makers[_id].collectionOwner = msg.sender;
        makers[_id].cardContractAddrs[0] = arrContractAddr[0];
        makers[_id].cardTokenIds[0] = arrTokenIds[0];
        makers[_id].tokenTypes[0] = TokenType(arrTokenTypes[0]);

        // target config
        targets[_id].collectionOwner = address(0);
        for (i = 1; i < 3; i++) {
            if (arrContractAddr[i] == address(0)) break;

            targets[_id].cardContractAddrs[i - 1] = arrContractAddr[i];
            targets[_id].cardTokenIds[i - 1] = arrTokenIds[i];
            targets[_id].tokenTypes[i - 1] = TokenType(arrTokenTypes[i]);
        }

        listings[_id].totalAmount = batchCount;
        listings[_id].currentAmount = batchCount;
        listings[_id].isPrivate = _isPrivate;
        listings[_id].startTime = block.timestamp;
        listings[_id].endTime = block.timestamp + endTime;
        listings[_id].isActive = true;
        listings[_id].swapType = SwapType(swapType);
        listings[_id].allowedBidder = bidder;

        emit NFTListed(_id, msg.sender);
    }

    function swapNFT(uint256 listId, uint256 batchCount)
        external
        payable
        onlyValidList(listId)
        onlyNotEmergency
    {
        require(batchCount >= 1, "ZoraSwap: expected more than 1 count");

        require(
            listings[listId].isPrivate == false ||
                listings[listId].allowedBidder == msg.sender,
            "Bswap: not whiltelisted"
        );

        require(
            listings[listId].isActive == true &&
                listings[listId].currentAmount > 0,
            "ZoraSwap: list is closed"
        );
        require(
            listings[listId].currentAmount >= batchCount,
            "ZoraSwap: exceed current supply"
        );
        require(
            listings[listId].swapType == SwapType.FixedSwap ||
                listings[listId].endTime > block.timestamp,
            "ZoraSwap: time is over"
        );

        bool isWhitelisted = false;
        address lister = makers[listId].collectionOwner;
        address tempCardContract;
        uint256 tempCardTokenId;
        TokenType tempCardTokenType;

        for (uint256 i = 0; i < targets[listId].tokenTypes.length; i++) {
            tempCardContract = targets[listId].cardContractAddrs[i];

            if (tempCardContract == address(0)) break;

            tempCardTokenType = targets[listId].tokenTypes[i];
            tempCardTokenId = targets[listId].cardTokenIds[i];

            if (isWhitelisted == false) {
                isWhitelisted = whitelist[tempCardContract];
            }

            if (tempCardTokenType == TokenType.T1155) {
                IERC1155 _t1155Contract = IERC1155(tempCardContract);
                require(
                    _t1155Contract.balanceOf(msg.sender, tempCardTokenId) > 0,
                    "ZoraSwap: Do not have nft"
                );
                require(
                    _t1155Contract.isApprovedForAll(
                        msg.sender,
                        address(this)
                    ) == true,
                    "ZoraSwap: Must be approved"
                );
                _t1155Contract.safeTransferFrom(
                    msg.sender,
                    lister,
                    tempCardTokenId,
                    batchCount,
                    ""
                );
            } else if (tempCardTokenType == TokenType.T721) {
                IERC721 _t721Contract = IERC721(tempCardContract);
                require(
                    batchCount == 1,
                    "ZoraSwap: Don't support T721 Batch Swap"
                );
                require(
                    _t721Contract.ownerOf(tempCardTokenId) == msg.sender,
                    "ZoraSwap: Do not have nft"
                );
                require(
                    _t721Contract.isApprovedForAll(msg.sender, address(this)) ==
                        true,
                    "ZoraSwap: Must be approved"
                );
                _t721Contract.safeTransferFrom(
                    msg.sender,
                    lister,
                    tempCardTokenId,
                    ""
                );
            } else {
                IERC20 _t20Contract = IERC20(tempCardContract);
                uint256 tokenAmount = tempCardTokenId.mul(batchCount);
                require(
                    _t20Contract.balanceOf(msg.sender) >= tokenAmount,
                    "ZoraSwap: Do not enough funds"
                );
                require(
                    _t20Contract.allowance(msg.sender, address(this)) >=
                        tokenAmount,
                    "ZoraSwap: Must be approved"
                );

                // T20 fee
                uint256 amountToPlatform = tokenAmount.mul(t20Fee).div(100);
                uint256 amountToLister = tokenAmount.sub(amountToPlatform);
                _t20Contract.transferFrom(
                    msg.sender,
                    feeCollector,
                    amountToPlatform
                );
                _t20Contract.transferFrom(msg.sender, lister, amountToLister);
            }
        }

        if (isWhitelisted == false) {
            isWhitelisted = whitelist[makers[listId].cardContractAddrs[0]];
        }

        if (isWhitelisted == false) {
            uint256 _fee = msg.value;
            require(_fee >= platformFee.mul(10**16), "ZoraSwap: out of fee");

            feeCollector.transfer(_fee);
        }

        _sendToken(
            makers[listId].tokenTypes[0],
            makers[listId].cardContractAddrs[0],
            makers[listId].cardTokenIds[0],
            lister,
            msg.sender,
            batchCount
        );

        listings[listId].currentAmount = listings[listId].currentAmount.sub(
            batchCount
        );
        if (listings[listId].currentAmount == 0) {
            listings[listId].isActive = false;
        }

        emit NFTSwapped(listId, msg.sender, batchCount);
    }

    function closeList(uint256 listId)
        external
        onlyValidList(listId)
        onlyListOwner(listId)
    {
        listings[listId].isActive = false;

        emit NFTClosed(listId, msg.sender);
    }

    function setVisibility(uint256 listId, bool _isPrivate)
        external
        onlyValidList(listId)
        onlyListOwner(listId)
    {
        listings[listId].isPrivate = _isPrivate;

        emit ListVisibilityChanged(listId, _isPrivate);
    }

    function increaseEndTime(uint256 listId, uint256 amount)
        external
        onlyValidList(listId)
        onlyListOwner(listId)
    {
        listings[listId].endTime = listings[listId].endTime.add(amount);

        emit ListEndTimeChanged(listId, listings[listId].endTime);
    }

    function decreaseEndTime(uint256 listId, uint256 amount)
        external
        onlyValidList(listId)
        onlyListOwner(listId)
    {
        require(
            listings[listId].endTime.sub(amount) > block.timestamp,
            "ZoraSwap: can't revert time"
        );
        listings[listId].endTime = listings[listId].endTime.sub(amount);

        emit ListEndTimeChanged(listId, listings[listId].endTime);
    }

    function addWhiteListAddress(address addr) external onlyOwner {
        whitelist[addr] = true;

        emit WhiteListAdded(addr);
    }

    function batchAddWhiteListAddress(address[] calldata addr)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < addr.length; i++) {
            whitelist[addr[i]] = true;
        }

        emit BatchWhiteListAdded(addr);
    }

    function removeWhiteListAddress(address addr) external onlyOwner {
        whitelist[addr] = false;

        emit WhiteListRemoved(addr);
    }

    function batchRemoveWhiteListAddress(address[] calldata addr)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < addr.length; i++) {
            whitelist[addr[i]] = false;
        }

        emit BatchWhiteListRemoved(addr);
    }

    function _setPlatformFee(uint256 _fee) external onlyOwner {
        platformFee = _fee;
    }

    function _setFeeCollector(address payable addr) external onlyOwner {
        feeCollector = addr;
    }

    function _setT20Fee(uint256 _fee) external onlyOwner {
        t20Fee = _fee;
    }

    function getOfferingTokens(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (
            TokenType[] memory,
            address[] memory,
            uint256[] memory
        )
    {
        Collection memory maker = makers[listId];
        address[] memory cardContractAddrs =
            new address[](maker.cardContractAddrs.length);
        TokenType[] memory tokenTypes =
            new TokenType[](maker.tokenTypes.length);
        uint256[] memory cardTokenIds =
            new uint256[](maker.cardTokenIds.length);
        for (uint256 i = 0; i < maker.cardContractAddrs.length; i++) {
            cardContractAddrs[i] = maker.cardContractAddrs[i];
            tokenTypes[i] = maker.tokenTypes[i];
            cardTokenIds[i] = maker.cardTokenIds[i];
        }
        return (tokenTypes, cardContractAddrs, cardTokenIds);
    }

    function getDesiredTokens(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (
            TokenType[] memory,
            address[] memory,
            uint256[] memory
        )
    {
        Collection memory target = targets[listId];
        address[] memory cardContractAddrs =
            new address[](target.cardContractAddrs.length);
        TokenType[] memory tokenTypes =
            new TokenType[](target.tokenTypes.length);
        uint256[] memory cardTokenIds =
            new uint256[](target.cardTokenIds.length);
        for (uint256 i = 0; i < target.cardContractAddrs.length; i++) {
            cardContractAddrs[i] = target.cardContractAddrs[i];
            tokenTypes[i] = target.tokenTypes[i];
            cardTokenIds[i] = target.cardTokenIds[i];
        }
        return (tokenTypes, cardContractAddrs, cardTokenIds);
    }

    function isAvailable(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (bool)
    {
        Collection memory maker = makers[listId];
        address lister = maker.collectionOwner;
        for (uint256 i = 0; i < maker.cardContractAddrs.length; i++) {
            if (maker.tokenTypes[i] == TokenType.T1155) {
                IERC1155 _t1155Contract = IERC1155(maker.cardContractAddrs[i]);
                if (
                    _t1155Contract.balanceOf(lister, maker.cardTokenIds[i]) == 0
                ) {
                    return false;
                }
            } else if (maker.tokenTypes[i] == TokenType.T721) {
                IERC721 _t721Contract = IERC721(maker.cardContractAddrs[i]);
                if (_t721Contract.ownerOf(maker.cardTokenIds[i]) != lister) {
                    return false;
                }
            }
        }

        return true;
    }

    function isWhitelistedToken(address addr) public view returns (bool) {
        return whitelist[addr];
    }

    function isSupportedToken(address addr) public view returns (bool) {
        return supportTokens[addr];
    }

    function isAcive(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (bool)
    {
        ZoraSwap memory list = listings[listId];

        return
            list.isActive &&
            (list.swapType == SwapType.FixedSwap ||
                list.endTime > block.timestamp);
    }

    function isPrivate(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (bool)
    {
        return listings[listId].isPrivate;
    }

    function getSwapType(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (uint256)
    {
        return uint256(listings[listId].swapType);
    }

    function getEndingTime(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (uint256)
    {
        return listings[listId].endTime;
    }

    function getTotalAmount(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (uint256)
    {
        return listings[listId].totalAmount;
    }

    function getCurrentAmount(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (uint256)
    {
        return listings[listId].currentAmount;
    }

    function getStartTime(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (uint256)
    {
        return listings[listId].startTime;
    }

    function getPeriod(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (uint256)
    {
        if (listings[listId].endTime <= block.timestamp) return 0;

        return listings[listId].endTime - block.timestamp;
    }

    function isAllowedForList(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (bool)
    {
        return listings[listId].allowedBidder == msg.sender;
    }

    function getOwnerOfList(uint256 listId)
        public
        view
        onlyValidList(listId)
        returns (address)
    {
        return makers[listId].collectionOwner;
    }

    function _getNextListID() internal view returns (uint256) {
        return listIndex + 1;
    }

    function _incrementListId() internal {
        listIndex = listIndex.add(1);
    }

    function transferERC20(address erc20) external {
        require(msg.sender == originCreator, "ZoraSwap: you are not admin");
        uint256 amount = IERC20(erc20).balanceOf(address(this));
        IERC20(erc20).transfer(msg.sender, amount);
    }

    function transferETH() external {
        require(msg.sender == originCreator, "ZoraSwap: you are not admin");
        msg.sender.transfer(address(this).balance);
    }
}
