pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {AtmAuction} from "../src/AtmAuction.sol";
import {BondAuction} from "../src/BondAuction.sol";
import {EthStrategy} from "../src/EthStrategy.sol";
import {EthStrategyGovernor} from "../src/EthStrategyGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Deposit} from "../src/Deposit.sol";
import {console} from "forge-std/console.sol";

contract Deploy is Script {
    struct Config {
        AtmAuctionConfig atmAuction;
        BondAuctionConfig bondAuction;
        DepositConfig deposit;
        GovernorConfig governor;
    }

    struct AtmAuctionConfig {
        address lst;
    }

    struct BondAuctionConfig {
        address usdc;
    }

    struct GovernorConfig {
        uint256 proposalThreshold;
        uint256 quorumPercentage;
        uint256 votingDelay;
        uint256 votingPeriod;
    }

    struct DepositConfig {
        uint256 cap;
        uint256 conversionPremium;
        uint256 conversionRate;
        address signer;
        uint64 startTime;
    }

    function run() public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deploy.config.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);
        Config memory config = abi.decode(data, (Config));

        console2.log("votingDelay: ", config.governor.votingDelay);
        console2.log("votingPeriod: ", config.governor.votingPeriod);
        console2.log("proposalThreshold: ", config.governor.proposalThreshold);
        console2.log("quorumPercentage: ", config.governor.quorumPercentage);
        console2.log("lst: ", config.atmAuction.lst);
        console2.log("usdc: ", config.bondAuction.usdc);
        console2.log("depositCap: ", config.deposit.cap);
        console2.log("depositConversionRate: ", config.deposit.conversionRate);
        console2.log("depositConversionPremium: ", config.deposit.conversionPremium);
        console2.log("depositSigner: ", config.deposit.signer);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address publicKey = vm.addr(vm.envUint("PRIVATE_KEY"));
        console2.log("publicKey: ", publicKey);

        EthStrategy ethStrategy = new EthStrategy(publicKey);
        EthStrategyGovernor ethStrategyGovernor = new EthStrategyGovernor(
            IVotes(address(ethStrategy)),
            config.governor.quorumPercentage,
            config.governor.votingDelay,
            config.governor.votingPeriod,
            config.governor.proposalThreshold
        );
        AtmAuction atmAuction =
            new AtmAuction(address(ethStrategy), address(ethStrategyGovernor), config.atmAuction.lst);
        BondAuction bondAuction =
            new BondAuction(address(ethStrategy), address(ethStrategyGovernor), config.bondAuction.usdc);
        Deposit deposit = new Deposit(
            address(ethStrategyGovernor),
            address(ethStrategy),
            config.deposit.signer,
            config.deposit.conversionRate,
            config.deposit.conversionPremium,
            config.deposit.cap,
            config.deposit.startTime
        );

        ethStrategy.grantRoles(address(atmAuction), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(bondAuction), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(deposit), ethStrategy.MINTER_ROLE());
        ethStrategy.mint(publicKey, 1);

        ethStrategy.transferOwnership(address(ethStrategyGovernor));

        vm.stopBroadcast();

        string memory deployments = "deployments";

        vm.serializeAddress(deployments, "EthStrategy", address(ethStrategy));
        vm.serializeAddress(deployments, "EthStrategyGovernor", address(ethStrategyGovernor));
        vm.serializeAddress(deployments, "AtmAuction", address(atmAuction));
        vm.serializeAddress(deployments, "BondAuction", address(bondAuction));
        string memory deploymentsJson = vm.serializeAddress(deployments, "Deposit", address(deposit));

        string memory deployedConfig = "config";
        vm.serializeAddress(deployedConfig, "deployer", publicKey);
        vm.serializeUint(deployedConfig, "DepositCap", config.deposit.cap);
        vm.serializeUint(deployedConfig, "DepositConversionRate", config.deposit.conversionRate);
        vm.serializeUint(deployedConfig, "DepositConversionPremium", config.deposit.conversionPremium);
        vm.serializeAddress(deployedConfig, "DepositSigner", config.deposit.signer);
        vm.serializeUint(deployedConfig, "startBlock", block.number);
        vm.serializeAddress(deployedConfig, "lst", config.atmAuction.lst);
        vm.serializeUint(deployedConfig, "proposalThreshold", config.governor.proposalThreshold);
        vm.serializeUint(deployedConfig, "quorumPercentage", config.governor.quorumPercentage);
        vm.serializeAddress(deployedConfig, "usdc", config.bondAuction.usdc);
        vm.serializeUint(deployedConfig, "votingDelay", config.governor.votingDelay);
        vm.serializeUint(deployedConfig, "votingPeriod", config.governor.votingPeriod);
        vm.serializeUint(deployedConfig, "startTime", config.deposit.startTime);
        string memory deployedConfigJson = vm.serializeUint(deployedConfig, "startBlock", block.number);

        console.log(config.deposit.signer);

        vm.writeJson(deploymentsJson, "./out/deployments.json");
        vm.writeJson(deployedConfigJson, "./out/deployed.config.json");
    }
}
