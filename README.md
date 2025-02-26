# GreenEnergy Credits

A decentralized carbon credit trading and tracking platform built on Stacks blockchain using Clarity smart contracts.

## Overview

GreenEnergy Credits enables organizations and individuals to participate in carbon credit trading with transparent verification, offset tracking, and compliance reporting capabilities.

## Features

- **Credit Management**
  - Mint new carbon credits (admin controlled)
  - Transfer credits between accounts
  - Real-time balance tracking
  
- **Offset Tracking**
  - Record and verify carbon offsets
  - Historical offset data maintenance
  - Timestamp-based tracking

- **Reporting & Analytics**
  - View credit balances
  - Track total offsets
  - Monitor total credits in circulation

## Smart Contract Functions

### Public Functions

1. `mint-credits (amount uint) (recipient principal)`
   - Creates new carbon credits
   - Restricted to contract owner
   - Parameters:
     - amount: Number of credits to mint
     - recipient: Address to receive credits

2. `transfer-credits (amount uint) (sender principal) (recipient principal)`
   - Transfers credits between accounts
   - Parameters:
     - amount: Number of credits to transfer
     - sender: Source address
     - recipient: Destination address

3. `record-offset (amount uint)`
   - Records carbon offset activities
   - Parameters:
     - amount: Quantity of carbon offset

### Read-Only Functions

1. `get-credit-balance (account principal)`
   - Returns credit balance for an account

2. `get-offset-total (account principal)`
   - Returns total offsets recorded for an account

3. `get-total-credits`
   - Returns total credits in circulation

## Error Codes

- `u100`: Owner-only operation
- `u101`: Invalid amount
- `u102`: Insufficient balance

