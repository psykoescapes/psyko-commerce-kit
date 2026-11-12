// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts@5.1.0/token/ERC1155/ERC1155.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts@5.1.0/access/Ownable2Step.sol";

contract PsykoLicense is ERC1155, Ownable2Step {

    mapping(address => bool) public isMinter;

    mapping(uint256 => bool) public transferable;

    mapping(uint256 => string) private _tokenURIs;

    string public constant name = "PSYKO Licence";
    string public constant symbol = "PSYKOLIC";

    event MinterSet(address indexed account, bool allowed);
    event TransferableSet(uint256 indexed id, bool allowed);
    event TokenURISet(uint256 indexed id, string uri);

    error NotMinter();
    error NonTransferable(uint256 id);
    error LengthMismatch();

    constructor(string memory baseURI, address initialOwner) ERC1155(baseURI) Ownable(initialOwner) {}

    modifier onlyMinter() {
        if (!isMinter[msg.sender] && msg.sender != owner()) revert NotMinter();
        _;
    }

    function mint(address to, uint256 id, uint256 amount) external onlyMinter {
        _mint(to, id, amount, "");
    }

    function grant(address[] calldata to, uint256 id) external onlyMinter {
        for (uint256 i = 0; i < to.length; ++i) {
            if (balanceOf(to[i], id) == 0) _mint(to[i], id, 1, "");
        }
    }

    function burn(uint256 id, uint256 amount) external {
        _burn(msg.sender, id, amount);
    }

    function setMinter(address account, bool allowed) external onlyOwner {
        isMinter[account] = allowed;
        emit MinterSet(account, allowed);
    }

    function setTransferable(uint256 id, bool allowed) external onlyOwner {
        transferable[id] = allowed;
        emit TransferableSet(id, allowed);
    }

    function setBaseURI(string calldata newBase) external onlyOwner {
        _setURI(newBase);
    }

    function setTokenURI(uint256 id, string calldata tokenUri) external onlyOwner {
        _tokenURIs[id] = tokenUri;
        emit TokenURISet(id, tokenUri);
        emit URI(tokenUri, id);
    }

    function uri(uint256 id) public view override returns (string memory) {
        string memory u = _tokenURIs[id];
        return bytes(u).length > 0 ? u : super.uri(id);
    }

    function holdsAny(address account, uint256[] calldata ids) external view returns (bool) {
        for (uint256 i = 0; i < ids.length; ++i) {
            if (balanceOf(account, ids[i]) > 0) return true;
        }
        return false;
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override {

        if (from != address(0) && to != address(0)) {
            for (uint256 i = 0; i < ids.length; ++i) {
                if (!transferable[ids[i]]) revert NonTransferable(ids[i]);
            }
        }
        super._update(from, to, ids, values);
    }
}
