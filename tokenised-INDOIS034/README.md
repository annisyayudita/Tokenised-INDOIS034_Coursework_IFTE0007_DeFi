# Tokenised INDOIS034 Coursework

This repository contains a proof of concept of a smart contract for a tokenised fractional ownership certificate referencing **Indonesia's 5.20% Global Sukuk (Sharia/Islamic Bond) due 02 July 2034 (INDOIS034)**.

## Scope

This project is a **coursework prototype** showing how a fungible token could represent fractional ownership in an **off-chain holding** of the selected INDOIS 2034 series.

> The smart contract  is a testnet proof of concept for a fungible digital certificate representing fractional ownership in an off-chain holding of Indonesia's 5.20% Global Sukuk (Sharia/Islamic Bond) due 02 July 2034 (INDOIS034).

## Overview

| Parameter | Value |
|---|---|
| **Token Name** | Tokenized INDOIS034 |
| **Symbol** | tINDOIS34 |
| **Standard** | ERC-20 (OpenZeppelin v5) |
| **Decimals** | 0 (1 token = 1 whole unit) |
| **1 Token** | USD 100 face-value exposure |
| **Coupon** | 5.20% p.a., semi-annual |
| **Maturity** | 2 July 2034 |
| **Network** | Ethereum Sepolia Testnet |

## Deployed testnet contract

- **Contract Name:** TokenizedIndois2034
- **Network:** Sepolia Testnet
- **Smart Contract Address (CA):** `0x62669938948fa30fc7909682fe85c1d6c854e467`
- **Compiler Version:** Solidity 0.8.24
- **Deployment Transaction Hash:** `0xc0c155f9378690753858bb8939102b14f21594fb16b5ccbf4008eeefda5728a6`
- **Block Explorer:** `https://sepolia.etherscan.io/address/0x62669938948fa30fc7909682fe85c1d6c854e467`

## Underlying reference asset

- **Asset:** Indonesia Global Sukuk (Sharia/Islamic Bond) 5.20% due 2 July 2034 (INDOIS034)
- **ISIN:** USY68613AB73 (Reg S line, 10-year tranche)
- **Product form:** USD sovereign global sukuk
- **Token design:** fungible token (ERC-20)
- **Conceptual backing:** fractional beneficial-interest certificate over an off-chain holding

## Token design assumptions

- **1 token = USD 100 face-value exposure** to the underlying sukuk
- Traditional market access is assumed to remain much higher than this tokenised threshold
- The underlying sukuk pays **semi-annually**
- The smart contract uses **ETH as a mock testnet settlement asset** 

## Contract features

### Core features
- ERC-20 fungible token with **0 decimals** 
- **AccessControl** with separate roles: `DEFAULT_ADMIN`, `DISTRIBUTOR`, `PAUSER`
- Admin minting backed by hypothetical off-chain holdings
- **Whitelist transfer restrictions** (compliance gated)
- **Pausable** — emergency freeze on transfers, distributions, and claims
- **ReentrancyGuard** — protection on all ETH sending functions

### Distribution features
- `depositDistribution(memo)` — admin deposits ETH to simulate a semi-annual profit event
- `claimDistribution()` — token holders claim their pro rata share; **ETH transfers on-chain**
- `withdrawableProfitOf(account)` / `accumulativeProfitOf(account)` — view claimable and total accumulated profit
- `accruedProfitPerTokenUSD18()` — informational daily accrual display, capped at one coupon interval (182 days)
- `expectedSemiAnnualProfitPerTokenUSD18()` — returns USD 2.60 per token per semi annual period
- **Coupon correction logic** (`magnifiedProfitCorrections`) — prevents double claiming when tokens are transferred after a distribution

### Redemption features
- `setRedemptionRateWeiPerToken(weiPerToken)` — admin sets maturity redemption rate
- `fundRedemptionPool()` — admin funds principal pool in ETH
- `redeemAtMaturity(tokenAmount)` — holders burn tokens and receive ETH payout; **auto claims any pending profit first**

## Contract architecture

