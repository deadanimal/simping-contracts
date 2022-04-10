// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


import "./Factory.sol";

interface IMLMRegistrar {
    function downlineCount(address) external view returns (uint256);
    function getUplines(address) external view returns (address, address, address, address, address);
    function register(address) external;
    function registered(address) external view returns (bool);
    function remove() external;
    function replace(address) external;
    function uplineForUser(address) external view returns (address);
}


contract Market is Ownable {

    using Counters for Counters.Counter;
    using SafeMath for uint256;

    uint256 public cancelFee; // absolute amount
    uint256 public commissionFee; // % in terms of 1000
    uint256 public minimumPrice; // absolute amount

    Factory public factory;
    IMLMRegistrar public registrar;

    Counters.Counter private _saleIdCounter;
    Counters.Counter private _auctionIdCounter;
    Counters.Counter private _bidIdCounter;

    mapping(uint256 => uint256) royaltyPercent;
    mapping(uint256 => bool) royaltySet;

    struct Sale {
        address seller;
        address buyer;
        uint256 price;

        uint256 collectionId;
        address alamat;
        uint256 tokenId;
    }

    struct Auction {
        address auctioner;
        uint256 minimumPrice;

        uint256 highestBid;
        bool bidAccepted;

        uint256 collectionId;
        address alamat;
        uint256 tokenId;
    }    

    struct Bid {
        uint256 auctionId;
        address bidder;
        uint256 amount;
    }        

    mapping(uint256 => Sale) sales;
    mapping(uint256 => Auction) auctions;
    mapping(uint256 => Bid) bids;
    

    event ForSale(uint256 indexed saleId, address indexed seller, uint256 price);
    event NotForSale (uint256 indexed saleId, address indexed seller);
    event SaleCompleted(uint256 indexed saleId, address indexed buyer, address indexed seller, uint256 price);

    event SendAmount(address indexed sender, address indexed receiver, uint256 amount, uint256 indexed sendReason);

    event BidCreated(uint256 indexed bidId, uint256 indexed auctionId, address indexed bidder, uint256 amount);
    event AuctionCreated(uint256 indexed auctionId, address indexed auctioner, uint256 amount);
    event AuctionCompleted(uint256 indexed auctionId, address indexed auctioner, address indexed bidder, uint256 amount);

    constructor(address _factory, address _registrar, uint256 _cancelFee, uint256 _commissionFee, uint256 _minimumPrice) {
        factory = Factory(_factory);
        registrar = IMLMRegistrar(_registrar);
        cancelFee = _cancelFee;
        commissionFee = _commissionFee;
        minimumPrice = _minimumPrice;
    }

    function initialise(uint256 collectionId, uint256 _royaltyPercent) public {
        address creator = factory.getCollectionCreator(collectionId);
        
        require(creator == msg.sender, "Initialiser must be creator");
        require(_royaltyPercent >= 1 || _royaltyPercent <= 1500, ">= 0.01 and <= 15.00");
        require(royaltySet[collectionId] == false, "Royalty must not be set");
        
        royaltyPercent[collectionId] = _royaltyPercent;
        royaltySet[collectionId] = true;
    }

    function buy(uint256 saleId) public payable {

        Sale memory sale = sales[saleId];       

        IERC721 nft = IERC721(sale.alamat);
        uint256 buyPrice = msg.value;

        require(buyPrice >= sale.price, "Pay the price set or more");
        require(sale.buyer == address(0), "Must not have existing buyer");

        uint256 amountRoyalty = buyPrice.mul(royaltyPercent[sale.collectionId]).div(10000);
        uint256 amountFee = buyPrice.mul(commissionFee).div(10000);
        uint256 amountNetFeeRoyalty = buyPrice.sub(amountRoyalty).sub(amountFee);
        address creator = factory.getCollectionCreator(sale.collectionId);

        distributeRoyalty(creator, sale.seller, amountRoyalty);
        sendAmount(address(this), sale.seller, amountNetFeeRoyalty, 3); // Net of fees to seller

        sale.buyer = msg.sender;
        nft.safeTransferFrom(address(this), msg.sender, sale.tokenId);

        emit SaleCompleted(saleId, msg.sender, sale.seller, sale.price);
    }

    function sell(uint256 collectionId, address alamat, uint256 tokenId, uint256 price) public {

        IERC721 nft = IERC721(alamat);
        address seller = msg.sender;

        require(nft.ownerOf(tokenId) == seller, "Caller must be owner of tokenId");
        require(nft.isApprovedForAll(seller, address(this)), "Caller must approve this contract");
        require(price >= minimumPrice, "Price set must be more than minimumPrice");
        require(royaltySet[collectionId] == true, "Royalty must be set");

        nft.safeTransferFrom(seller, address(this), tokenId);

        uint256 saleId = _saleIdCounter.current();
        _saleIdCounter.increment();            

        Sale storage sale = sales[saleId];
        sale.collectionId = collectionId;
        sale.seller = seller;
        sale.price = price;
        sale.alamat = alamat;
        sale.tokenId = tokenId;  

        emit ForSale(saleId, seller, price);      
    }

    function retract(uint256 saleId) public payable {

        Sale memory sale = sales[saleId];
        address seller = sale.seller;
        address alamat = sale.alamat;
        uint256 tokenId = sale.tokenId;          

        IERC721 nft = IERC721(alamat);
        address caller = msg.sender;   
        uint256 cancelPrice = msg.value;

        require(caller == seller, "Caller must be seller");
        require(sale.buyer == address(0), "Must not have existing buyer"); 
        require(cancelPrice == cancelFee, "Must pay cancel fee");

        nft.safeTransferFrom(address(this), seller, tokenId);

        emit NotForSale(saleId, seller);
    }

    function getSale(uint256 saleId) public view returns (address seller, address buyer, uint256 price, address alamat, uint256 tokenId) {
        
        Sale memory sale = sales[saleId];
        
        seller = sale.seller;
        buyer = sale.buyer;
        price = sale.price;
        alamat = sale.alamat;
        tokenId = sale.tokenId;
    }

    function bidToken(uint256 auctionId) public payable {

        address bidder = msg.sender;
        uint256 bidAmount = msg.value;
        Auction memory auction = auctions[auctionId];  

        (uint256 previousHigh, address previousBidder) = getHighestBid(auctionId);

        require(bidAmount >= minimumPrice, "Must be more than minimum price set by platform");
        require(bidAmount > previousHigh, "Amount must exceed previous high");
        require(auction.bidAccepted == false, "Auction must still accepting bids");

        if (previousBidder != address(0)) {
            sendAmount(address(this), previousBidder, bidAmount, 4); // Refund previous bidder
        }

        uint256 bidId = _bidIdCounter.current();
        _bidIdCounter.increment();           

        Bid memory bid = bids[bidId];

        bid.amount = bidAmount;
        bid.bidder = bidder;
        bid.auctionId = auctionId;   

        auction.highestBid = bidId;  

        emit BidCreated(bidId, auctionId, bidder, bidAmount);
    }

    function acceptBid(uint256 auctionId) public {

        address auctioner = msg.sender;

        Auction memory auction = auctions[auctionId];   
        uint256 collectionId = auction.collectionId;
        uint256 tokenId = auction.tokenId;
        address alamat = auction.alamat;

        require(auctioner == auction.auctioner, "Only auctioner can call");
        require(auction.bidAccepted == false, "Auction must still accepting bids");

        (uint256 previousHigh, address previousBidder) = getHighestBid(auctionId);

        auction.bidAccepted = true;

        uint256 amountRoyalty = previousHigh.mul(royaltyPercent[collectionId]).div(10000);
        uint256 amountFee = previousHigh.mul(commissionFee).div(10000);
        uint256 amountNetFeeRoyalty = previousHigh.sub(amountRoyalty).sub(amountFee);
        address creator = factory.getCollectionCreator(collectionId);
        address smartContract = address(this);

        distributeRoyalty(creator, auctioner, amountRoyalty);
        sendAmount(smartContract, auctioner, amountNetFeeRoyalty, 3); // Net of fees to auctioner
        
        IERC721 nft = IERC721(alamat);
        nft.safeTransferFrom(address(this), previousBidder, tokenId); 

        emit AuctionCompleted(auctionId, auctioner, previousBidder, previousHigh);      
    }

    function auctionToken(uint256 collectionId, address alamat, uint256 tokenId, uint256 _minPrice) public {
        IERC721 nft = IERC721(alamat);
        address auctioner = msg.sender;

        require(nft.ownerOf(tokenId) == auctioner, "Caller must be owner of tokenId");
        require(nft.isApprovedForAll(auctioner, address(this)), "Caller must approve this contract");
        require(_minPrice >= minimumPrice, "Price set must be more than minimumPrice");
        require(royaltySet[collectionId] == true, "Royalty must be set");

        nft.safeTransferFrom(auctioner, address(this), tokenId);

        uint256 auctionId = _auctionIdCounter.current();
        _auctionIdCounter.increment();            

        Auction storage auction = auctions[auctionId];
        auction.auctioner = auctioner;
        auction.minimumPrice = _minPrice;

        auction.collectionId = collectionId;
        auction.alamat = alamat;
        auction.tokenId = tokenId;         

        emit AuctionCreated(auctionId, auctioner, _minPrice);
    }

    function getAuction(uint256 auctionId) public view 
        returns (
            uint256 collectionId, address alamat, uint256 tokenId, uint256 minPrice, 
            address auctioner, uint256 highestBid, bool bidAccepted) 
    {

        Auction memory auction = auctions[auctionId];      
        auctioner = auction.auctioner;
        minPrice = auction.minimumPrice;
        highestBid = auction.highestBid;
        bidAccepted = auction.bidAccepted;

        collectionId = auction.collectionId;
        alamat = auction.alamat;
        tokenId = auction.tokenId;              
    }

    function getBid(uint256 bidId) public view returns (uint256 amount, address bidder, uint256 auctionId) {
        Bid memory bid = bids[bidId];
        amount = bid.amount;
        bidder = bid.bidder;
        auctionId = bid.auctionId;        
    }

    function getHighestBid(uint256 auctionId) public view returns (uint256 amount, address bidder) {
        Auction memory auction = auctions[auctionId];      
        uint256 bidId = auction.highestBid;
        
        Bid memory bid = bids[bidId];
        amount = bid.amount;
        bidder = bid.bidder;
    }


    function withdraw(address _receiver, uint256 _amount) public onlyOwner {
        address payable receiver = payable(_receiver);
        bool sent = receiver.send(_amount);
        require(sent, "Failed to send Ether");        
    }

    function setFees(uint256 _cancelFee, uint256 _commissionFee, uint256 _minimumPrice) public onlyOwner {
        cancelFee = _cancelFee;
        commissionFee = _commissionFee;
        minimumPrice = _minimumPrice;
    }

    function getBalance() public view returns (uint256 amount) {
        amount = address(this).balance;
    }

    function distributeRoyalty(address creator, address seller, uint256 royalty) internal {
        (address upline1, address upline2, address upline3, address upline4, address upline5) = registrar.getUplines(seller);
        upline4; upline5;   

        // HERE WHERE YOU ADJUST COMMISSION PERCENTAGE
        uint256 amountCreator = royalty.mul(900).div(1000);
        uint256 amountUpline1 = royalty.mul(70).div(1000);
        uint256 amountUpline2 = royalty.mul(25).div(1000);
        uint256 amountUpline3 = royalty.mul(5).div(1000);

        if (upline1 != address(0)) {
            sendAmount(seller, upline1, amountUpline1, 2); // Royalty Distribution to seller's uplines

            if (upline2 != address(0)) {
                sendAmount(seller, upline2, amountUpline1, 2);

                if (upline3 != address(0)) {
                    sendAmount(seller, upline3, amountUpline1, 2);
                
                } else {
                    amountCreator = amountCreator.add(amountUpline3); 
                }                                
            } else {
                amountCreator = amountCreator.add(amountUpline2); 
            }            
        } else {
            amountCreator = amountCreator.add(amountUpline3); 
        }

        sendAmount(seller, creator, amountCreator, 1); // Royalty Distribution to Creator

    }

    function sendAmount(address sender, address receiver, uint256 amount, uint256 _amountType) internal {
        address payable personReceiver = payable(receiver);
        bool sentToPerson = personReceiver.send(amount);
        emit SendAmount(sender, receiver, amount, _amountType);  
        require(sentToPerson, "Failed to send to Person");         
    }       

}