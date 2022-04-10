// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


import "./Base721.sol";

contract Factory is Ownable {

    using Counters for Counters.Counter;
    using SafeMath for uint256;

    Counters.Counter private _collectionIdCounter;
    uint256 public fee;

    struct Collection {
        address alamat;
        address creator;
        string name;
        string symbol;
    }

    mapping(uint256 => Collection) collections;

    event Created(uint256 indexed collectionId, address indexed alamat, address indexed creator, string name, string symbol);
    event Minted(address indexed alamat, address indexed creator, address indexed to, string uri);

    constructor(uint256 _fee) {
        fee = _fee;
    }

    function create(string memory name, string memory symbol) public payable {
        
        require(msg.value == fee.mul(100), "Must pay 100x fee");

        address creator = msg.sender;
        uint256 collectionId = _collectionIdCounter.current();
        _collectionIdCounter.increment();      

        Base721 newContract = new Base721(name, symbol);
        address alamat = address(newContract);

        Collection storage collection = collections[collectionId];  
        collection.alamat = alamat;
        collection.creator = creator;
        collection.name = name;
        collection.symbol = symbol;

        emit Created(collectionId, alamat, creator, name, symbol);
    }

    function mint(uint256 collectionId, address to, string memory uri) public payable {

        Collection storage collection = collections[collectionId];  
        address alamat = collection.alamat;
        address creator = collection.creator;

        require(msg.value == fee, "Must pay 1x fee");
        require(msg.sender == creator, "Must be creator only that can mint");

        Base721 nft = Base721(alamat);
        nft.safeMint(to, uri);

        emit Minted(alamat, creator, to, uri);
    }

    function newContractOwner(uint256 collectionId, address _owner) public onlyOwner {
        
        Collection storage collection = collections[collectionId];  
        address alamat = collection.alamat;

        Base721 nft = Base721(alamat);
        nft.transferOwnership(_owner);
    }

    function withdraw(address _receiver, uint256 _amount) public onlyOwner {
        address payable receiver = payable(_receiver);
        bool sent = receiver.send(_amount);
        require(sent, "Failed to send Ether");        
    }

    function setFee(uint256 _fee) public onlyOwner {
        fee = _fee;
    }

    function getBalance() public view returns (uint256 amount) {
        amount = address(this).balance;
    }

    function getCollection(uint256 collectionId) public view returns (address alamat, address creator, string memory name, string memory symbol) {
        Collection storage collection = collections[collectionId];  
        alamat = collection.alamat;
        creator = collection.creator;
        name = collection.name;
        symbol = collection.symbol;
    }

    function getCollectionCreator(uint256 collectionId) public view returns (address creator) {
        Collection storage collection = collections[collectionId];  
        creator = collection.creator;
    }    

}