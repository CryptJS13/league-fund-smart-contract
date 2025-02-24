# League Fund Smart Contracts

This repository contains the smart contracts for the League Fund project, developed using [Foundry](https://book.getfoundry.sh/), a fast and portable toolkit for Ethereum application development.

## Project Structure

- **`src/`**: Main smart contract source code.
- **`lib/`**: External library dependencies.
- **`script/`**: Deployment and utility scripts.
- **`test/`**: Test files for the smart contracts.

## Getting Started

### Prerequisites

- Ensure you have [Foundry installed](https://book.getfoundry.sh/getting-started/installation.html).

### Installation

1. **Clone the Repository**:
   ```sh
   git clone https://github.com/leaguefund/league-fund-smart-contract.git
   cd league-fund-smart-contract
   ```


2. **Install Dependencies**:
   ```sh
   forge install
   ```


3. **Set Up Environment Variables**:
   - Duplicate `.env.example` and rename it to `.env`.
   - Fill in the necessary environment variables in the `.env` file.

## Usage

### Building Contracts

Compile the smart contracts:


```sh
forge build
```


### Running Tests

Execute the test suite:


```sh
forge test --fork-url sepolia
```


### Deployment

To deploy contracts, use the provided scripts in the `script/` directory. For example:


```sh
forge script script/DeployContract.s.sol --rpc-url sepolia --broadcast
```

## Resources

- [Foundry Documentation](https://book.getfoundry.sh/)