```
TokenizedIndois2034 (ERC-20 + AccessControl + Pausable + ReentrancyGuard)
│
├── Roles
│   ├── DEFAULT_ADMIN_ROLE  — whitelist, mint, set rates, coupon clock
│   ├── DISTRIBUTOR_ROLE    — deposit distributions, fund redemption pool
│   └── PAUSER_ROLE         — pause / unpause
│
├── Compliance
│   ├── setWhitelist(account, bool)
│   ├── batchSetWhitelist(accounts[], bool)
│   └── _update() override — enforces whitelist + pause on every transfer
│
├── Token Lifecycle
│   ├── mint(to, amount)
│   ├── transfer / transferFrom (whitelist + pause gated)
│   └── redeemAtMaturity(amount) → burn + ETH payout
│
├── Profit Distribution (mock ETH)
│   ├── depositDistribution(memo) → payable, updates magnifiedProfitPerShare
│   ├── claimDistribution() → sends ETH to holder
│   ├── withdrawableProfitOf(account) / accumulativeProfitOf(account)
│   └── magnifiedProfitCorrections — anti double claim on transfer
│
├── Informational
│   ├── accruedProfitPerTokenUSD18() — daily accrual, capped at 182 days
│   └── expectedSemiAnnualProfitPerTokenUSD18() — returns 2.6e18
│
└── Admin Controls
    ├── pause() / unpause()
    ├── setCouponClock(timestamp)
    ├── setRedemptionRateWeiPerToken(weiPerToken)
    └── fundRedemptionPool() → payable
```

## Repository structure

```
tokenised-indois-2034/
├── contracts/
│   └── TokenizedIndois2034.sol    — main Solidity smart contract
├── screenshots/                   — Screenshots for smart contract address (CA) implementation on a test networ
│   └── README.txt               
└── README.md
```

## Constructor inputs

| Parameter | Type | Description |
|---|---|---|
| `_maturityTimestamp` | `uint256` | Unix timestamp in the future (e.g. `2035411200` for 2 July 2034) |
| `admin` | `address` | Admin wallet address (receives all roles + whitelist) |

## Testing and deployment workflow of smart contract address (CA) on a test network

The contract was developed in Remix. Preliminary logic checks could be performed in Remix VM, but the documented implementation evidence for this coursework is based on deployment and interaction on the Sepolia test network to obtain a valid public testnet contract address via MetaMask. The testing and deployment flow (minting, transfer, distribution) logic is as follows:

1. Create a MetaMask wallet & account
2. Switch MetaMask to Sepolia
3. Get free Sepolia ETH from a faucet ([Google Cloud Faucet](https://cloud.google.com/application/web3/faucet/ethereum/sepolia))
3. Open Remix, change environment to **Browser Extention** and select **Sepolia Testnet - MetaMask**
4. Deploy the contract (use `2035411200` for realistic 2034 maturity)
5. Whitelist a second wallet
6. Mint tokens
7. Transfer a portion of tokens
8. Deposit one mock distribution
9. Claim the distribution

## Screenshots of smart contract address (CA) implementation on the test network

| # | Screenshots |  File Name |
|---|---|---|
| 1 | Contract compiled successfully in Remix | `1_compile_success.png` |
| 2 | Contract deployed on Sepolia | `2_sepolia_deployment.png` |
| 3 | Deployed contract address visible | `3_contract_address-1.png` `3_contract_address-2.png`|
| 4 | Block details for the contract creation process| `4_sepolia_contract_creation_block_details.png` |
| 5 | Whitelist transaction | `5_whitelist_transaction.png` |
| 6 | Mint transaction | `6_mint_transaction.png` |
| 7 | Transfer transaction | `7_transfer_transaction.png` |
| 8 | Distribution deposit transaction | `8_distribution_deposit.png` |
| 9 | Profit claim transaction | `9_claim_distribution.png` |
| 10 | Sepolia block explorer page | `10_sepolia_block_explorer.png` |

## Coursework reference

IFTE0007 — Decentralised Finance and Blockchain, 2025–2026.

