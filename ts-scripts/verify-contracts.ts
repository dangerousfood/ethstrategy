import { exec } from 'child_process';
import { promises as fs } from 'node:fs';
import { zeroAddress } from 'viem';

const THREE_SECONDS = 3000;

// packages/contracts/out/Untitled.sol/Untitled.json
// eslint-disable-next-line @typescript-eslint/no-explicit-any

const getCompilerVersion = async(contractName: string):Promise<string> => {
  const data = await fs.readFile(`./out/${contractName}.sol/${contractName}.json`)
  const abi = JSON.parse(data);
  return abi.metadata.compiler.version
}

const getContractAddresses = async () => {
  const data = await fs.readFile('./out/deployments.json')
  const addresses = JSON.parse(data);
  console.log(addresses);

  const keys = Object.keys(addresses);
  for (const key of keys) {
    await verifyContractWithTimeout(key, addresses[key]);
  }
}

const getContractAddressesMap = async () => {
  const data = await fs.readFile('./out/deployments.json')
  return JSON.parse(data);
}

const verifyContractWithTimeout = async (contractName, address) => {
  await new Promise((resolve) => {
    setTimeout(async () => {
      await verifyContract(contractName, address);
      resolve(true);
    }, THREE_SECONDS);
  });
};

const getConfig = async () => {
  const data = await fs.readFile('./out/deployed.config.json')
  return JSON.parse(data);
}

getContractAddresses()

const verifyContract = async(
  contractName: string,
  address: string
) => {
  console.log(`Verifying ${contractName} at ${address}`);
  const config = await getConfig();

  const addressesMap = await getContractAddressesMap();
  const compilerVersion = await getCompilerVersion(contractName)
  let command = `forge verify-contract ${address} ${contractName} --compiler-version ${compilerVersion} --watch --verifier etherscan --etherscan-api-key ${process.env.ETHERSCAN_API_KEY} --chain-id ${process.env.CHAIN_ID} --rpc-url ${process.env.RPC_URL}`;

  if (contractName === 'AtmAuction') {
    command += ` --constructor-args $(cast abi-encode "constructor(address,address,address)" ${addressesMap.EthStrategy} ${config.lst} ${zeroAddress})`;
  }

  if (contractName === 'BondAuction') {
    command += ` --constructor-args $(cast abi-encode "constructor(address,address,address)" ${addressesMap.EthStrategy} ${config.usdc} ${zeroAddress})`;
  }

  if (contractName === 'EthStrategy') {
    command += ` --constructor-args $(cast abi-encode "constructor(uint32,uint256,uint48,uint48,uint32,uint256)" ${config.timelockDelay} ${config.quorumPercentage} ${config.voteExtension} ${config.votingDelay} ${config.votingPeriod} ${config.proposalThreshold} )`;
  }

  if (contractName === 'Deposit') {
    command += ` --constructor-args $(cast abi-encode "constructor(address,address,address,uint256)" ${addressesMap.EthStrategy} ${zeroAddress} ${config.DepositSigner} ${BigInt(config.DepositCap).toString()} )`;
  }

  if (contractName === 'NavOptions') {
    command += ` --constructor-args $(cast abi-encode "constructor(address)" ${addressesMap.EthStrategy} )`;
  }

  exec(command, (err, stdout) => {
    if (err) {
      console.error(err);
    }
    console.log(stdout);
  });
}
