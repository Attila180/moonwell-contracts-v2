//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import "@utils/ChainIds.sol";
import "@protocol/utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Configs} from "@proposals/Configs.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// how to run locally:
///       DO_DEPLOY=true DO_VALIDATE=true forge script src/proposals/mips/mip-xwell/xwellDeployOptimism.sol:xwellDeployOptimism
/// @dev do not use MIP as a base to fork off of, it will not work
contract xwellDeployOptimism is HybridProposal, Configs, xWELLDeploy {
    using ChainIds for uint256;

    /// @notice the name of the proposal
    string public constant override name = "MIP xWELL Token Creation Optimism";

    /// @notice the buffer cap for the xWELL token on all chains
    uint112 public constant bufferCap = 100_000_000 * 1e18;

    /// @notice the rate limit per second for the xWELL token on all chains
    /// heals at ~19m per day if buffer is fully replenished or depleted
    /// this limit is used for the wormhole bridge adapters
    uint128 public constant rateLimitPerSecond = 1158 * 1e18;

    /// @notice the duration of the pause for the xWELL token on all chains
    /// once the contract has been paused, in this period of time, it will automatically
    /// unpause if no action is taken.
    uint128 public constant pauseDuration = 10 days;

    function primaryForkId() public pure override returns (uint256) {
        return OPTIMISM_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        /// --------------------------------------------------
        /// --------------------------------------------------
        /// ---------------- OPTIMISM NETWORK ----------------
        /// --------------------------------------------------
        /// --------------------------------------------------
        {
            address existingProxyAdmin = addresses.getAddress(
                "MRD_PROXY_ADMIN"
            );
            address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
            address temporalGov = addresses.getAddress("TEMPORAL_GOVERNOR");
            address relayer = addresses.getAddress("WORMHOLE_BRIDGE_RELAYER");

            (
                address xwellLogic,
                address xwellProxy,
                ,
                address wormholeAdapterLogic,
                address wormholeAdapter
            ) = deployBaseSystem(existingProxyAdmin);

            MintLimits.RateLimitMidPointInfo[]
                memory limits = new MintLimits.RateLimitMidPointInfo[](1);

            limits[0].bridge = wormholeAdapter;
            limits[0].rateLimitPerSecond = rateLimitPerSecond;
            limits[0].bufferCap = bufferCap;

            initializeXWell(
                xwellProxy,
                "WELL",
                "WELL",
                temporalGov,
                limits,
                pauseDuration,
                pauseGuardian
            );

            initializeWormholeAdapter(
                wormholeAdapter,
                xwellProxy,
                temporalGov,
                relayer,
                block.chainid.toMoonbeamWormholeChainId()
            );

            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                wormholeAdapter
            );
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_LOGIC",
                wormholeAdapterLogic
            );
            addresses.addAddress("xWELL_LOGIC", xwellLogic);
            addresses.addAddress("xWELL_PROXY", xwellProxy);

            printAddresses(addresses);
            addresses.resetRecordingAddresses();
        }
    }

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    /// ------------ MTOKEN MARKET ACTIVIATION BUILD ------------

    function build(Addresses addresses) public override {}

    /// no cross chain actions to run, so remove all code from this function
    /// @dev do not use MIP as a base to fork off of, it will not work
    function run(Addresses, address) public override(HybridProposal) {}

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public view override {
        /// do validation for base network, then do validation for moonbeam network
        //// ensure chainId is correct and non zero
        /// ensure correct owner

        /// --------------------------------------------------
        /// --------------------------------------------------
        /// ------------------ BASE NETWORK ------------------
        /// --------------------------------------------------
        /// --------------------------------------------------
        {
            address basexWellProxy = addresses.getAddress("xWELL_PROXY");
            address wormholeAdapter = addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY"
            );
            address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
            address temporalGov = addresses.getAddress("TEMPORAL_GOVERNOR");
            address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");

            assertEq(
                xWELL(wormholeAdapter).owner(),
                temporalGov,
                "wormhole bridge adapter owner is incorrect"
            );
            assertEq(
                address(
                    WormholeBridgeAdapter(wormholeAdapter).wormholeRelayer()
                ),
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
                "wormhole bridge adapter relayer is incorrect"
            );
            assertEq(
                WormholeBridgeAdapter(wormholeAdapter).gasLimit(),
                300_000,
                "wormhole bridge adapter gas limit is incorrect"
            );
            assertEq(
                xWELL(basexWellProxy).owner(),
                temporalGov,
                "temporal gov address is incorrect"
            );
            assertEq(
                xWELL(basexWellProxy).pendingOwner(),
                address(0),
                "pending owner address is incorrect"
            );

            /// ensure correct pause guardian
            assertEq(
                xWELL(basexWellProxy).pauseGuardian(),
                pauseGuardian,
                "pause guardian address is incorrect"
            );
            /// ensure correct pause duration
            assertEq(
                xWELL(basexWellProxy).pauseDuration(),
                pauseDuration,
                "pause duration is incorrect"
            );
            /// ensure correct rate limits
            assertEq(
                xWELL(basexWellProxy).rateLimitPerSecond(wormholeAdapter),
                rateLimitPerSecond,
                "rateLimitPerSecond is incorrect"
            );
            /// ensure correct buffer cap
            assertEq(
                xWELL(basexWellProxy).bufferCap(wormholeAdapter),
                bufferCap,
                "bufferCap is incorrect"
            );
            assertTrue(
                WormholeBridgeAdapter(wormholeAdapter).isTrustedSender(
                    block.chainid.toMoonbeamWormholeChainId(),
                    wormholeAdapter
                ),
                "trusted sender not trusted"
            );
            /// ensure correct wormhole adapter logic
            /// ensure correct wormhole adapter owner
            assertEq(
                WormholeBridgeAdapter(wormholeAdapter).owner(),
                temporalGov,
                "wormhole adapter owner is incorrect"
            );
            /// ensure correct wormhole adapter relayer
            /// ensure correct wormhole adapter wormhole id
            /// ensure proxy admin has correct owner
            /// ensure proxy contract owners are proxy admin
            assertEq(
                ProxyAdmin(proxyAdmin).owner(),
                temporalGov,
                "ProxyAdmin owner is incorrect"
            );
            assertEq(
                ProxyAdmin(proxyAdmin).getProxyAdmin(
                    ITransparentUpgradeableProxy(basexWellProxy)
                ),
                proxyAdmin,
                "Admin is incorrect basexWellProxy"
            );
            assertEq(
                ProxyAdmin(proxyAdmin).getProxyAdmin(
                    ITransparentUpgradeableProxy(wormholeAdapter)
                ),
                proxyAdmin,
                "Admin is incorrect wormholeAdapter"
            );
        }
    }

    function printAddresses(Addresses addresses) private view {
        (
            string[] memory recordedNames,
            ,
            address[] memory recordedAddresses
        ) = addresses.getRecordedAddresses();
        for (uint256 j = 0; j < recordedNames.length; j++) {
            console.log("{\n        'addr': '%s', ", recordedAddresses[j]);
            console.log("        'chainId': %d,", block.chainid);
            console.log(
                "        'name': '%s'\n}%s",
                recordedNames[j],
                j < recordedNames.length - 1 ? "," : ""
            );
        }
    }
}