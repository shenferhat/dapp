pragma solidity ^0.5.0;
import "./interfaces/IERC721Full.sol";
import "./utils/SafeMath.sol";

contract Vitalik {
    
    /*
    This smart contract collects patronage from current owner through a Harberger tax model and 
    takes stewardship of the asset token if the patron can't pay anymore.

    Harberger Tax (COST): 
    - Asset is always on sale.
    - You have to have a price set.
    - Tax (Patronage) is paid to maintain ownership.
    - Steward maints control over ERC721.
    */
    using SafeMath for uint256;
    
    uint256 public price; //in wei
    IERC721Full public assetToken; // ERC721 NFT.
    
    uint256 public totalCollected; // all patronage ever collected
    uint256 public currentCollected; // amount currently collected for patron  
    uint256 public timeLastCollected; // 
    uint256 public deposit;

    address payable public organization; // non-profit organization
    uint256 public organizationFund;
    
    mapping (address => bool) public patrons;
    mapping (address => uint256) public timeHeld;
    mapping (address => uint256) public paid; // NOTE: not used [accident]

    uint256 public timeAcquired;
    
    // 5% patronage
    uint256 patronageNumerator = 50000000000;
    uint256 patronageDenominator = 1000000000000;

    enum StewardState { Foreclosed, Owned }
    StewardState public state;

    constructor(address payable _organization, address _assetToken) public {
        assetToken = IERC721Full(_assetToken);
        assetToken.setup();
        organization = _organization;
        state = StewardState.Foreclosed;
    } 

    event LogBuy(address indexed owner, uint256 indexed price);
    event LogPriceChange(uint256 indexed newPrice);
    event LogForeclosure(address indexed prevOwner);
    event LogCollection(uint256 indexed collected);
    
    modifier onlyPatron() {
        require(msg.sender == assetToken.ownerOf(42), "Not patron");
        _;
    }

    modifier onlyReceivingOrganization() {
        require(msg.sender == organization);
        _;
    }

    modifier collectPatronage() {
       _collectPatronage(); 
       _;
    }

    function changeReceivingOrganization(address _newReceivingOrganization) public onlyReceivingOrganization {
        organization = address(uint160(_newReceivingOrganization));
    }

    /* public view functions */
    function patronageOwed() public view returns (uint256 patronageDue) {
        return price.mul(now.sub(timeLastCollected)).mul(patronageNumerator)
            .div(patronageDenominator).div(365 days);
    }

    function patronageOwedWithTimestamp() public view returns (uint256 patronageDue, uint256 timestamp) {
        return (patronageOwed(), now);
    }

    function foreclosed() public view returns (bool) {
        // returns whether it is in foreclosed state or not
        // depending on whether deposit covers patronage due
        // useful helper function when price should be zero, but contract doesn't reflect it yet.
        uint256 collection = patronageOwed();
        if(collection >= deposit) {
            return true;
        } else {
            return false;
        }
    }

    // same function as above, basically
    function depositAbleToWithdraw() public view returns (uint256) {
        uint256 collection = patronageOwed();
        if(collection >= deposit) {
            return 0;
        } else {
            return deposit.sub(collection);
        }
    }

    /*
    now + deposit/patronage per second 
    now + depositAbleToWithdraw/(price*nume/denom/365).
    */
    function foreclosureTime() public view returns (uint256) {
        // patronage per second
        uint256 pps = price.mul(patronageNumerator).div(patronageDenominator).div(365 days);
        return now + depositAbleToWithdraw().div(pps); // zero division if price is zero.
    }

    /* actions */
    function _collectPatronage() public {
        // determine patronage to pay
        if (state == StewardState.Owned) {
            uint256 collection = patronageOwed();
            
            // should foreclose and stake stewardship
            if (collection >= deposit) {
                // up to when was it actually paid for?
                timeLastCollected = timeLastCollected.add(((now.sub(timeLastCollected)).mul(deposit).div(collection)));
                collection = deposit; // take what's left.

                _foreclose();
            } else  {
                // just a normal collection
                timeLastCollected = now;
                currentCollected = currentCollected.add(collection);
            }
            
            deposit = deposit.sub(collection);
            totalCollected = totalCollected.add(collection);
            organizationFund = organizationFund.add(collection);
            emit LogCollection(collection);
        }
    }
    
    // note: anyone can deposit
    function depositWei() public payable collectPatronage {
        require(state != StewardState.Foreclosed, "Foreclosed");
        deposit = deposit.add(msg.value);
    }
    
    function buy(uint256 _newPrice) public payable collectPatronage {
        require(_newPrice > 0, "Price is zero");
        require(msg.value > price, "Not enough"); // >, coz need to have at least something for deposit
        address currentOwner = assetToken.ownerOf(42);

        if (state == StewardState.Owned) {
            uint256 totalToPayBack = price;
            if(deposit > 0) {
                totalToPayBack = totalToPayBack.add(deposit);
            }  
    
            // pay previous owner their price + deposit back.
            address payable payableCurrentOwner = address(uint160(currentOwner));
            payableCurrentOwner.transfer(totalToPayBack);
        } else if(state == StewardState.Foreclosed) {
            state = StewardState.Owned;
            timeLastCollected = now;
        }
        
        deposit = msg.value.sub(price);
        transferAssetTokenTo(currentOwner, msg.sender, _newPrice);
        emit LogBuy(msg.sender, _newPrice);
    }

    function changePrice(uint256 _newPrice) public onlyPatron collectPatronage {
        require(state != StewardState.Foreclosed, "Foreclosed");
        require(_newPrice != 0, "Incorrect Price");
        
        price = _newPrice;
        emit LogPriceChange(price);
    }
    
    function withdrawDeposit(uint256 _wei) public onlyPatron collectPatronage returns (uint256) {
        _withdrawDeposit(_wei);
    }

    function withdrawOrganizationFunds() public {
        require(msg.sender == organization, "Not organization");
        organization.transfer(organizationFund);
        organizationFund = 0;
    }

    function exit() public onlyPatron collectPatronage {
        _withdrawDeposit(deposit);
    }

    /* internal */

    function _withdrawDeposit(uint256 _wei) internal {
        // note: can withdraw whole deposit, which puts it in immediate to be foreclosed state.
        require(deposit >= _wei, 'Withdrawing too much');

        deposit = deposit.sub(_wei);
        msg.sender.transfer(_wei); // msg.sender == patron

        if(deposit == 0) {
            _foreclose();
        }
    }

    function _foreclose() internal {
        // become steward of assetToken (aka foreclose)
        address currentOwner = assetToken.ownerOf(42);
        transferAssetTokenTo(currentOwner, address(this), 0);
        state = StewardState.Foreclosed;
        currentCollected = 0;

        emit LogForeclosure(currentOwner);
    }

    function transferAssetTokenTo(address _currentOwner, address _newOwner, uint256 _newPrice) internal {
        // note: it would also tabulate time held in stewardship by smart contract
        timeHeld[_currentOwner] = timeHeld[_currentOwner].add((timeLastCollected.sub(timeAcquired)));
        
        assetToken.transferFrom(_currentOwner, _newOwner, 42);

        price = _newPrice;
        timeAcquired = now;
        patrons[_newOwner] = true;
    }
}
