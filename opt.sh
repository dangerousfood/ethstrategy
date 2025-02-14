#!/usr/bin/env bash

set -e

# Constants, run forge build --sizes first to see existing build size
# TODO Have a MAX_SIZE value for current build configuration?
TARGET_SIZE=2400
MIN_RUNS=10
# Explanation of MAX_RUNS: Etherscan does not support verifying contracts with more than 10,000,000 optimizer runs.
# Using a higher number might not affect the bytecode output, but verification might require "spoofing" the optimizer run count.
MAX_RUNS=$((2**16-1))
ENV_FILE=".env"

# Your Contract
TARGET_CONTRACT="EthStrategy"

# Variables
foundRuns=0

# Function to check if the optimizer is enabled
check_optimizer_status() {
    local optimizer_status
    optimizer_status=$(forge config | grep optimizer | head -n 1)
    if [ "$optimizer_status" != "optimizer = true" ]; then
        echo "Error: The optimizer is not enabled. Please enable it and try again."
        exit 1
    fi
}

# Function to try runs and check if the contract size is within the target
try_runs() {
    local runs=$1
    printf "Trying with FOUNDRY_OPTIMIZER_RUNS=%d\n" "$runs"
    local result
    result=$(FOUNDRY_OPTIMIZER_RUNS=$runs forge build --sizes 2>&1)
    if [ $? -ne 0 ]; then
        echo "Error running 'forge build --sizes'."
        exit 1
    fi
    local contractSize
    # TODO change grep hardcode value of Auctioneer to take passable argument or something to accept new contract names
    contractSize=$(echo "$result" | grep $TARGET_CONTRACT | head -n 1 | awk -F'|' '{print $3}' | awk '{print $1}')
    # remove non-digit newline characters, new lines, etc for integer comparision
    sanitized_contractSize="${contractSize//[$'\t\r\n ']}"
    [ "$(echo "$sanitized_contractSize<=$TARGET_SIZE" | bc)" -eq 1 ]
}

# Check optimizer status
check_optimizer_status

# Main logic using binary search
if try_runs $MAX_RUNS; then
    foundRuns=$MAX_RUNS
else
    while [ $MIN_RUNS -le $MAX_RUNS ]; do
        midRuns=$(( (MIN_RUNS + MAX_RUNS) / 2 ))

        if try_runs $midRuns; then
            printf "Success with FOUNDRY_OPTIMIZER_RUNS=%d and contract size %.3fKB\n" "$midRuns" "$contractSize"
            MIN_RUNS=$((midRuns + 1))
            foundRuns=$midRuns
        else
            printf "Failure with FOUNDRY_OPTIMIZER_RUNS=%d and contract size %.3fKB\n" "$midRuns" "$contractSize"
            MAX_RUNS=$((midRuns - 1))
        fi
    done
fi

printf "Highest FOUNDRY_OPTIMIZER_RUNS found: %d\n" "$foundRuns"

# Update or create the .env file
if [ -f "$ENV_FILE" ]; then
    if grep -q "^FOUNDRY_OPTIMIZER_RUNS=" "$ENV_FILE"; then
        awk -v runs="$foundRuns" '{gsub(/^FOUNDRY_OPTIMIZER_RUNS=.*/, "FOUNDRY_OPTIMIZER_RUNS="runs); print}' "$ENV_FILE" > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
    else
        echo "FOUNDRY_OPTIMIZER_RUNS=$foundRuns" >> "$ENV_FILE"
    fi
    printf "Updated %s with FOUNDRY_OPTIMIZER_RUNS=%d\n" "$ENV_FILE" "$foundRuns"
else
    printf "Error: %s not found.\n" "$ENV_FILE"
fi

echo "Solidity Optimizer value search completed"
exit 0
