# RockX Liquid Staking

## Usage

### 0. Repo clone

```
$ git clone https://github.com/RockX-SG/stake
```

### 1. Create API KEY 
Visit [access.rockx.com](https://access.rockx.com), and create an Ethereum API KEY

### 2. Install brownie 
Visit [brownie](https://eth-brownie.readthedocs.io/en/stable/quickstart.html), install brownie environment.

### 3. Follow: [brownie-integration](https://rockx.gitbook.io/rockx-access-node-manual/brownie-integration) to setup brownie network
```
$brownie networks modify mainnet host=https://eth.w3node.com/\$ROCKX_API_KEY/api provider=rockx

Brownie v1.18.1 - Python development framework for Ethereum

SUCCESS: Network 'Mainnet' has been modified
  └─Mainnet
    ├─id: mainnet
    ├─chainid: 1
    ├─explorer: https://api.etherscan.io/api
    ├─host: https://eth.w3node.com/$ROCKX_API_KEY/api
    ├─multicall2: 0x5BA1e12693Dc8F9c48aAD8770482f4739bEeD696

$ export ROCKX_API_KEY=<YOUR API KEY>
```

### 4. Deploy to mainnet-fork
```
$cd src
$brownie run scripts/ganache_deploy.py --network mainnet-fork -I
```


### 5. Official deployment
mainnet
```
UNIVERSAL_ETH_ADDRESS: '0xF1376bceF0f78459C0Ed0ba5ddce976F1ddF51F4'
STAKING_ADDRESS: '0x4beFa2aA9c305238AA3E0b5D17eB20C045269E9d'
REDEEM_ADDRESS: '0x98169228cB99Ed26c1043eD8Ca53A5Cb371D3B8D'
PROXY_ADMIN: '0xa5F2B6AB5B38b88Ba221741b3A189999b4c889C6'
```

goerli
```
UNIVERSAL_ETH_ADDRESS: '0xB4f4231fC4Be7A34f0a1BE046538793Dc8D99c0E'
STAKING_ADDRESS: '0xa6E1a466626Db4927C197468026fa0A54c092492'
REDEEM_ADDRESS: '0xc6928Af206b0ABe57354D901dfB6Ca3EC4ecC5E3'
```

### 6. Error Codes from contracts
1. SYS001: PHASE_MISMATCH
1. SYS002: PHASE_ROLLBACK 
1. SYS003: INCONSISTENT_SIG_LEN
1. SYS004: INCONSISTENT_PUBKEY_LEN 
1. SYS005: DUPLICATED_PUBKEY
1. SYS006: PUBKEY_NOT_EXSITS
1. SYS007: LENGTH_NOT_EQUAL
1. SYS008: SHARE_OUT_OF_RANGE
1. SYS009: REGISTRY_DEPLETED
1. SYS010: WITHDRAW_EXCEEDED_MANAGER_REVENUE
1. SYS011: INSUFFICIENT_ETHERS 
1. SYS012: CASUALITY_VIOLATION
1. SYS013: VALIDATOR_COUNT_MISMATCH
1. SYS014: ALIVE_BALANCE_DECREASED
1. SYS015: NOT_ENOUGH_REVENUE
1. SYS016: MALICIOUS_PUSH
1. SYS017: EMPTY_CALLDATA
1. SYS018: REPORTED_MORE_STOPPED_VALIDATORS
1. SYS019: INSUFFICIENT_ETHERS_ARRIVED
1. SYS020: ID_ALREADY_STOPPED
1. SYS021: MALICIOUS_UNSTAKED_VALUE
1. SYS022: EMPTY_QUEUE
1. SYS023: DEBT_CONTRACT_NOT_SET
1. SYS024: WITHDRAWAL_CREDENTIALS_NOT_SET
1. USR001: TRANSACTION_EXPIRED
1. USR002: MINT_ZERO
1. USR003: NEED_KYC_FOR_MORE
1. USR004: EXCHANGE_RATIO_MISMATCH
1. USR005: REDEEM_NOT_IN_32ETHERS
