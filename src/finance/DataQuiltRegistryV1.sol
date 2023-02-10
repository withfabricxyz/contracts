// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./CrowdFinancingV1.sol";

/**
 *
 * @title DataQuilt NFT Contract for Fabric Campaigns
 * @author Dan Simpson
 *
 * ERC721 + Metadata, with custom minting functions for users who have contributed to
 * a Fabric campaign.
 *
 */
contract DataQuiltRegistryV1 is ERC721 {
    // Base URI for which we generate URIs for NFTs
    string private _baseUri;

    // Campaign specific double mint guard
    mapping(address => mapping(address => bool)) private _campaignMints;

    /**
     * @param name the name of the token
     * @param symbol the symbol of hte token
     * @param baseUri the base URI, such as: `https://somehost.com/`
     */
    constructor(string memory name, string memory symbol, string memory baseUri) ERC721(name, symbol) {
        _baseUri = baseUri;
    }

    /**
     * Mint a contribution token using a tokenId, which encodes the campaign address + encoded variant
     *
     * @param tokenId the id of the token, which is an abi packed [campaign address, uint64(0), uint32(variant)]
     */
    function mintContributionToken(uint256 tokenId) external {
        address account = msg.sender;
        address campaignAddress = address(uint160(tokenId >> 96));
        require(canMint(campaignAddress), "Err: already minted or deposits not found");
        _safeMint(account, tokenId);
        _campaignMints[campaignAddress][account] = true;
    }

    function canMint(address campaignAddress) public view returns (bool) {
        if (_campaignMints[campaignAddress][msg.sender]) {
            return false;
        }
        // Is it possible to verify this is a CFV1 contract?
        return CrowdFinancingV1(payable(campaignAddress)).depositedAmount(msg.sender) > 0;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }
}
