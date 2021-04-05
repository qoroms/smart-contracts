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

    struct ZoraSwap {
        address sellerAddr;
        address sellerTokenAddr;
        uint256 sellerTokenId;
        uint256 sellerTokenAmount;
        TokenType sellerTokenType;

        address buyerTokenAddr;
        uint256 buyerTokenId;
        uint256 buyerTokenAmount;
        TokenType buyerTokenType;

        uint256 leftAmount;
        bool isActive;        
    }

    uint256 public listIndex;
    mapping(uint256 => ZoraSwap) public swapList;

    bool public emergencyStop;

    address public owner;
    address public feeCollector;

    address public ZORA = "0xd8e3fb3b08eba982f2754988d70d57edc0055ae6";

    event SwapCreated(
        uint256 listIndex,
        address sellerTokenAddr,
        uint256 sellerTokenId,
        uint256 sellerTokenAmount,
        uint256 sellerTokenType,
        address buyerTokenAddr,
        uint256 buyerTokenId,
        uint256 buyerTokenAmount,
        uint256 buyerTokenType);
    event NFTSwapped(uint256 listIndex, uint256 leftAmount);
    event SwapClosed(uint256 listIndex);


    modifier onlyListOwner(uint256 listId) {
        require(
            swapList[listId].sellerAddr == msg.sender,
            "ZoraSwap: not your list"
        );
        _;
    }

    modifier onlyNotEmergency() {
        require(emergencyStop == false, "ZoraSwap: emergency stop");
        _;
    }

    constructor() public {
        originCreator = msg.sender;
        feeCollector = msg.sender;
        listIndex = 0;
        emergencyStop = false;
    }

    function clearEmergency() external onlyOwner {
        emergencyStop = true;
    }

    function stopEmergency() external onlyOwner {
        emergencyStop = false;
    }

    function createSwap(
        address sellerTokenAddr,
        uint256 sellerTokenId,
        uint256 sellerTokenAmount,
        uint256 sellerTokenType,
        address buyerTokenAddr,
        uint256 buyerTokenId,
        uint256 buyerTokenAmount,
        uint256 buyerTokenType
    ) external payable onlyNotEmergency {
        if (sellerTokenType == uint256(TokenType.T1155)) {
            IERC1155 _t1155Contract = IERC1155(sellerTokenAddr);
            require(
                _t1155Contract.balanceOf(msg.sender, sellerTokenId) >=
                    sellerTokenAmount,
                "ZoraSwap: Seller do not have nft"
            );
            require(
                _t1155Contract.isApprovedForAll(
                    msg.sender,
                    address(this)
                ) == true,
                "ZoraSwap: Must be approved"
            );
        } else if(sellerTokenType == uint256(TokenType.T721)) {
            require(
                sellerTokenAmount == 1,
                "ZoraSwap: Don't support T721 Batch Swap"
            );
            IERC721 _t721Contract = IERC721(sellerTokenAddr);
            require(
                _t721Contract.ownerOf(sellerTokenId) == msg.sender,
                "ZoraSwap: Seller do not have nft"
            );
            require(
                _t721Contract.isApprovedForAll(
                    msg.sender,
                    address(this)
                ) == true,
                "ZoraSwap: Must be approved"
            );
        } else {
            revert("Token Type is Invalid");
        }

        IERC20 ZORA_CONTRACT = IERC20(ZORA);
        uint256 zoraBalance = ZORA_CONTRACT.balanceOf(msg.sender);
        if (zoraBalance >= 5.mul(10**9)) {
            require(msg.value >= 0, "ZoraSwap: out of fee");
        } else if (zoraBalance >= 15.mul(10**8)) {
            require(msg.value >= 3.mul(10**16), "ZoraSwap: out of fee");
        } else {
            require(msg.value >= 5.mul(10**16), "ZoraSwap: out of fee");
        }

        uint256 _index = listIndex;
        swapList[_index].sellerAddr = msg.sender;
        swapList[_index].sellerTokenAddr = sellerTokenAddr;
        swapList[_index].sellerTokenId = sellerTokenId;
        swapList[_index].sellerTokenAmount = sellerTokenAmount;
        swapList[_index].sellerTokenType = TokenType(sellerTokenType);
        swapList[_index].buyerTokenAddr = buyerTokenAddr;
        swapList[_index].buyerTokenId = buyerTokenId;
        swapList[_index].buyerTokenAmount = buyerTokenAmount;
        swapList[_index].buyerTokenType = TokenType(buyerTokenType);
        swapList[_index].leftAmount = sellerTokenAmount;
        swapList[_index].isAcive = true;
        
        _incrementListId();
        emit SwapCreated(
            _index,
            sellerTokenAddr,
            sellerTokenId,
            sellerTokenAmount,
            sellerTokenType,
            buyerTokenAddr,
            buyerTokenId,
            buyerTokenAmount,
            buyerTokenType
        );
    }

    function _sendToken(
        TokenType tokenType,
        address contractAddr,
        uint256 tokenId,
        address from,
        address to,
        uint256 amount,
        uint256 listId
    ) internal {
        if (tokenType == TokenType.T1155) {
            IERC1155(contractAddr).safeTransferFrom(from, to, tokenId, amount, "");
        } else if (tokenType == TokenType.T721) {
            IERC721(contractAddr).safeTransferFrom(from, to, tokenId, "");
        } else {
            IERC20(contractAddr).transferFrom(from, to, swapList[listId].sellerTokenAmount * amount);
        }
    }

    function swapNFT(
        uint256 listId,
        uint256 tokenAmount
    ) external payable onlyNotEmergency {
        require(tokenAmount >= 1, "ZoraSwap: expected more than 1 amount");
        address lister = swapList[listId].sellerAddr;
        
        require(swapList[listId].leftAmount >= tokenAmount, 
            "ZoraSwap: exceed current supply"
        );

        require(swapList[listId].isActive == true, 
            "ZoraSwap: Swap is closed"
        );

        if(swapList[listId].buyerTokenType == uint256(TokenType.T1155)) {
            IERC1155 _t1155Contract = IERC1155(swapList[listId].buyerTokenAddr);
            require(
                _t1155Contract.balanceOf(msg.sender, swapList[listId].buyerTokenId) >= tokenAmount,
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
                swapList[listId].buyerTokenId,
                tokenAmount,
                ""
            );
        } else if(swapList[listId].buyerTokenType == uint256(TokenType.T721)) {
            IERC721 _t721Contract = IERC721(swapList[listId].buyerTokenAddr);
            require(
                tokenAmount == 1,
                "ZoraSwap: Don't support T721 Batch Swap"
            );
            require(
                _t721Contract.ownerOf(swapList[listId].buyerTokenId) == msg.sender,
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
                swapList[listId].buyerTokenId,
                ""
            );
        } else if(swapList[listId].buyerTokenType == uint256(TokenType.T20)) {
            IERC20 _t20Contract = IERC20(swapList[listId].buyerTokenAddr);
            uint256 amount = swapList[listId].buyerTokenAmount.mul(tokenAmount);
            require(
                _t20Contract.balanceOf(msg.sender) >= amount,
                "ZoraSwap: Do not enough funds"
            );
            require(
                _t20Contract.allowance(msg.sender, address(this)) >=
                    amount,
                "ZoraSwap: Must be approved"
            );
            _t20Contract.transferFrom(msg.sender, lister, amount);
        } else {
            revert("ZoraSwap: Buyer's Token Type is Invalid");
        }
        _sendToken(
            swapList[listId].sellerTokenType,
            swapList[listId].sellerTokenAddr,
            swapList[listId].sellerTokenId,
            lister,
            msg.sender,
            tokenAmount,
            listId
        );
        swapList[listId].leftAmount = swapList[listId].leftAmount.sub(tokenAmount);
        if (swapList[listId].leftAmount == 0) {
            swapList[listId].isAcive = false;
        }
        emit NFTSwapped(listId, swapList[listId].leftAmount);
    }

    function closeList(uint256 listId)
        external
        onlyListOwner(listId)
    {
        swapList[listId].isActive = false;
        emit NFTClosed(listId);
    }

    function _incrementListId() internal {
        listIndex = listIndex.add(1);
    }
}