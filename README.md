# Stake

## Usage

### 1. Create a new [infura.io](infura.io) project

### 2. Startup a new [geth](https://geth.ethereum.org/) node

**python**:

```sh
pip install eth-brownie

export WEB3_INFURA_PROJECT_ID=<Your Infura PROJECT ID>
./run.sh
```

or run with **docker**

```sh
export WEB3_INFURA_PROJECT_ID=<Your Infura PROJECT ID>
docker-compose up -d
```

### 3. Open Metamask, add the network `http://localhost:8545`
