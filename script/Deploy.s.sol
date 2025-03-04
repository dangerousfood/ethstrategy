// SPDX-License-Identifier: Apache 2.0
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {AtmAuction} from "../src/AtmAuction.sol";
import {BondAuction} from "../src/BondAuction.sol";
import {EthStrategy} from "../src/EthStrategy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Deposit} from "../src/Deposit.sol";
import {NavOptions} from "../src/NavOptions.sol";
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
        uint256 timelockDelay;
        uint256 votingDelay;
        uint256 voteExtension;
        uint256 votingPeriod;
    }

    struct DepositConfig {
        uint128 cap;
        uint256 conversionRate;
        uint64 duration;
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
        console2.log("depositDuration: ", config.deposit.duration);
        console2.log("depositSigner: ", config.deposit.signer);
        console2.log("depositStartTime: ", config.deposit.startTime);

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        address deployer = vm.addr(vm.envUint("PRIVATE_KEY"));
        console2.log("deployer: ", deployer);

        EthStrategy ethStrategy = new EthStrategy(
            uint32(config.governor.timelockDelay),
            config.governor.quorumPercentage,
            uint48(config.governor.voteExtension),
            uint48(config.governor.votingDelay),
            uint32(config.governor.votingPeriod),
            config.governor.proposalThreshold
        );
        AtmAuction atmAuction = new AtmAuction(address(ethStrategy), config.atmAuction.lst, address(0));
        BondAuction bondAuction = new BondAuction(address(ethStrategy), config.bondAuction.usdc, address(0));
        Deposit deposit = new Deposit(address(ethStrategy), address(0), config.deposit.signer, config.deposit.cap);
        deposit.startAuction(
            config.deposit.startTime,
            config.deposit.duration,
            config.deposit.conversionRate,
            config.deposit.conversionRate,
            config.deposit.cap
        );
        NavOptions navOptions = new NavOptions(address(ethStrategy));
        ethStrategy.grantRoles(address(atmAuction), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(bondAuction), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(navOptions), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(deposit), ethStrategy.MINTER_ROLE());
        ethStrategy.grantRoles(address(deposit), ethStrategy.GOV_INIT_ADMIN_ROLE());
        ethStrategy.transferOwnership(address(ethStrategy));
        deposit.renounceRoles(deposit.DA_ADMIN_ROLE());

        vm.stopBroadcast();

        string memory deployments = "deployments";

        vm.serializeAddress(deployments, "EthStrategy", address(ethStrategy));
        vm.serializeAddress(deployments, "AtmAuction", address(atmAuction));
        vm.serializeAddress(deployments, "BondAuction", address(bondAuction));
        vm.serializeAddress(deployments, "NavOptions", address(navOptions));
        string memory deploymentsJson = vm.serializeAddress(deployments, "Deposit", address(deposit));

        string memory deployedConfig = "config";
        vm.serializeAddress(deployedConfig, "deployer", deployer);
        vm.serializeUint(deployedConfig, "DepositCap", config.deposit.cap);
        vm.serializeUint(deployedConfig, "DepositConversionRate", config.deposit.conversionRate);
        vm.serializeUint(deployedConfig, "DepositDuration", config.deposit.duration);
        vm.serializeAddress(deployedConfig, "DepositSigner", config.deposit.signer);
        vm.serializeUint(deployedConfig, "startBlock", block.number);
        vm.serializeAddress(deployedConfig, "lst", config.atmAuction.lst);
        vm.serializeUint(deployedConfig, "proposalThreshold", config.governor.proposalThreshold);
        vm.serializeUint(deployedConfig, "quorumPercentage", config.governor.quorumPercentage);
        vm.serializeAddress(deployedConfig, "usdc", config.bondAuction.usdc);
        vm.serializeUint(deployedConfig, "votingDelay", config.governor.votingDelay);
        vm.serializeUint(deployedConfig, "votingPeriod", config.governor.votingPeriod);
        vm.serializeUint(deployedConfig, "startTime", config.deposit.startTime);
        vm.serializeUint(deployedConfig, "voteExtension", config.governor.voteExtension);
        vm.serializeUint(deployedConfig, "timelockDelay", config.governor.timelockDelay);
        string memory deployedConfigJson = vm.serializeUint(deployedConfig, "startBlock", block.number);

        console.log(config.deposit.signer);

        vm.writeJson(deploymentsJson, "./out/deployments.json");
        vm.writeJson(deployedConfigJson, "./out/deployed.config.json");
    }
}
