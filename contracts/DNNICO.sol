pragma solidity ^0.4.11;


import './libraries/math/SafeMath.sol';
import './DNNToken.sol';

/// @title DNNICO contract - Takes funds from users and issues tokens.
/// @author Dondrey Taylor - <dondrey@dnn.media>
contract DNNICO {

    using SafeMath for uint256;

    /////////////////////////
    // DNN Token Contract  //
    /////////////////////////
    DNNToken public dnnToken;

    //////////////////////////////////////////
    // Addresses of the co-founders of DNN. //
    //////////////////////////////////////////
    address public cofounderA;
    address public cofounderB;

    ///////////////////////////
    // DNN Holding Multisig //
    //////////////////////////
    address public dnnHoldingMultisig;

    ///////////////////////////
    // Start date of the ICO //
    ///////////////////////////
    uint256 public ICOStartDate;  // Epoch

    /////////////////////////
    // End date of the ICO //
    /////////////////////////
    uint256 public ICOEndDate;  // Epoch

    /////////////////////////////////
    // Amount of atto-DNN per wei //
    /////////////////////////////////
    uint256 public tokenExchangeRateBase = 3000; // 1 Wei = 3000 atto-DNN

    /////////////////////////////////////////////////
    // Number of tokens distributed (in atto-DNN) //
    /////////////////////////////////////////////////
    uint256 public tokensDistributed = 0;

    ///////////////////////////////////////////////
    // Minumum Contributions for pre-ICO and ICO //
    ///////////////////////////////////////////////
    uint256 public minimumICOContributionInWei = 0.001 ether;
    uint256 public minimumPREICOContributionInWei = 100 ether;

    //////////////////////
    // Funding Hard cap //
    //////////////////////
    uint256 public maximumFundingGoalInETH;

    //////////////////
    // Funds Raised //
    //////////////////
    uint256 public fundsRaisedInWei;

    ////////////////////////////////////////////
    // Keep track of Wei contributed per user //
    ////////////////////////////////////////////
    mapping(address => uint256) ETHContributions;


    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // Keeps track of pre-ico contributors and how many tokens they are entitled to get based on their contribution //
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    mapping(address => uint256) PREICOContributorTokensPendingRelease;
    mapping(uint256 => address) PREICOContributors; // iterative list of pre-ico contributor addresses
    uint256 PREICOContributorsCount = 0; // Total number of pre-ico contributors


    ///////////////////////////////////////////////////////////////////
    // Checks if all pre-ico contributors have received their tokens //
    ///////////////////////////////////////////////////////////////////
    modifier NoPREICOContributorsAwaitingTokens() {

        // Determine if all pre-ico contributors have received tokens
        require(getOutstandingPREICOTokenIssuance() == 0);

        _;
    }

    ///////////////////////////////////////////////////////////////////////////////////////
    // Checks if there are any pre-ico contributors that have not recieved their tokens  //
    ///////////////////////////////////////////////////////////////////////////////////////
    modifier PREICOContributorsAwaitingTokens() {

        // Determine if all pre-ico contributors have received tokens
        require(getOutstandingPREICOTokenIssuance() > 0);

        _;
    }

    ////////////////////////////////////////////////////
    // Checks if CoFounders are performing the action //
    ////////////////////////////////////////////////////
    modifier onlyCofounders() {
        require (msg.sender == cofounderA || msg.sender == cofounderB);
        _;
    }

    ////////////////////////////////////////////////////
    // Checks if CoFounder A is performing the action //
    ////////////////////////////////////////////////////
    modifier onlyCofounderA() {
        require (msg.sender == cofounderA);
        _;
    }

    ////////////////////////////////////////////////////
    // Checks if CoFounder B is performing the action //
    ////////////////////////////////////////////////////
    modifier onlyCofounderB() {
        require (msg.sender == cofounderB);
        _;
    }

    //////////////////////////////////////
    // Check if the pre-ico is going on //
    //////////////////////////////////////
    modifier PREICOHasNotEnded() {
       require (now < ICOStartDate);
       _;
    }

    //////////////////////////////////////
    // Check if the pre-ico is going on //
    //////////////////////////////////////
    modifier ICOHasNotEnded() {
       require (now < ICOEndDate);
       _;
    }

    //////////////////////////////////////
    // Check if the pre-ico is going on //
    //////////////////////////////////////
    modifier ICOHasEnded() {
       require (now >= ICOEndDate || fundsRaisedInWei >= maximumFundingGoalInETH);
       _;
    }

    /////////////////////////////////////////////////////////////
    // User has to send at least the ether value of one token. //
    /////////////////////////////////////////////////////////////
    modifier ContributionIsAtLeastMinimum() {
        require (msg.value >= minimumICOContributionInWei);
        _;
    }

    ///////////////////////////////////////////////////////////////
    // Make sure max cap is not exceeded with added contribution //
    ///////////////////////////////////////////////////////////////
    modifier ContributionDoesNotCauseGoalExceedance() {
       uint256 newContractBalance = msg.value+fundsRaisedInWei;
       require (newContractBalance <= maximumFundingGoalInETH && fundsRaisedInWei < maximumFundingGoalInETH);
       _;
    }

    /////////////////////////////////////////////////////////////////
    // Check if the specified beneficiary has sent us funds before //
    /////////////////////////////////////////////////////////////////
    modifier HasPendingPREICOTokens(address _contributor) {
        require (PREICOContributorTokensPendingRelease[_contributor] !=  0);
        _;
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    // @des Gives back the total count of pre-ico contributors that haven't received tokens //
    //////////////////////////////////////////////////////////////////////////////////////////
    function getOutstandingPREICOTokenIssuance()
        internal
        constant
        returns (uint256)
    {
        // Total count of preico contributors still waiting for tokens
        uint256 outstandingContributorCount = 0;

        // Iterate through the list of pre-ico contributors, checking for those that have
        // not yet received tokens
        for (uint256 index=0; index < PREICOContributorsCount; index++) {

            // Use the address of the pre-ico contributor to check if they have not yet received tokens
            if (PREICOContributorTokensPendingRelease[PREICOContributors[index]] > 0) {
                outstandingContributorCount++;
            }
        }

        return outstandingContributorCount;
    }

    ///////////////////////////////////////////////////////
    //  @des Function to change founder A address.       //
    //  @param newAddress Address of new founder A.      //
    ///////////////////////////////////////////////////////
    function changeCofounderA(address newAddress)
        onlyCofounderA
    {
        cofounderA = newAddress;
    }

    //////////////////////////////////////////////////////
    //  @des Function to change founder B address.      //
    //  @param newAddress Address of new founder B.     //
    //////////////////////////////////////////////////////
    function changeCofounderB(address newAddress)
        onlyCofounderB
    {
        cofounderB = newAddress;
    }

    //////////////////////////////////////////////////////
    //  @des Function to change multisig address.       //
    //  @param newAddress Address of new multisig.      //
    //////////////////////////////////////////////////////
    function changeDNNHoldingMultisig(address newAddress)
        onlyCofounders
    {
        dnnHoldingMultisig = newAddress;
    }

    //////////////////////////////////////////
    // @des ETH balance of each contributor //
    //////////////////////////////////////////
    function contributorETHBalance(address _owner)
      constant
      returns (uint256 balance)
    {
        return ETHContributions[_owner];
    }

    ////////////////////////////////////////////////////////////
    // @des Determines if an address is a pre-ICO contributor //
    ////////////////////////////////////////////////////////////
    function isExistingPREICOContributor(address _contributorAddress)
       internal
       returns (bool)
    {
        // Iterate through the list of pre-ico contributors, checking for the specific contributor provided
        for (uint256 index=0; index < PREICOContributorsCount; index++) {

            // Check if the address exists in pre-ICO contributor list
            if (PREICOContributors[index] == _contributorAddress) {
                return true;
            }
        }

        return false;
    }
    /////////////////////////////////////////////////////////////
    // @des Returns pending presale tokens for a given address //
    /////////////////////////////////////////////////////////////
    function getPendingPresaleTokens(address _contributor)
        constant
        returns (uint256)
    {
        return PREICOContributorTokensPendingRelease[_contributor];
    }

    ////////////////////////////////
    // @des Returns current bonus //
    ////////////////////////////////
    function getCurrentICOBonus()
        constant
        returns (uint256)
    {
        return getICOTokenExchangeRate(now);
    }


    ////////////////////////////////
    // @des Returns current bonus //
    ////////////////////////////////
    function getCurrentPREICOBonus()
        constant
        returns (uint256)
    {
        return getPREICOTokenExchangeRate(now);
    }

    ///////////////////////////////////////////////////////////////////////
    // @des Returns bonus (in atto-DNN) per wei for the specific moment //
    // @param timestamp Time of purchase (in seconds)                    //
    ///////////////////////////////////////////////////////////////////////
    function getICOTokenExchangeRate(uint256 timestamp)
        constant
        returns (uint256)
    {
        // No bonus - ICO ended
        if (timestamp > ICOEndDate) {
            return uint256(0);
        }

        // No bonus - ICO has not started
        if (ICOStartDate > timestamp) {
            return uint256(0);
        }

        // Determine how long the ICO has been running
        uint256 icoDuration = timestamp.sub(ICOStartDate);

        // Beyond Week 1 - 0% bonus
        if (icoDuration > 1 weeks) {
            return tokenExchangeRateBase;

        // After 48 hours - 5% bonus
        } else if (icoDuration > 48 hours) {
            return tokenExchangeRateBase + tokenExchangeRateBase.mul(5).div(100);

        // First 48 hours - 10% bonus
        } else if (icoDuration <= 48 hours) {
            return tokenExchangeRateBase + tokenExchangeRateBase.mul(10).div(100);

        // Default - 0% bonus
        } else {
            return tokenExchangeRateBase;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // @des Returns bonus (in atto-DNN) per wei for the specific contribution amount //
    // @param weiamount The amount of wei being contributed                           //
    ////////////////////////////////////////////////////////////////////////////////////
    function getPREICOTokenExchangeRate(uint256 weiamount)
        constant
        returns (uint256)
    {
        // Presale will only accept contributions above minimum
        if (weiamount < minimumPREICOContributionInWei) {
            return uint256(0);
        }

        // 100 ETH - 199 ETH Bonus
        if (weiamount >= 100 ether && weiamount <= 199 ether) {
            return tokenExchangeRateBase + tokenExchangeRateBase.mul(15).div(100);

        // 200 ETH - 300 ETH Bonus
        } else if (weiamount >= 200 ether && weiamount <= 300 ether) {
            return tokenExchangeRateBase + tokenExchangeRateBase.mul(20).div(100);

        // 301 ETH - 2665 ETH Bonus
        } else if (weiamount >= 301 ether && weiamount <= 2665 ether) {
            return tokenExchangeRateBase + tokenExchangeRateBase.mul(25).div(100);

        // 2666+ ETH Bonus
        } else {
            return tokenExchangeRateBase + tokenExchangeRateBase.mul(40).div(100);
        }
    }

    //////////////////////////////////////////////////////////////////////////////////////////
    // @des Computes how many tokens a buyer is entitled to based on contribution and time. //
    //////////////////////////////////////////////////////////////////////////////////////////
    function calculateTokens(uint256 weiamount, uint256 timestamp)
        constant
        returns (uint256)
    {

        // Compute how many atto-DNN user is entitled to.
        uint256 computedTokensForPurchase = weiamount.mul(timestamp >= ICOStartDate ? getICOTokenExchangeRate(timestamp) : getPREICOTokenExchangeRate(weiamount));

        // Amount of atto-DNN to issue
        return computedTokensForPurchase;
     }


    ///////////////////////////////////////////////////////////////
    // @des Issues tokens for users who made purchase with ETH   //
    // @param beneficiary Address the tokens will be issued to.  //
    // @param weiamount ETH amount (in Wei)                      //
    // @param timestamp Time of purchase (in seconds)            //
    ///////////////////////////////////////////////////////////////
    function buyTokens()
        internal
        ContributionIsAtLeastMinimum
        ContributionDoesNotCauseGoalExceedance
        returns (bool)
    {

        // Determine how many tokens should be issued
        uint256 tokenCount = calculateTokens(msg.value, now);

        // Update total amount of tokens distributed (in atto-DNN)
        tokensDistributed = tokensDistributed.add(tokenCount);

        // Keep track of contributions (in Wei)
        ETHContributions[msg.sender] = ETHContributions[msg.sender].add(msg.value);

        // Increase total funds raised by contribution
        fundsRaisedInWei = fundsRaisedInWei.add(msg.value);

        // Determine which token allocation we should be deducting from
        DNNToken.DNNSupplyAllocations allocationType = DNNToken.DNNSupplyAllocations.ICOSupplyAllocation;

        // Attempt to issue tokens to contributor
        if (!dnnToken.issueTokens(msg.sender, tokenCount, allocationType)) {
            revert();
        }

        // Transfer funds to multisig
        dnnHoldingMultisig.transfer(msg.value);

        return true;
    }

    ////////////////////////////////////////////////////////////////////////////////////////
    // @des Issues tokens for users who made purchase without using ETH during presale.   //
    // @param beneficiary Address the tokens will be issued to.                           //
    // @param weiamount ETH amount (in Wei)                                               //
    ////////////////////////////////////////////////////////////////////////////////////////
    function buyPREICOTokensWithoutETH(address beneficiary, uint256 weiamount, uint tokenCount)
        onlyCofounders
        PREICOHasNotEnded
        returns (bool)
    {

          // Keep track of contributions (in Wei)
          ETHContributions[beneficiary] = ETHContributions[beneficiary].add(weiamount);

          // Increase total funds raised by contribution
          fundsRaisedInWei = fundsRaisedInWei.add(weiamount);

          // Check to see if this contributor has sent ETH in the past, prior to reflecting them in
          // the contract as a new participant
          if (!isExistingPREICOContributor(beneficiary)) {
              PREICOContributors[PREICOContributorsCount] = beneficiary;
              PREICOContributorsCount += 1;
          }

          // Add these tokens to the total amount of tokens this contributor is entitled to
          PREICOContributorTokensPendingRelease[beneficiary] = PREICOContributorTokensPendingRelease[beneficiary].add(tokenCount);

          // Send tokens to contibutor
          return issuePREICOTokens(beneficiary);
      }

    ///////////////////////////////////////////////////////////////
    // @des Issues pending tokens to pre-ico contributor         //
    // @param beneficiary Address the tokens will be issued to.  //
    ///////////////////////////////////////////////////////////////
    function issuePREICOTokens(address beneficiary)
        onlyCofounders
        PREICOContributorsAwaitingTokens
        HasPendingPREICOTokens(beneficiary)
        returns (bool)
    {

        // Amount of tokens to credit pre-ico contributor
        uint256 tokenCount = PREICOContributorTokensPendingRelease[beneficiary];

        // Update total amount of tokens distributed (in atto-DNN)
        tokensDistributed = tokensDistributed.add(tokenCount);

        // Allocation type will be PREICOSupplyAllocation
        DNNToken.DNNSupplyAllocations allocationType = DNNToken.DNNSupplyAllocations.PREICOSupplyAllocation;

        // Attempt to issue tokens
        if (!dnnToken.issueTokens(beneficiary, tokenCount, allocationType)) {
            revert();
        }

        // Denote that tokens have been issued for this pre-ico contributor
        PREICOContributorTokensPendingRelease[beneficiary] = 0;

        return true;
    }


    /////////////////////////////////
    // @des Marks ICO as completed //
    /////////////////////////////////
    function finalizeICO()
       onlyCofounders
       ICOHasEnded
    {
        // Check if the tokens are either locked or we have tokens to transfer
        require(dnnToken.tokensLocked() == true || dnnToken.ICOSupplyRemaining() > 0);

        // Unlock tokens
        dnnToken.unlockTokens();

        // Transfer unsold ICO tokens to platform
        dnnToken.sendUnsoldICOTokensToPlatform();
    }


    ////////////////////////////////////////////////////////////////////////////////
    // @des Marks pre-ICO as completed by moving remaining tokens into ICO supply //
    ////////////////////////////////////////////////////////////////////////////////
    function finalizePREICO()
       onlyCofounders
       NoPREICOContributorsAwaitingTokens
    {
        // Check if we have tokens to transfer to ICO
        require(dnnToken.PREICOSupplyRemaining() > 0);

        // Transfer unsold ICO tokens to platform
        dnnToken.sendUnsoldPREICOTokensToICO();
    }


    ///////////////////////////////
    // @des Contract constructor //
    ///////////////////////////////
    function DNNICO(address tokenAddress, address founderA, address founderB, address dnnHolding, uint256 hardCap, uint256 startDate, uint256 endDate)
    {

        // Set token address
        dnnToken = DNNToken(tokenAddress);

        // Set cofounder addresses
        cofounderA = founderA;
        cofounderB = founderB;

        // Set DNN holding address
        dnnHoldingMultisig = dnnHolding;

        // Set Hard Cap
        maximumFundingGoalInETH = hardCap * 1 ether;

        // Set Start Date
        ICOStartDate = startDate >= now ? startDate : now;

        // Set End date (Make sure the end date is at least 30 days from start date)
        // Will default to a date that is exactly 30 days from start date.
        ICOEndDate = endDate > ICOStartDate && (endDate-ICOStartDate) >= 30 days ? endDate : (ICOStartDate + 30 days);
    }

    /////////////////////////////////////////////////////////
    // @des Handle's ETH sent directly to contract address //
    /////////////////////////////////////////////////////////
    function () payable {

        // Handle pre-sale contribution (tokens held, until tx confirmation from contributor)
        // Also, make sure the user sends minimum PRE-ICO contribution.
        if (now < ICOStartDate && msg.value >= minimumPREICOContributionInWei) {

            // Keep track of contributions (in Wei)
            ETHContributions[msg.sender] = ETHContributions[msg.sender].add(msg.value);

            // Increase total funds raised by contribution
            fundsRaisedInWei = fundsRaisedInWei.add(msg.value);

            /// Make a note of how many tokens this user should get for their contribution to the presale
            PREICOContributorTokensPendingRelease[msg.sender] = PREICOContributorTokensPendingRelease[msg.sender].add(calculateTokens(msg.value, now));

            // Store the users address and update pre-ico contibutor count (will be used when determining outstanding token issuance)
            // Check to see if this contributor has sent ETH in the past, prior to reflecting them in
            // the contract as a new participant
            if (!isExistingPREICOContributor(msg.sender)) {
                PREICOContributors[PREICOContributorsCount] = msg.sender;
                PREICOContributorsCount += 1;
            }

            // Transfer contribution directly to multisig
            dnnHoldingMultisig.transfer(msg.value);
        }

        // Handle public-sale contribution (tokens issued immediately)
        else if (now >= ICOStartDate && now < ICOEndDate) buyTokens();

        // Otherwise, reject the contribution
        else revert();
    }
}
