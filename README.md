# Fractional Ownership Platform
## Fractional Real Estate Ownership Smart Contract

A Clarity smart contract for managing fractional ownership of real estate assets on the Stacks blockchain. This contract enables property tokenization, shareholder voting, and automated rental income distribution.

## Features

### 🏠 Property Management
- **Property Initialization**: Set property valuation and define total ownership shares
- **Share Tokenization**: Mint NFTs representing fractional ownership stakes
- **Ownership Tracking**: Monitor share distribution and ownership percentages

### 💰 Rental Income Distribution
- **Income Deposits**: Secure deposit mechanism for rental income in STX
- **Automated Distribution**: Proportional distribution to shareholders based on ownership percentage
- **Fungible Token Tracking**: Track rental income using dedicated fungible tokens

### 🗳️ Governance System
- **Proposal Creation**: Allow stakeholders to create governance proposals
- **Voting Mechanism**: Secure voting system with time-based voting periods
- **Vote Tracking**: Comprehensive tracking of votes and voter participation

### 🔒 Security Features
- **Input Validation**: Comprehensive validation of all user inputs
- **Access Control**: Role-based access control with contract owner privileges
- **Bounds Checking**: Protection against malicious or extreme input values

## Contract Architecture

### Data Structures

#### Property Data
```clarity
;; Property state variables
(define-data-var property-initialized bool false)
(define-data-var total-shares uint u100)
(define-data-var property-valuation uint u0)
(define-data-var shares-minted bool false)
```

#### Tokens
- **NFT**: `ownership-share` - Represents fractional ownership stakes
- **FT**: `rental-income` - Tracks rental income distribution

#### Governance
```clarity
;; Proposal structure
{
  title: (string-ascii 128),
  description: (string-ascii 512),
  end-block: uint,
  votes-for: uint,
  votes-against: uint,
  executed: bool
}
```

## Usage

### 1. Property Initialization

```clarity
;; Initialize property with valuation and share count
(contract-call? .fractional-ownership-v1 initialize-property u50000000 u100)
```

### 2. Share Minting

```clarity
;; Mint initial shares (contract owner only)
(contract-call? .fractional-ownership-v1 mint-initial-shares)
```

### 3. Rental Income Management

```clarity
;; Deposit rental income
(contract-call? .fractional-ownership-v1 deposit-rental-income u1000000)

;; Distribute income to shareholders
(contract-call? .fractional-ownership-v1 distribute-income)
```

### 4. Governance

```clarity
;; Create a proposal
(contract-call? .fractional-ownership-v1 create-proposal 
  "Property Renovation" 
  "Proposal to renovate the kitchen and bathrooms" 
  u1440) ;; 10 days

;; Vote on a proposal
(contract-call? .fractional-ownership-v1 vote-on-proposal u1 true)
```

## API Reference

### Administrative Functions

#### `initialize-property`
Initializes property details and total ownership shares.

**Parameters:**
- `valuation` (uint): Property valuation (1M - 1T STX)
- `shares` (uint): Number of ownership shares (1 - 10,000)

**Returns:** `(response bool uint)`

#### `mint-initial-shares`
Mints initial ownership shares to contract owner.

**Returns:** `(response bool uint)`

#### `deposit-rental-income`
Deposits rental income into the contract.

**Parameters:**
- `amount` (uint): STX amount to deposit

**Returns:** `(response bool uint)`

#### `distribute-income`
Distributes rental income to shareholders proportionally.

**Returns:** `(response bool uint)`

### Governance Functions

#### `create-proposal`
Creates a new governance proposal.

**Parameters:**
- `title` (string-ascii 128): Proposal title
- `description` (string-ascii 512): Detailed description
- `voting-duration` (uint): Voting period in blocks (144 - 52,560)

**Returns:** `(response uint uint)`

#### `vote-on-proposal`
Allows shareholders to vote on proposals.

**Parameters:**
- `proposal-id` (uint): ID of the proposal
- `in-favor` (bool): Vote direction (true = for, false = against)

**Returns:** `(response bool uint)`

### Read-Only Functions

#### `get-property-details`
Returns property information.

**Returns:** `(response object uint)`

#### `get-proposal-details`
Returns details of a specific proposal.

**Parameters:**
- `proposal-id` (uint): Proposal ID

**Returns:** `(optional object)`

#### `has-voted`
Checks if a user has voted on a proposal.

**Parameters:**
- `voter` (principal): Voter's principal
- `proposal-id` (uint): Proposal ID

**Returns:** `bool`

#### `get-rental-income-balance`
Returns rental income token balance.

**Parameters:**
- `owner` (principal): Token holder's principal

**Returns:** `uint`

#### `get-share-owner`
Returns the owner of a specific share.

**Parameters:**
- `share-id` (uint): Share NFT ID

**Returns:** `(optional principal)`

#### `get-proposal-count`
Returns the total number of proposals created.

**Returns:** `uint`

## Security Considerations

### Input Validation
All user inputs are validated against defined bounds:
- Property valuation: 1M - 1T STX
- Share count: 1 - 10,000 shares
- Voting duration: 144 - 52,560 blocks (≈1 day to 1 year)
- String inputs: Non-empty, within size limits

### Access Control
- Contract owner has exclusive rights to initialize property and mint shares
- Only shareholders can vote on proposals
- Comprehensive error handling prevents unauthorized actions

### Economic Security
- Bounds checking prevents DoS attacks via extreme values
- Rental income distribution is proportional and transparent
- Voting mechanisms prevent double-voting and late voting

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 100 | `ERR-UNAUTHORIZED` | Unauthorized access attempt |
| 101 | `ERR-PROPOSAL-NOT-FOUND` | Proposal does not exist |
| 102 | `ERR-VOTING-CLOSED` | Voting period has ended |
| 103 | `ERR-ALREADY-VOTED` | User has already voted |
| 104 | `ERR-INVALID-SHARE-TOTAL` | Invalid share count |
| 105 | `ERR-PROPERTY-NOT-INITIALIZED` | Property not initialized |
| 106 | `ERR-SHARES-ALREADY-MINTED` | Shares already minted |
| 107 | `ERR-INSUFFICIENT-FUNDS` | Insufficient balance |
| 108 | `ERR-NOTHING-TO-DISTRIBUTE` | No income to distribute |
| 200 | `ERR-ALREADY-INITIALIZED` | Property already initialized |
| 201 | `ERR-INVALID-VALUATION` | Invalid property valuation |
| 202 | `ERR-INVALID-VOTING-DURATION` | Invalid voting duration |
| 203 | `ERR-INVALID-PROPOSAL-ID` | Invalid proposal ID |

## Development

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) v1.0.0+
- [Stacks CLI](https://github.com/blockstack/stacks-blockchain/tree/master/src/stacks-cli)

### Testing
```bash
# Check contract syntax and security
clarinet check

# Run unit tests
clarinet test

# Start local development environment
clarinet integrate
```

### Deployment
```bash
# Deploy to testnet
clarinet deploy --testnet

# Deploy to mainnet
clarinet deploy --mainnet
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Disclaimer

This smart contract is provided as-is for educational and development purposes. Ensure thorough testing and security auditing before deploying to production environments. The authors are not responsible for any financial losses or security vulnerabilities.