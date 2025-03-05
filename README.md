### **EthStrategy ($ETHXR)**

#### **What is it?**

EtherStrategy (\$ETHXR) is a tokenized vehicle for ETH accumulation, giving \$ETHXR holders a claim on a growing pool of ETH managed through fully transparent, onchain strategies.

Think of EtherStrategy as **MicroStrategy, but entirely onchain and transparent**. If you’re familiar with how MicroStrategy operates, you already get the gist.

---

### **TL;DR**

1. **Deposit Pool:**  
   * The protocol starts with an initial ETH pool funded by early depositors.  
   * Early backers receive $ETHXR tokens, aligning their incentives with the protocol’s growth.
   * Global deposit cap at 10,000 $ETH
   * Individual addresses capped at 100 $ETH
2. **Growth Mechanisms:**  
   * **Convertible Bonds:** Users buy bonds with USDC. Proceeds are used to buy ETH, growing the pool and increasing $ETHXR’s value.  
   * **ATM Offerings:** If $ETHXR trades at a premium to NAV, new tokens are sold at the market price. Proceeds are used to acquire more ETH.  
   * **Net Asset Value (NAV) Options** \$oETHxr is an options contract that can be minted by governance that allows a holder to mint \$ETHXR by exchanging a proportional amount of NAV tokens relative to the total supply of $ETHXR
   * **Redemptions:** If $ETHXR trades at a discount to NAV, holders can vote to redeem ETH.

   ---

### **How It Works**

#### **1\. Convertible Bonds (USDC for ETH Acquisition):**

EtherStrategy raises funds by issuing **onchain convertible bonds**, which are structured as follows:

* **Initial Offering:**  
  * Bonds are sold at a fixed price in USDC with a maturity date and a strike price in $ETHXR.  
* **Conversion Option:**  
  * At maturity, bondholders can convert bonds into $ETHXR tokens if the token’s market price exceeds the strike price.  
  * Conversion is performed onchain, allowing bondholders to capture appreciation in $ETHXR’s value.  
* **Redemption Option:**  
  * If $ETHXR’s market price does not exceed the strike price, bondholders can redeem the bonds for their principal in USDC, potentially with a fixed yield.  
* **Protocol Benefits:**  
  * USDC raised is immediately used to buy ETH, growing the pool and boosting $ETHXR’s NAV.  
  * Conversion aligns bondholder incentives with the protocol’s long-term success.

  ---

#### **2\. At-The-Money (ATM) Offerings:**

If $ETHXR trades at a **premium to NAV**, EtherStrategy issues new tokens to capture demand and grow the ETH pool.

* **Mechanism:**  
  * New $ETHXR tokens are sold at the market price, capped at a percentage per week to maintain upside for existing holders.  
  * Proceeds are used to buy ETH and add it to the pool.  
* **Benefits:**  
  * Prevents runaway premiums by issuing tokens only when $ETHXR is overvalued.  
  * Scales the ETH pool efficiently, increasing NAV for all holders.

#### **3\. Net Asset Value (NAV) Options:**
* **Mechanism:**
  * Allows the governance to reward contributors or other parties like market makers for their contributions
* **Benefits:**  
  * Zero cost to the platform and are only valuable if $ETHXR exogenously trades at a premium to NAV 

#### **4\. Governance:**
* **Mechanism:**
  * From genesis, $ETHXR holders are in complete control of the protocol
  * $ETHXR is both the token representing the net asset value and the governance token
  * Protocol is designed to be egalitarian and takes no fee on deposits or redemption
  * Governance is vulnerable to a 51% attack, to mitigate this governance includes a rage quit functionality
    * One of these conditions are true:
      * Token transfers are paused by governance
      * Proposal succeeds and is in queue within the 24 hour execution delay before execution
          * $ETHXR holder or their delegate voted no or did not cast a vote (casting an abstain vote will not allow you to rage quit)
* **Benefits:** 
  * Self determination of the protocol

## Setup

```shell
git submodule update --init --recursive
mv .env.sample .env
# set your variables in .env
pnpm i
forge build
```

## Test
```shell
forge test
```

## Coverage Report
```shell
pnpm report
```

## Deploy Contracts

**Test**
```shell
pnpm deploy:test
```

**Production**
```shell
pnpm deploy:prod
```

## Verify Contracts on Etherscan
```shell
pnpm verify
```

Copyright 2025 EthStrategy Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.