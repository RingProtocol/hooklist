// SPDX-License-Identifier: MIT
// Qian Exchange - https://qian.ag
pragma solidity ^0.8.24;

// Factory Errors
error BadRouterConfig();
error DeployDisabled();
error InsufficientDeployFee();
error InvalidFeeVault();
error InvalidConfig();
error InvalidReceiver();
error InvalidTickRange();
error NotController();
error Unauthorized();
error TransferFailed();
error MintingDisabled();
error InsufficientTokenBalance(uint256 required, uint256 available);

// Hook Registry Errors
error HookNotApproved();
error HookAlreadyConfigured();
error InvalidTaxRate();
error InvalidThreshold();
error InvalidPoolFee();
