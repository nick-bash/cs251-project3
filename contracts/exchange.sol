// =================== CS251 DEX Project =================== // 
//        @authors: Simon Tao '22, Mathew Hogan '22          //
// ========================================================= //    
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../interfaces/erc20_interface.sol';
import '../libraries/safe_math.sol';
import './token.sol';


contract TokenExchange {
    using SafeMath for uint;
    address public admin;

    address tokenAddr = 0xef750Bc13cC7DbdF2cea14834f8591303712f1BE;
    DragonToken private token = DragonToken(tokenAddr);

    uint public token_reserves = 0;
    uint public eth_reserves = 0;

    // Constant: x * y = k
    uint public k;

    // Track liquidity providers (LPs)
    address[] private LPs;
    // Track each LP's percentage share as integers
    // Multiply each integer by 10^3, to allow for float-like calculation
    // i.e. a 64% share is represented as 64000
    mapping (address => uint) private LP_shares; 
    uint private float_converter = 1000;
    uint private pct_converter = float_converter*100;
    
    // liquidity rewards
    uint private swap_fee_numerator = 0;       // TODO Part 5: Set liquidity providers' returns.
    uint private swap_fee_denominator = 100;
    
    // Events to be emitted as logs
    // Note to instructors: I assume all amounts represent ETH, not tokens
    event AddLiquidity(address from, uint amount);
    event RemoveLiquidity(address to, uint amount);
    event Received(address from, uint amountETH);
    event Debug(string message); // for debugging

    constructor() 
    {
        admin = msg.sender;
    }
    
    modifier AdminOnly {
        require(msg.sender == admin, "Only admin can use this function!");
        _;
    }

    // Used for receiving ETH
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
    fallback() external payable{}

    // Function createPool: Initializes a liquidity pool between your Token and ETH.
    // ETH will be sent to pool in this transaction as msg.value
    // amountTokens specifies the amount of tokens to transfer from the liquidity provider.
    // Sets up the initial exchange rate for the pool by setting amount of token and amount of ETH.
    // In createPool, you will have to add some code to track the liquidity added by the initial pool creator. The original starter code said not to modify the function, but this was a mistake. This should just be one or two lines.
    function createPool(uint amountTokens) external payable AdminOnly
    {
        // require pool does not yet exist
        require (token_reserves == 0, "Token reserves was not 0");
        require (eth_reserves == 0, "ETH reserves was not 0.");

        // require nonzero values were sent
        require (msg.value > 0, "Need ETH to create pool.");
        require (amountTokens > 0, "Need tokens to create pool.");

        emit Debug("Successfully passed require checks  in createPool()");
        token.transferFrom(msg.sender, address(this), amountTokens);
        emit Debug("Successful transfer in createPool()");
        eth_reserves = msg.value;
        token_reserves = amountTokens;
        k = eth_reserves.mul(token_reserves);
        emit Debug("Successfully set eth/token values in createPool()");                

        // Keep track of the initial liquidity added by the initial provider
        LPs.push(msg.sender);
        LP_shares[msg.sender] = pct_converter;
        emit Debug("createPool done()");
    }

    // ============================================================
    //                    FUNCTIONS TO IMPLEMENT
    // ============================================================
    /* Be sure to use the SafeMath library for all operations! */
    
    // Function priceToken: Calculate the price of your token in ETH.
    // You can change the inputs, or the scope of your function, as needed.
    function priceToken() public view returns (uint)
    {
        return eth_reserves.mul(float_converter).div(token_reserves).div(float_converter);
    }

    // Function priceETH: Calculate the price of ETH in your token.
    // You can change the inputs, or the scope of your function, as needed.
    function priceETH() public view returns (uint)
    {        
        return token_reserves.mul(float_converter).div(eth_reserves).div(float_converter);
    }

    // Function addLiquidity: Adds liquidity given a supply of ETH (sent to the contract as msg.value)
    // You can change the inputs, or the scope of your function, as needed.
    function addLiquidity(uint ETH_max_exchange_rate, uint ETH_min_exchange_rate) external payable
    {       
        /* HINTS:
            Calculate the liquidity to be added based on what was sent in and the prices.
            If the caller possesses insufficient tokens to equal the ETH sent, then transaction must fail.
            Update token_reserves, eth_reserves, and k.
            Emit AddLiquidity event.
        */
        // Check sender has enough tokens
        uint tokens_required = msg.value.mul(token_reserves).mul(float_converter).div(eth_reserves).div(float_converter);
        require(tokens_required <= token.balanceOf(msg.sender), "Not enough tokens to add liquidity");
        emit Debug("addLiquidity() require tests passed");

        // Check for slippage
        require(ETH_max_exchange_rate >= priceETH(), "addLiquidity(): max ETH exchange rate exceeded");
        require(ETH_min_exchange_rate <= priceETH(), "addLiquidity(): min ETH exchange rate breached");
        
        // Transfer the tokens to the exchange contract
        token.transferFrom(msg.sender, address(this), tokens_required);
        
        // Update token_reserves, eth_reserves, and k
        uint old_eth_reserves = eth_reserves;                
        eth_reserves = eth_reserves.add(msg.value);
        token_reserves = token_reserves.add(tokens_required);
        k = token_reserves.mul(eth_reserves);
        
        // Update shares of other LPs for dilution
        uint checkSum = 0;
        for(uint i = 0; i < LPs.length; i++)
        {
            LP_shares[LPs[i]] = LP_shares[LPs[i]].mul(old_eth_reserves).div(eth_reserves);
            checkSum = checkSum.add(LP_shares[LPs[i]]);
        }

        // Track this liquidity provider
        LPs.push(msg.sender);
        LP_shares[msg.sender] = pct_converter.mul(msg.value).div(eth_reserves);
        checkSum = checkSum.add(LP_shares[msg.sender]);
        
        //require(checkSum == pct_converter, "LP shares not adding up to 100%");
        //emit Debug("addLiquidity() LP shares correctly adjusted");

        // Emit AddLiquidity event    
        emit AddLiquidity(msg.sender, msg.value);
        emit Debug("addLiquidity() finished");
    }

    // Function removeLiquidity: Removes liquidity given the desired amount of ETH to remove.
    // You can change the inputs, or the scope of your function, as needed.
    function removeLiquidity(uint amountETH, uint ETH_max_exchange_rate, uint ETH_min_exchange_rate) public payable
    {
        /* HINTS:
            Calculate the amount of your tokens that should be also removed.
            Transfer the ETH and Token to the provider.
            Update token_reserves, eth_reserves, and k.
            Emit RemoveLiquidity event.
        */
        // Check the requester is entitled to remove this amount
        uint requestedShare = amountETH.mul(pct_converter).div(eth_reserves);
        require(requestedShare <= LP_shares[msg.sender], "Not enough share in LP pool to removeLiquidity()");
        
        // Check for slippage
        require(ETH_max_exchange_rate >= priceETH(), "removeLiquidity(): max ETH exchange rate exceeded");
        require(ETH_min_exchange_rate <= priceETH(), "removeLiquidity(): min ETH exchange rate breached");
        
        // Check this won't empty either pool
        uint tokens_required = amountETH.mul(token_reserves).mul(float_converter).div(eth_reserves).div(float_converter);
        require(tokens_required < token_reserves, "Request to remove liquidity would empty token reserves");
        require(amountETH < eth_reserves, "Request to remove liquidity would empty ETH reserves");

        emit Debug("removeLiquidity() require tests passed");
        
        // Transfer ETH to sender & Token to provider
        (bool sent, bytes memory data) = msg.sender.call{value: amountETH}("");
        require(sent, "Failed to send Ether back to sender in removeLiquidity()");        
        token.transfer(msg.sender, tokens_required); // emits log for tokens

        // Update values
        uint old_eth_reserves = eth_reserves;
        eth_reserves = eth_reserves.sub(amountETH);
        token_reserves = token_reserves.sub(tokens_required);
        k = token_reserves.mul(eth_reserves);

        // TODO: Remove this LP from list of LPs
        LP_shares[msg.sender] = 0;
                
        // Update shares of all other LPs
        uint checkSum = 0;
        for(uint i = 0; i < LPs.length; i++)
        {
            LP_shares[LPs[i]] = LP_shares[LPs[i]].mul(old_eth_reserves).div(eth_reserves);
            checkSum = checkSum.add(LP_shares[LPs[i]]);
        }
        //require(checkSum == pct_converter, "LP shares not adding up to 100%");
        //emit Debug("removeLiquidity() LP shares correctly adjusted");

        // Emit event
        emit RemoveLiquidity(msg.sender, amountETH);
        emit Debug("RemoveLiquidity() finished");
    }

    // Function removeAllLiquidity: Removes all liquidity that msg.sender is entitled to withdraw
    // You can change the inputs, or the scope of your function, as needed.
    function removeAllLiquidity(uint ETH_max_exchange_rate, uint ETH_min_exchange_rate) external payable
    {        
        uint amountETH = LP_shares[msg.sender].mul(eth_reserves).div(pct_converter);
        removeLiquidity(amountETH, ETH_max_exchange_rate, ETH_min_exchange_rate);
        emit Debug("removeAllLiquidity() finished");
    }

    // Function swapTokensForETH: Swaps your token with ETH
    // You can change the inputs, or the scope of your function, as needed.
    function swapTokensForETH(uint amountTokens, uint max_exchange_rate) external payable
    {        
        /* HINTS:
          Part 4: 
                Expand the function to take in addition parameters as needed.
                If current exchange_rate > slippage limit, abort the swap.
            
            Part 5:
                Only exchange amountTokens * (1 - liquidity_percent), 
                    where % is sent to liquidity providers.
                Keep track of the liquidity fees to be added.
        */

        // Check caller has sufficient tokens
        require(amountTokens <= token.balanceOf(msg.sender), "Insufficient tokens in swapTokensForETH()");

        // Check this won't empty the pool of ETH
        uint amountETH = eth_reserves.sub(k.div(token_reserves.add(amountTokens)));
        require (amountETH < eth_reserves, "swapTokensForETH() would empty ETH pool");

        // Check max_exchange_rate not breached
        require(max_exchange_rate >= priceETH(), "swapTokensForETH(): max exchange rate breached");

        // Transfer: (1) ETH from exchange to sender; (2) tokens from sender to exchange
        (bool sent, bytes memory data) = msg.sender.call{value: amountETH}("");        
        require(sent, "Failed to send Ether back to sender in swapTokensForETH()");  
        token.transferFrom(msg.sender, address(this), amountTokens);
        
        // Update values
        eth_reserves = eth_reserves.sub(amountETH);
        token_reserves = token_reserves.add(amountTokens);

        /***************************/
        // DO NOT MODIFY BELOW THIS LINE
        // Check for x * y == k, assuming x and y are rounded to the nearest integer.
        // Check for Math.abs(token_reserves * eth_reserves - k) < (token_reserves + eth_reserves + 1));
        // to account for the small decimal errors during uint division rounding.
        uint check = token_reserves.mul(eth_reserves);
        if (check >= k) {
            check = check.sub(k);
        }
        else {
            check = k.sub(check);
        }
        assert(check < (token_reserves.add(eth_reserves).add(1)));
        k = token_reserves.mul(eth_reserves); // avoid rounding errors by re'calc-ing k
        emit Debug("swapTokensForETH() finished");
    }

    // Function swapETHForTokens: Swaps ETH for your tokens.
    // ETH is sent to contract as msg.value.
    // You can change the inputs, or the scope of your function, as needed.
    function swapETHForTokens(uint max_exchange_rate) external payable 
    {
        /* HINTS:
           Part 4: 
                Expand the function to take in addition parameters as needed.
                If current exchange_rate > slippage limit, abort the swap. 
            
            Part 5: 
                Only exchange amountTokens * (1 - %liquidity), 
                    where % is sent to liquidity providers.
                Keep track of the liquidity fees to be added.
        */

        // Check tokens requested won't empty the pool
        uint amountTokens = token_reserves.sub(k.div(eth_reserves.add(msg.value)));
        require(amountTokens < token_reserves, "swapETHForTokens() would empty token pool");        
        
        // Check max_exchange_rate not breached
        require(max_exchange_rate >= priceToken(), "swapETHForTokens(): max exchange rate breached");
        
        // Transfer tokens to sender
        token.transfer(msg.sender, amountTokens);
        
        // Update values
        token_reserves = token_reserves.sub(amountTokens);
        eth_reserves = eth_reserves.add(msg.value);

        /**************************/
        // DO NOT MODIFY BELOW THIS LINE
        // Check for x * y == k, assuming x and y are rounded to the nearest integer
        // Check for Math.abs(token_reserves * eth_reserves - k) < (token_reserves + eth_reserves + 1));
        //   to account for the small decimal errors during uint division rounding.
        uint check = token_reserves.mul(eth_reserves);
        if (check >= k) {
            check = check.sub(k);
        }
        else {
            check = k.sub(check);
        }
        assert(check < (token_reserves.add(eth_reserves).add(1)));        
        k = token_reserves.mul(eth_reserves); // avoid rounding errors by re'calc-ing k

        emit Debug("swapETHForTokens() finished");
    }

    // ============================================================
    //                    HELPER FUNCTIONS
    // ============================================================
     
     // converts amountETH into equivalent tokens at current exchange rate
     // completed with long-form math to minimize uint division errors
     function ETHToTokens(uint amountETH) public view returns (uint)
     {
        return amountETH.mul(token_reserves).mul(float_converter).div(eth_reserves).div(float_converter);
     }

     // converts amountTokens into equivalent ETH at current exchange rate
     // completed with long-form math to minimize uint division errors
     function TokensToETH(uint amountTokens) public view returns (uint)
     {
        return amountTokens.mul(eth_reserves).mul(float_converter).div(token_reserves).div(float_converter);
     }
}