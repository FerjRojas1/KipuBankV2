// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* -------------------------------------------------------------------------- */
/*                                  IMPORTS                                   */
/* -------------------------------------------------------------------------- */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBankV2
 * @notice Optimized decentralized banking contract with multi-token support, price oracles and access control
 * @dev Secure vault system allowing deposits and withdrawals of ETH and ERC-20 tokens with capacity and withdrawal limits
 * @author Fernando Rojas
 */
contract KipuBankV2 is Ownable {
    using SafeERC20 for IERC20;

    /* -------------------------------------------------------------------------- */
    /*                                  VARIABLES                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Maximum total bank capacity expressed in USD
    uint256 public immutable i_bankCap;

    /// @notice Maximum allowed amount per individual withdrawal
    uint256 public immutable i_withdrawLimit;

    /// @notice Chainlink oracle for ETH/USD price
    AggregatorV3Interface public oracle;
    
    /// @notice Total accumulated value in the bank expressed in USD
    uint256 public s_totalUSDValue;

    /// @notice Balance mapping: token → user → amount
    mapping(address => mapping(address => uint256)) private balances;

    /// @notice Flag for reentrancy protection
    bool private locked;

    /// @notice Contract pause state
    bool public paused;
    
    /// @notice Mapping of specific oracles for ERC-20 tokens
    mapping(address => AggregatorV3Interface) public tokenOracles;

    /* -------------------------------------------------------------------------- */
    /*                                  EVENTS                                    */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when a user deposits funds
     * @param token Address of the deposited token (address(0) for ETH)
     * @param user Address of the user who deposited
     * @param amount Amount deposited
     * @param newBalance User's new balance for the token
     */
    event Deposit(address indexed token, address indexed user, uint256 amount, uint256 newBalance);

    /**
     * @notice Emitted when a user successfully withdraws funds
     * @param token Address of the withdrawn token (address(0) for ETH)
     * @param user Address of the user who withdrew
     * @param amount Amount withdrawn
     * @param newBalance User's new balance for the token
     */
    event Withdraw(address indexed token, address indexed user, uint256 amount, uint256 newBalance);

    /**
     * @notice Emitted when an oracle address is updated
     * @param token Address of the associated token (address(0) for ETH)
     * @param newOracle New oracle contract address
     */
    event OracleUpdated(address indexed token, address newOracle);

    /**
     * @notice Emitted when the contract pause state changes
     * @param paused New pause state (true = paused, false = active)
     */
    event PauseStateChanged(bool paused);

    /* -------------------------------------------------------------------------- */
    /*                                  ERRORS                                    */
    /* -------------------------------------------------------------------------- */

    /// @notice Error when attempting to operate with zero amount
    error ZeroAmount();

    /// @notice Error when exceeding maximum bank capacity
    error BankCapExceeded(uint256 bankCap, uint256 attempted);

    /// @notice Error when attempting to withdraw more than allowed limit
    error WithdrawLimitExceeded(uint256 limit, uint256 requested);

    /// @notice Error when user has insufficient balance
    error InsufficientBalance(uint256 available, uint256 requested);

    /// @notice Error when fund transfer fails
    error TransferFailed(address to, uint256 amount);

    /// @notice Error when invalid token address is provided
    error InvalidToken(address token);

    /// @notice Error when contract is in paused state
    error ContractPaused();

    /// @notice Error when invalid oracle address is provided
    error InvalidOracle();

    /// @notice Error when reentrancy attempt is detected
    error ReentrancyAttempt();

    /* -------------------------------------------------------------------------- */
    /*                                MODIFIERS                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Modifier to prevent reentrancy attacks
     * @notice Blocks concurrent executions of the same function
     */
    modifier nonReentrant() {
        if (locked) revert ReentrancyAttempt();
        locked = true;
        _;
        locked = false;
    }

    /**
     * @dev Modifier to validate that amount is not zero
     * @param amount Amount to validate
     */
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    /**
     * @dev Modifier to verify that contract is not paused
     */
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    /**
     * @dev Modifier to validate token addresses
     * @param token Token address to validate
     */
    modifier validToken(address token) {
        if (token == address(this)) revert InvalidToken(token);
        _;
    }

    /**
     * @dev Modifier to verify withdrawal limits
     * @param amount Amount to withdraw
     */
    modifier withinWithdrawLimit(uint256 amount) {
        if (amount > i_withdrawLimit) revert WithdrawLimitExceeded(i_withdrawLimit, amount);
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                               CONSTRUCTOR                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Initializes the banking contract with configuration parameters
     * @dev Limits are immutable to ensure consistency
     * @param _bankCap Maximum total bank capacity in USD
     * @param _withdrawLimit Maximum amount per individual withdrawal
     * @param _oracle Chainlink ETH/USD oracle address
     */
    constructor(uint256 _bankCap, uint256 _withdrawLimit, address _oracle) Ownable(msg.sender) {
        if (_bankCap == 0 || _withdrawLimit == 0) revert ZeroAmount();
        i_bankCap = _bankCap;
        i_withdrawLimit = _withdrawLimit;
        oracle = AggregatorV3Interface(_oracle);
        locked = false;
        paused = false;
    }

    /* -------------------------------------------------------------------------- */
    /*                             SPECIAL FUNCTIONS                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Receive function to accept ETH directly
     * @dev Executed when ETH is sent to the contract without data
     */
    receive() external payable whenNotPaused {
        _deposit(address(0), msg.sender, msg.value);
    }

    /**
     * @notice Fallback function to handle unrecognized calls
     * @dev Deposits ETH if sent with the transaction
     */
    fallback() external payable whenNotPaused {
        if (msg.value > 0) {
            _deposit(address(0), msg.sender, msg.value);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                             PUBLIC FUNCTIONS                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Allows depositing ETH into the banking contract
     * @dev The amount to deposit is sent as transaction value
     */
    function depositETH() 
        external 
        payable 
        nonReentrant 
        validAmount(msg.value)
        whenNotPaused 
    {
        _deposit(address(0), msg.sender, msg.value);
    }

    /**
     * @notice Allows depositing ERC-20 tokens into the banking contract
     * @dev Requires previous token approval
     * @param token Address of the ERC-20 token to deposit
     * @param amount Amount of tokens to deposit
     */
    function depositToken(address token, uint256 amount) 
        external 
        nonReentrant 
        validAmount(amount)
        validToken(token)
        whenNotPaused 
    {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _deposit(token, msg.sender, amount);
    }

    /**
     * @notice Allows withdrawing previously deposited ETH
     * @param amount Amount of ETH to withdraw (in wei)
     */
    function withdrawETH(uint256 amount) 
        external 
        nonReentrant 
        validAmount(amount)
        withinWithdrawLimit(amount)
        whenNotPaused 
    {
        uint256 userBalance = balances[address(0)][msg.sender];
        if (userBalance < amount) revert InsufficientBalance(userBalance, amount);
        
        _withdraw(address(0), msg.sender, amount);
    }

    /**
     * @notice Allows withdrawing previously deposited ERC-20 tokens
     * @param token Address of the ERC-20 token to withdraw
     * @param amount Amount of tokens to withdraw
     */
    function withdrawToken(address token, uint256 amount) 
        external 
        nonReentrant 
        validAmount(amount)
        validToken(token)
        withinWithdrawLimit(amount)
        whenNotPaused 
    {
        uint256 userBalance = balances[token][msg.sender];
        if (userBalance < amount) revert InsufficientBalance(userBalance, amount);
        
        _withdraw(token, msg.sender, amount);
    }

    /**
     * @notice Queries a user's balance for a specific token
     * @param token Token address (address(0) for ETH)
     * @param user User address
     * @return balance User's balance for the specified token
     */
    function balanceOf(address token, address user) external view returns (uint256 balance) {
        return balances[token][user];
    }

    /**
     * @notice Queries the total accumulated value in the bank in USD
     * @return totalUSD Total value in USD of all funds in the bank
     */
    function totalBankValueUSD() external view returns (uint256 totalUSD) {
        return s_totalUSDValue;
    }

    /**
     * @notice Gets the current ETH/USD price from Chainlink oracle
     * @return price Current ETH price in USD (with 8 decimals)
     */
    function getLatestETHPrice() public view returns (int256 price) {
        (, int256 currentPrice,,,) = oracle.latestRoundData();
        return currentPrice;
    }

    /**
     * @notice Gets the current price of a specific token from its oracle
     * @param token ERC-20 token address
     * @return price Current token price in USD
     */
    function getLatestTokenPrice(address token) public view returns (int256 price) {
        AggregatorV3Interface tokenOracle = tokenOracles[token];
        if (address(tokenOracle) == address(0)) revert InvalidOracle();
        
        (, int256 currentPrice,,,) = tokenOracle.latestRoundData();
        return currentPrice;
    }

    /* -------------------------------------------------------------------------- */
    /*                            INTERNAL FUNCTIONS                              */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Optimized internal logic for processing deposits
     * @param token Address of the deposited token
     * @param from Address of the user depositing
     * @param amount Amount deposited
     */
    function _deposit(address token, address from, uint256 amount) private {
        uint256 currentTotalUSD = s_totalUSDValue;
        uint256 usdValue = _convertToUSD(token, amount);
        uint256 newTotalUSD = currentTotalUSD + usdValue;
        
        if (newTotalUSD > i_bankCap) revert BankCapExceeded(i_bankCap, newTotalUSD);

        unchecked {
            balances[token][from] += amount;
            s_totalUSDValue = newTotalUSD;
        }

        emit Deposit(token, from, amount, balances[token][from]);
    }

    /**
     * @dev Optimized internal logic for processing withdrawals
     * @param token Address of the token to withdraw
     * @param from Address of the user withdrawing
     * @param amount Amount to withdraw
     */
    function _withdraw(address token, address from, uint256 amount) private {
        uint256 currentTotalUSD = s_totalUSDValue;
        uint256 usdValue = _convertToUSD(token, amount);
        uint256 newTotalUSD = currentTotalUSD - usdValue;

        unchecked {
            balances[token][from] -= amount;
            s_totalUSDValue = newTotalUSD;
        }

        if (token == address(0)) {
            (bool success, ) = payable(from).call{value: amount}("");
            if (!success) revert TransferFailed(from, amount);
        } else {
            IERC20(token).safeTransfer(from, amount);
        }

        emit Withdraw(token, from, amount, balances[token][from]);
    }

    /**
     * @dev Converts a token amount to its USD equivalent
     * @notice Uses Chainlink for ETH, specific oracles or 1:1 ratio for tokens
     * @param token Token address to convert
     * @param amount Amount to convert
     * @return usdValue Equivalent value in USD
     */
    function _convertToUSD(address token, uint256 amount) internal view returns (uint256 usdValue) {
        if (token == address(0)) {
            int256 ethPrice = getLatestETHPrice();
            return (amount * uint256(ethPrice)) / 1e18;
        } else {
            if (address(tokenOracles[token]) != address(0)) {
                int256 tokenPrice = getLatestTokenPrice(token);
                uint8 decimals = IERC20Metadata(token).decimals();
                return (amount * uint256(tokenPrice)) / (10 ** decimals);
            } else {
                return amount;
            }
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                           ADMINISTRATIVE FUNCTIONS                         */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Allows the owner to update the ETH/USD oracle
     * @param newOracle New oracle contract address
     */
    function setOracle(address newOracle) external onlyOwner {
        if (newOracle == address(0)) revert InvalidOracle();
        oracle = AggregatorV3Interface(newOracle);
        emit OracleUpdated(address(0), newOracle);
    }

    /**
     * @notice Allows the owner to configure oracles for specific tokens
     * @param token ERC-20 token address
     * @param oracleAddress Oracle address for the token
     */
    function setTokenOracle(address token, address oracleAddress) external onlyOwner {
        if (token == address(0) || oracleAddress == address(0)) revert InvalidOracle();
        tokenOracles[token] = AggregatorV3Interface(oracleAddress);
        emit OracleUpdated(token, oracleAddress);
    }

    /**
     * @notice Allows the owner to pause the contract in case of emergency
     * @dev Blocks all deposit and withdrawal operations
     */
    function pause() external onlyOwner {
        paused = true;
        emit PauseStateChanged(true);
    }

    /**
     * @notice Allows the owner to resume contract operations
     * @dev Reactivates all paused functions
     */
    function unpause() external onlyOwner {
        paused = false;
        emit PauseStateChanged(false);
    }

    /**
     * @notice Emergency function to withdraw trapped funds from the contract
     * @dev Only for exceptional use cases, exclusively by the owner
     * @param token Token address to withdraw (address(0) for ETH)
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = payable(owner()).call{value: amount}("");
            if (!success) revert TransferFailed(owner(), amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }
}