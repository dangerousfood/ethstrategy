### **EtherStrategy ($ETHSR)**

#### **What is it?**

EtherStrategy (\$ETHSR) is a tokenized vehicle for ETH accumulation, giving \$ETHSR holders a claim on a growing pool of ETH managed through fully transparent, onchain strategies.

Think of EtherStrategy as **MicroStrategy, but entirely onchain and transparent**. If you’re familiar with how MicroStrategy operates, you already get the gist.

**Note:** To maximize efficiency and capture staking yield, EtherStrategy will likely hold **wstETH** xinstead of plain ETH.

---

### **TL;DR**

1. **Seed Pool:**  
   * The protocol starts with an initial ETH pool funded by early depositors.  
   * Early backers receive $ETHSR tokens, aligning their incentives with the protocol’s growth.  
2. **Growth Mechanisms:**  
   * **Convertible Bonds:** Users buy bonds with USDC. Proceeds are used to buy ETH, growing the pool and increasing $ETHSR’s value.  
   * **ATM Offerings:** If $ETHSR trades at a premium to NAV, new tokens are sold at the market price. Proceeds are used to acquire more ETH.  
   * **Redemptions:** If $ETHSR trades at a discount to NAV, holders can vote to redeem ETH.

   ---

### **How It Works**

#### **1\. Convertible Bonds (USDC for ETH Acquisition):**

EtherStrategy raises funds by issuing **onchain convertible bonds**, which are structured as follows:

* **Initial Offering:**  
  * Bonds are sold at a fixed price in USDC with a maturity date and a strike price in $ETHSR.  
* **Conversion Option:**  
  * At maturity, bondholders can convert bonds into $ETHSR tokens if the token’s market price exceeds the strike price.  
  * Conversion is performed onchain, allowing bondholders to capture appreciation in $ETHSR’s value.  
* **Redemption Option:**  
  * If $ETHSR’s market price does not exceed the strike price, bondholders can redeem the bonds for their principal in USDC, potentially with a fixed yield.  
* **Protocol Benefits:**  
  * USDC raised is immediately used to buy ETH, growing the pool and boosting $ETHSR’s NAV.  
  * Conversion aligns bondholder incentives with the protocol’s long-term success.

  ---

#### **2\. At-The-Money (ATM) Offerings:**

If $ETHSR trades at a **premium to NAV**, EtherStrategy issues new tokens to capture demand and grow the ETH pool.

* **Mechanism:**  
  * New $ETHSR tokens are sold at the market price, capped at a percentage per week to maintain upside for existing holders.  
  * Proceeds are used to buy ETH and add it to the pool.  
* **Benefits:**  
  * Prevents runaway premiums by issuing tokens only when $ETHSR is overvalued.  
  * Scales the ETH pool efficiently, increasing NAV for all holders.

  ### 3. Minting $ETHSR to Cover Debt

In addition to the standard “convert or redeem” paths, EtherStrategy can mint new $ETHSR tokens to repay bondholders if the protocol chooses not to (or cannot) redeem the bonds in USDC. This ensures the protocol retains its ETH position without forced liquidation, at the cost of diluting existing token holders.

1. **Trigger Conditions**  
   - **Maturity or Default Scenario:** If the convertible bonds come due and the protocol lacks the USDC reserves—or prefers to preserve its ETH, governance can opt to mint new $ETHSR.  
   - **Market-Driven Decision:** If $ETHSR trades at or above a certain threshold, minting tokens may be cheaper (in opportunity cost) than liquidating ETH from the treasury.

2. **Implementation Details**  
   - **Onchain Governance Approval:** A governance vote can trigger the minting process, ensuring transparency.  
   - **Automated Smart Contract Flow:**
     1. Bondholders request repayment of principal at maturity.  
     2. The protocol decides to preserve ETH rather than sell to USDC.  
     3. The required amount of $ETHSR is minted and sold, USDC distributed to the bondholders.  

  - **Treasury Preservation:** No forced sales of ETH to cover debt.  
  
4. **Example Flow**  
   1. **Bond Maturity:** \$1M in convertible bonds comes due.  
   2. **DAO Vote:** Community opts to keep treasury ETH rather than selling it.  
   3. **Mint & Distribute:** \$1M worth of new $ETHSR is minted (based on the current token price) and sold.  
   4. **Outcome:**
      - The treasury retains its ETH, avoiding liquidation.  
      - Existing $ETHSR holders get diluted, but the protocol maintains its long-term rep.

By introducing this **mint-to-repay** option, EtherStrategy adds a final backstop for its convertible debt mechanism. All actions are transparent onchain and can be controlled by the community to ensure it aligns with the protocol’s long-term vision.


## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
