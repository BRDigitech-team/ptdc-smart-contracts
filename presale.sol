// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface Aggregator {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract PayTheDebt_Sale is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20Metadata;

    uint256 public presaleId;
    uint256 public USDT_MULTIPLIER;
    uint256 public ETH_MULTIPLIER;
    address public ownerWallet;
    address public treasuryWallet;

    struct Presale {
        uint256 startTime;
        uint256 endTime;
        uint256 price;
        uint256 nextStagePrice;
        uint256 Sold;
        uint256 tokensToSell;
        uint256 UsdtHardcap;
        uint256 amountRaised;
        bool Active;
        bool isEnableClaim;
    }

    struct ClaimData {
        uint256 claimAt;
        uint256 totalAmount;
        uint256 claimedAmount;
    }

    IERC20Metadata public USDTInterface;
    Aggregator internal aggregatorInterface;
    // https://docs.chain.link/docs/ethereum-addresses/ => (ETH / USD)

    mapping(uint256 => bool) public paused;
    mapping(uint256 => Presale) public presale;
    mapping(address => mapping(uint256 => ClaimData)) public userClaimData;

    IERC20Metadata public SaleToken;

    event PresaleCreated(
        uint256 indexed _id,
        uint256 _totalTokens,
        uint256 _startTime,
        uint256 _endTime
    );

    event PresaleUpdated(
        bytes32 indexed key,
        uint256 prevValue,
        uint256 newValue,
        uint256 timestamp
    );

    event TokensBought(
        address indexed user,
        uint256 indexed id,
        address indexed purchaseToken,
        uint256 tokensBought,
        uint256 amountPaid,
        uint256 timestamp
    );

    event TokensClaimed(
        address indexed user,
        uint256 indexed id,
        uint256 amount,
        uint256 timestamp
    );

    event PresaleTokenAddressUpdated(
        address indexed prevValue,
        address indexed newValue,
        uint256 timestamp
    );

    event PresalePaused(uint256 indexed id, uint256 timestamp);
    event PresaleUnpaused(uint256 indexed id, uint256 timestamp);

    constructor(
        address _usdt,
        address _treasuryWallet,
        address _ownerWallet,
        address _oracle
    ) Ownable(msg.sender) {
       
        SaleToken = IERC20Metadata(0xFCfF1E1c63bB57cA9f9d3bB22a91713D444E34a3);
        USDTInterface = IERC20Metadata(_usdt);
        ETH_MULTIPLIER = (10**18);
        USDT_MULTIPLIER =(10**6) ;
        ownerWallet = _ownerWallet;
        treasuryWallet = _treasuryWallet;
        aggregatorInterface = Aggregator(_oracle);
    }

    // function ChangeTokenToSell(address _token) public onlyOwner {
    //     SaleToken = _token;
    // }

    // /**
    //  * @dev Creates a new presale
    //  * @param _price Per token price multiplied by (10**18)
    //  * @param _tokensToSell No of tokens to sell
    //  */
    function createPresale(uint256 _price,uint256 _nextStagePrice, uint256 _tokensToSell, uint256 _UsdtHardcap)
        external
        onlyOwner
    {
        require(_price > 0, "Zero price");
        require(_tokensToSell > 0, "Zero tokens to sell");
        require(presale[presaleId].Active == false, "Previous Sale is Active");

        presaleId++;

        presale[presaleId] = Presale(
            0,
            0,
            _price,
            _nextStagePrice,
            0,
            _tokensToSell,
            _UsdtHardcap,
            0,
            false,
            false
        );

        emit PresaleCreated(presaleId, _tokensToSell, 0, 0);
    }

    function startPresale() public onlyOwner {
        presale[presaleId].startTime = block.timestamp;
        presale[presaleId].Active = true;
    }

    function endPresale() public onlyOwner {
        require(
            presale[presaleId].Active = true,
            "This presale is already Inactive"
        );
        presale[presaleId].endTime = block.timestamp;
        presale[presaleId].Active = false;
    }

    // @dev enabel Claim amount
    function enableClaim(uint256 _id, bool _status)
        public
        checkPresaleId(_id)
        onlyOwner
    {
        presale[_id].isEnableClaim = _status;
    }

    // /**
    //  * @dev Update a new presale
    //  * @param _price Per USD price should be multiplied with token decimals
    //  * @param _tokensToSell No of tokens to sell without denomination. If 1 million tokens to be sold then - 1_000_000 has to be passed
    //  */
    function updatePresale(
        uint256 _id,
        uint256 _price,
        uint256 _nextStagePrice,
        uint256 _tokensToSell,
        uint256 _Hardcap
    ) external checkPresaleId(_id) onlyOwner {
        require(_price > 0, "Zero price");
        require(_tokensToSell > 0, "Zero tokens to sell");
        presale[_id].price = _price;
        presale[_id].nextStagePrice = _nextStagePrice;
        presale[_id].tokensToSell = _tokensToSell;
        presale[_id].UsdtHardcap =_Hardcap;
    }

    /**
     * @dev To update the fund receiving wallet
     * @param _wallet address of wallet to update

     */
    function changeFundWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "Invalid parameters");
        treasuryWallet = _wallet;
    }

    function changeOwnerTokenWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "Invalid parameters");
        ownerWallet = _wallet;
    }

    /**
     * @dev To update the USDT Token address
     * @param _newAddress Sale token address
     */
    function changeUSDTToken(address _newAddress) external onlyOwner {
        require(_newAddress != address(0), "Zero token address");
        USDTInterface = IERC20Metadata(_newAddress);
    }

    /**
     * @dev To pause the presale
     * @param _id Presale id to update
     */
    function pausePresale(uint256 _id) external checkPresaleId(_id) onlyOwner {
        require(!paused[_id], "Already paused");
        paused[_id] = true;
        emit PresalePaused(_id, block.timestamp);
    }

    /**
     * @dev To unpause the presale
     * @param _id Presale id to update
     */
    function unPausePresale(uint256 _id)
        external
        checkPresaleId(_id)
        onlyOwner
    {
        require(paused[_id], "Not paused");
        paused[_id] = false;
        emit PresaleUnpaused(_id, block.timestamp);
    }

    /**
     * @dev To get latest ethereum price in 10**18 format
     */
    function getLatestPrice() public view returns (uint256) {
        (, int256 price, , , ) = aggregatorInterface.latestRoundData();
        price = (price * (10**10));
        return uint256(price);
    }

    modifier checkPresaleId(uint256 _id) {
        require(_id > 0 && _id <= presaleId, "Invalid presale id");
        _;
    }

    modifier checkSaleState(uint256 _id, uint256 amount) {
        require(
            block.timestamp >= presale[_id].startTime &&
                presale[_id].Active == true,
            "Invalid time for buying"
        );
        require(
            amount > 0 && amount <= presale[_id].tokensToSell-presale[_id].Sold,
            "Invalid sale amount"
        );
        _;
    }

    /**
     * @dev To buy into a presale using USDT
     * @param usdAmount Usdt amount to buy tokens
     */
    function buyWithUSDT(uint256 usdAmount)
        external
        checkPresaleId(presaleId)
        checkSaleState(presaleId, usdtToTokens(presaleId, usdAmount))
        returns (bool)
    {
        require(!paused[presaleId], "Presale paused");
        require(presale[presaleId].Active == true, "Presale is not active yet");
        require(presale[presaleId].amountRaised + usdAmount <= presale[presaleId].UsdtHardcap,
        "Amount should be less than leftHardcap");

        uint8 decimals = SaleToken.decimals();
        uint256 tokenPrice = presale[presaleId].price; // calculate token price in eth
        uint256 tokens = (usdAmount * (10**uint256(decimals))) / tokenPrice;


        presale[presaleId].Sold += tokens;
        presale[presaleId].amountRaised += usdAmount;

        USDTInterface.safeTransferFrom(msg.sender, treasuryWallet, usdAmount);
        SaleToken.safeTransferFrom(ownerWallet, msg.sender, tokens);

        emit TokensBought(
            _msgSender(),
            presaleId,
            address(USDTInterface),
            tokens,
            usdAmount,
            block.timestamp
        );
        return true;
    }

    /**
     * @dev To buy into a presale using ETH
     */
    function buyWithETH()
        external
        payable
        checkPresaleId(presaleId)
        checkSaleState(presaleId, ethToTokens(presaleId, msg.value))
        nonReentrant
        returns (bool)
    {
        uint256 weiAmount = msg.value;

        uint256 usdAmount = (msg.value * getLatestPrice() * USDT_MULTIPLIER) / (ETH_MULTIPLIER * ETH_MULTIPLIER);
        require(presale[presaleId].amountRaised + usdAmount <= presale[presaleId].UsdtHardcap,
        "Amount should be less than leftHardcap");

        require(!paused[presaleId], "Presale paused");
        require(presale[presaleId].Active == true, "Presale is not active yet");

        // calculate token amount to be created
        uint8 decimals = SaleToken.decimals();
        uint256 tokenPrice = _getTokenPriceInEth(presale[presaleId].price); // calculate token price in eth
        uint256 tokens = (weiAmount * (10**uint256(decimals))) / tokenPrice;

        presale[presaleId].Sold += tokens;
        presale[presaleId].amountRaised += usdAmount;

        sendValue(payable(treasuryWallet), msg.value);
        SaleToken.safeTransferFrom(ownerWallet, msg.sender, tokens);
        emit TokensBought(
            _msgSender(),
            presaleId,
            address(0),
            tokens,
            msg.value,
            block.timestamp
        );
        return true;
    }


    /**
     * @dev Helper funtion to get ETH price for given amount
     * @param _id Presale id
     * @param amount No of tokens to buy
     */
    function ethBuyHelper(uint256 _id, uint256 amount)
        external
        view
        checkPresaleId(_id)
        returns (uint256 ethAmount)
    {
        uint256 usdPrice = (amount * presale[_id].price);
        ethAmount = (usdPrice * ETH_MULTIPLIER) / (getLatestPrice() * 10**IERC20Metadata(SaleToken).decimals());
    }

    /**
     * @dev Helper funtion to get USDT price for given amount
     * @param _id Presale id
     * @param amount No of tokens to buy
     */
    function usdtBuyHelper(uint256 _id, uint256 amount)
        external
        view
        checkPresaleId(_id)
        returns (uint256 usdPrice)
    {
        usdPrice = (amount * presale[_id].price) / 10**IERC20Metadata(SaleToken).decimals();
    }

    /**
     * @dev Helper funtion to get tokens for eth amount
     * @param _id Presale id
     * @param amount No of eth
     */
    function ethToTokens(uint256 _id, uint256 amount)
        public
        view
        returns (uint256 _tokens)
    {
        uint256 usdAmount = amount * getLatestPrice() * USDT_MULTIPLIER / (ETH_MULTIPLIER * ETH_MULTIPLIER);
        _tokens = usdtToTokens(_id, usdAmount);
    }

    /**
     * @dev Helper funtion to get tokens for given usdt amount
     * @param _id Presale id
     * @param amount No of usdt
     */
    function usdtToTokens(uint256 _id, uint256 amount)
        public
        view
        checkPresaleId(_id)
        returns (uint256 _tokens)
    {
        _tokens = (amount * presale[_id].price) / USDT_MULTIPLIER;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Low balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH Payment failed");
    }

    function unlockToken(uint256 _id)
        public
        view
        checkPresaleId(_id)
        onlyOwner
    {
        require(
            block.timestamp >= presale[_id].endTime,
            "You can only unlock on finalize"
        );
    }

    function _getTokenPriceInEth(uint256 _rate) internal view returns (uint256) {
        uint256 ethPriceInUsd = uint256(getLatestPriceEth());
        uint256 ethPriceinUSDT = ethPriceInUsd / 100;
        uint256 tokenPriceInEth = _rate * (10 ** 18) / ethPriceinUSDT;
        return tokenPriceInEth;
    }

    function getLatestPriceEth() public view returns (int) {
        (
            /*uint80 roundID*/,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = aggregatorInterface.latestRoundData();
        return answer;
    }


    
}