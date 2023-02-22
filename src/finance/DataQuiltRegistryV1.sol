// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./CrowdFinancingV1.sol";

/**
 *
 * @title DataQuilt NFT Contract for Fabric Campaigns
 * @author Fabric Inc.
 *
 * ERC721 + Metadata, with custom minting functions for accounts which contributed to
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
     * Mint a contribution token using a tokenId, which encodes the campaign address and pattern configuration
     *
     * @param tokenId the id of the token, which is an abi packed [campaign address, uint64(0), uint32(variant)]
     */
    function mint(uint256 tokenId) external {
        address account = msg.sender;
        address campaignAddress = address(uint160(tokenId >> 96));
        require(canMint(campaignAddress), "Err: already minted or deposits not found");
        _safeMint(account, tokenId);
        _campaignMints[campaignAddress][account] = true;
    }

    /**
     * Check if an account can mint a token for a campaign
     *
     * @param campaignAddress the address of the campaign
     *
     * @return true if the account can mint a token for the campaign
     */
    function canMint(address campaignAddress) public view returns (bool) {
        if (_campaignMints[campaignAddress][msg.sender]) {
            return false;
        }
        // Is it possible to verify this is a CFV1 contract?
        return CrowdFinancingV1(payable(campaignAddress)).balanceOf(msg.sender) > 0;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseUri;
    }
}
