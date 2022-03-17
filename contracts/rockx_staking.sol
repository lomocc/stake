// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./iface.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";


contract RockXStaking is ReentrancyGuard, Pausable, Ownable, Initializable {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Address for address payable;
    using Address for address;
    using SafeMath for uint256;

    /**
        Incorrect storage preservation:

        |Implementation_v0   |Implementation_v1        |
        |--------------------|-------------------------|
        |address _owner      |address _lastContributor | <=== Storage collision!
        |mapping _balances   |address _owner           |
        |uint256 _supply     |mapping _balances        |
        |...                 |uint256 _supply          |
        |                    |...                      |
        Correct storage preservation:

        |Implementation_v0   |Implementation_v1        |
        |--------------------|-------------------------|
        |address _owner      |address _owner           |
        |mapping _balances   |mapping _balances        |
        |uint256 _supply     |uint256 _supply          |
        |...                 |address _lastContributor | <=== Storage extension.
        |                    |...                      |
    */

    // Always extend storage instead of modifying it
    // Variables in implementation v0 
    // stored credentials
    struct ValidatorCredential {
        bytes pubkey;
        bytes signature;
    }

    uint256 internal constant DEPOSIT_SIZE = 32 ether;
    uint256 internal constant MULTIPLIER = 1e18; 
    uint256 internal constant DEPOSIT_AMOUNT_UNIT = 1000000000 wei;
    uint256 internal constant SIGNATURE_LENGTH = 96;

    address public ethDepositContract;  // ETH 2.0 Deposit contract
    address public xETHAddress;         // xETH token address

    uint256 public managerFeeMilli = 100;   // manger's fee in 1/1000
    bytes32 public withdrawalCredentials;   // WithdrawCredential for all validator
    
    // credentials, pushed by owner
    ValidatorCredential [] public validatorRegistry;

    // next validator id
    uint256 public nextValidatorId;

    // track user staking
    uint256 public totalStaked;             // track total staked ethers for validators, rounded to 32 ethers
    uint256 public totalDeposited;          // track total deposited ethers from users..
    uint256 public totalWithdrawed;         // track total withdrawed ethers

    // track revenue from validators to form exchange ratio
    uint256 public accountedUserRevenue;    // accounted shared user revenue
    uint256 public accountedManagerRevenue; // accounted manager's revenue

    /** 
     * ======================================================================================
     * 
     * SYSTEM SETTINGS, OPERATED VIA OWNER(DAO/TIMELOCK)
     * 
     * ======================================================================================
     */

    /**
     * @dev initialization address
     */
    function initialize(address xETHAddress_, address ethDepositContract_) public initializer onlyOwner {
        ethDepositContract = ethDepositContract_;
        xETHAddress = xETHAddress_;
    }

    /**
     * @dev register a validator
     */
    function registerValidator(bytes calldata pubkey, bytes calldata signature) external onlyOwner {
        require(signature.length == SIGNATURE_LENGTH);
        validatorRegistry.push(ValidatorCredential({pubkey:pubkey, signature:signature}));
    }

    /**
     * @dev register a batch of validators
     */
    function registerValidators(bytes [] calldata pubkeys, bytes [] calldata signatures) external onlyOwner {
        require(pubkeys.length == signatures.length, "length mismatch");
        uint256 n = pubkeys.length;
        for(uint256 i=0;i<n;i++) {
            validatorRegistry.push(ValidatorCredential({pubkey:pubkeys[i], signature:signatures[i]}));
        }
    }
    
    /**
     * @dev set manager's fee in 1/1000
     */
    function setManagerFeeMilli(uint256 milli) external onlyOwner {
        require(milli >=0 && milli <=1000);
        managerFeeMilli = milli;

        emit ManagerFeeSet(milli);
    }

    /**
     @dev set withdraw credential to receive revenue, usually this should be the contract itself.
     */
    function setWithdrawCredential(bytes32 withdrawalCredentials_) external onlyOwner {
        withdrawalCredentials = withdrawalCredentials_;
        emit WithdrawCredentialSet(withdrawalCredentials);
    } 

    /**
     * @dev receive revenue
     */
    receive() external payable {
        emit RewardReceived(msg.value);
    }
    
    /**
     * @dev report accounted revenue for all validators
     */
    function reportBalance(uint256 creditEthers) external onlyOwner {
        uint256 fee = creditEthers.mul(managerFeeMilli).div(1000);
        accountedManagerRevenue = accountedManagerRevenue.add(fee);

        accountedUserRevenue = accountedUserRevenue
                                .add(creditEthers)
                                .sub(fee);

        emit RevenueAccounted(creditEthers);
    }


    /**
     * @dev manager withdraw fees
     */
    function withdrawManagerFee(uint256 amount, address to) external nonReentrant onlyOwner {
        require(accountedManagerRevenue >= amount, "insufficient manager fee");
        require(_checkEthersBalance(amount), "insufficient ethers");
        accountedManagerRevenue = accountedManagerRevenue.sub(amount);
        payable(to).sendValue(amount);
    }

    /**
     * ======================================================================================
     * 
     * VIEW FUNCTIONS
     * 
     * ======================================================================================
     */

    /**
     * @dev return num of validator credential pushed
     */
    function getRegisteredValidatorss() external view returns (uint256) {
        return validatorRegistry.length;
    }

    /**
     * @dev return exchange ratio of xETH:ETH, multiplied by 1e18
     */
    function exchangeRatio() external view returns (uint256) {
        uint256 xETHAmount = IERC20(xETHAddress).totalSupply();
        uint256 ratio = totalDeposited.add(accountedUserRevenue)
                            .mul(MULTIPLIER)
                            .div(xETHAmount);
        return ratio;
    }
 
     /**
     * ======================================================================================
     * 
     * EXTERNAL FUNCTIONS
     * 
     * ======================================================================================
     */
    /**
     * @dev mint xETH with ETH
     */
    function mint() external payable nonReentrant whenNotPaused {
        require(msg.value > 0, "amount 0");

        // mint xETH while keep the exchange ratio invariant
        //
        // current_ethers = totalDeposited + accountedUserRevenue - totalWithdrawed
        // amount XETH to mint = xETH * (msg.value/current_ethers)
        //
        uint256 amountXETH = IERC20(xETHAddress).totalSupply();
        uint256 currentEthers = _currentEthers();
        uint256 toMint = msg.value;  // default exchange ratio 1:1
        if (currentEthers > 0) { // avert division overflow
            toMint = amountXETH.mul(msg.value)
                                .div(currentEthers); 
       }
        
        // sum total deposited ethers
        totalDeposited = totalDeposited.add(msg.value);
        uint256 numValidators = totalDeposited.sub(totalStaked).div(DEPOSIT_SIZE);

        // spin up n nodes
        for (uint256 i = 0;i<numValidators;i++) {
            _spinup();
        }

        // mint xETH
        IMintableContract(xETHAddress).mint(msg.sender, toMint);
    }

    /**
     * @dev redeem ETH by burning xETH with current exchange ratio, 
     * approve xETH to this contract first.
     *
     * amount xETH to burn:
     *      xETH * ethers_to_redeem/current_ethers
     *
     * redeem keeps the ratio invariant
     */
    function redeemUnderlying(uint256 ethersToRedeem) external nonReentrant {
        require(_checkEthersBalance(ethersToRedeem));

        uint256 totalXETH = IERC20(xETHAddress).totalSupply();
        uint256 xETHToBurn = totalXETH.mul(ethersToRedeem).div(_currentEthers());
        
        // transfer xETH from sender & burn
        IERC20(xETHAddress).safeTransferFrom(msg.sender, address(this), xETHToBurn);
        IMintableContract(xETHAddress).burn(xETHToBurn);

        // send ethers back to sender
        payable(msg.sender).sendValue(ethersToRedeem);
        totalWithdrawed = totalWithdrawed.add(ethersToRedeem);

        // emit amount withdrawed
        emit Redeemed(xETHToBurn, ethersToRedeem);
    }

    /**
     * @dev redeem ETH by burning xETH with current exchange ratio, 
     * approve xETH to this contract first.
     * 
     * amount ethers to return:
     *  current_ethers * xETHToBurn/ xETH
     *
     * redeem keeps the ratio invariant
     */
    function redeem(uint256 xETHToBurn) external nonReentrant {
        uint256 totalXETH = IERC20(xETHAddress).totalSupply();
        uint256 ethersToRedeem = _currentEthers().mul(xETHToBurn).div(totalXETH);
        require(_checkEthersBalance(ethersToRedeem));

        // transfer xETH from sender & burn
        IERC20(xETHAddress).safeTransferFrom(msg.sender, address(this), xETHToBurn);
        IMintableContract(xETHAddress).burn(xETHToBurn);

        // send ethers back to sender
        payable(msg.sender).sendValue(ethersToRedeem);
        totalWithdrawed = totalWithdrawed.add(ethersToRedeem);

        // emit amount withdrawed
        emit Redeemed(xETHToBurn, ethersToRedeem);
    }

    /** 
     * ======================================================================================
     * 
     * INTERNAL FUNCTIONS
     * 
     * ======================================================================================
     */

    /**
     * @dev returns totalDeposited + accountedUserRevenue - totalWithdrawed
     */
    function _currentEthers() internal view returns(uint256) {
        return totalDeposited.add(accountedUserRevenue).sub(totalWithdrawed);
    }

    /**
     * @dev check ethers withdrawble
     */
    function _checkEthersBalance(uint256 amount) internal view returns(bool) {
        uint256 pendingEthers = totalDeposited.sub(totalStaked);
        if (address(this).balance.sub(pendingEthers) >= amount) {
            return true;
        }
        return false;
    }

    /**
     * @dev spin up the node
     */
    function _spinup() internal {
        // emit a log
        emit ValidatorActivated(nextValidatorId);

        // deposit to ethereum contract
        require(nextValidatorId < validatorRegistry.length) ;

         // load credential
        ValidatorCredential memory cred = validatorRegistry[nextValidatorId];
        _stake(cred.pubkey, cred.signature);

        totalStaked += DEPOSIT_SIZE;
        nextValidatorId++;        
    }

    /**
    * @dev Invokes a deposit call to the official Deposit contract
    */
    function _stake(bytes memory _pubkey, bytes memory _signature) internal {
         // The following computations and Merkle tree-ization will make official Deposit contract happy
        uint256 value = DEPOSIT_SIZE;
        uint256 depositAmount = value.div(DEPOSIT_AMOUNT_UNIT);
        assert(depositAmount.mul(DEPOSIT_AMOUNT_UNIT) == value);    // properly rounded

        // Compute deposit data root (`DepositData` hash tree root) according to deposit_contract.sol
        bytes32 pubkeyRoot = sha256(_pad64(_pubkey));
        bytes32 signatureRoot = sha256(
            abi.encodePacked(
                sha256(BytesLib.slice(_signature, 0, 64)),
                sha256(_pad64(BytesLib.slice(_signature, 64, SIGNATURE_LENGTH.sub(64))))
            )
        );
        bytes32 depositDataRoot = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(pubkeyRoot, withdrawalCredentials)),
                sha256(abi.encodePacked(_toLittleEndian64(depositAmount), signatureRoot))
            )
        );
        

        IDepositContract(ethDepositContract).deposit{value:DEPOSIT_SIZE} (
            _pubkey, abi.encodePacked(withdrawalCredentials), _signature, depositDataRoot);

    }

    /**
      * @dev Padding memory array with zeroes up to 64 bytes on the right
      * @param _b Memory array of size 32 .. 64
      */
    function _pad64(bytes memory _b) internal pure returns (bytes memory) {
        assert(_b.length >= 32 && _b.length <= 64);
        if (64 == _b.length)
            return _b;

        bytes memory zero32 = new bytes(32);
        assembly { mstore(add(zero32, 0x20), 0) }

        if (32 == _b.length)
            return BytesLib.concat(_b, zero32);
        else
            return BytesLib.concat(_b, BytesLib.slice(zero32, 0, uint256(64).sub(_b.length)));
    }

    /**
      * @dev Converting value to little endian bytes and padding up to 32 bytes on the right
      * @param _value Number less than `2**64` for compatibility reasons
      */
    function _toLittleEndian64(uint256 _value) internal pure returns (uint256 result) {
        result = 0;
        uint256 temp_value = _value;
        for (uint256 i = 0; i < 8; ++i) {
            result = (result << 8) | (temp_value & 0xFF);
            temp_value >>= 8;
        }

        assert(0 == temp_value);    // fully converted
        result <<= (24 * 8);
    }

    /**
     * ======================================================================================
     * 
     * ROCKX SYSTEM EVENTS
     *
     * ======================================================================================
     */
    event ValidatorActivated(uint256 node_id);
    event RevenueAccounted(uint256 amount);
    event RewardReceived(uint256 amount);
    event ManagerAccountSet(address account);
    event ManagerFeeSet(uint256 milli);
    event Redeemed(uint256 amountXETH, uint256 amountETH);
    event WithdrawCredentialSet(bytes32 withdrawCredential);
}