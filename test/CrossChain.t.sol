// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Test} from "forge-std/Test.sol";
import {IRebaseToken} from "../src/IRebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IERC20} from "lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from
    "lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "lib/ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "lib/ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "lib/ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "lib/ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChain is Test {
    address owner = makeAddr("owner"); //创建owner
    address user = makeAddr("user");
    uint256 constant SEND_VALUE = 1e5;

    uint256 sepoliaFork; //创建fork
    uint256 arbSepoliaFork;
    CCIPLocalSimulatorFork ccipLocalSimulatorFork; //创建CCIP本地模拟
    RebaseToken rbtSepolia;
    RebaseToken rbtArbSepolia;
    Vault vault;
    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;

    Register.NetworkDetails sepoliaNetworkDetails; //Register用来保存不同链的环境信息。
    Register.NetworkDetails arbsepoliaNetworkDetails;

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia"); //创建并选择fork
        vm.selectFork(sepoliaFork); //选择网络
        arbSepoliaFork = vm.createFork("arb-sepolia"); //创建fork
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork(); //创建CCIP本地模拟
        vm.makePersistent(address(ccipLocalSimulatorFork)); //让合约地址在测试中保持“持久化状态，把部署的合约“带到所有 fork
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid); //获得Registry的信息
        vm.startPrank(owner); //用owner身份部署合约
        rbtSepolia = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rbtSepolia)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(rbtSepolia)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress, //RMN (Risk Management Network) Proxy 可升级
            sepoliaNetworkDetails.routerAddress
        );
        rbtSepolia.grantMintAndBurnRole(address(vault));
        rbtSepolia.grantMintAndBurnRole(address(sepoliaPool));
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(rbtSepolia)
        );
        //由 owner 调用时，把address(rbtSepolia)地址注册为管理员
        //RegistryModuleOwnerCustom：只有 token owner 才能调用 → 保障安全。
        //TokenAdminRegistry：确保每个 token 的 pool 是唯一的、合法的。
        //接受 rbtSepolia的 admin 角色。
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(rbtSepolia));

        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(rbtSepolia), address(sepoliaPool)
        ); //设置代币的池子
        vm.stopPrank();
        //换链重新设置
        vm.selectFork(arbSepoliaFork);
        arbsepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        rbtArbSepolia = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(rbtArbSepolia)),
            new address[](0),
            arbsepoliaNetworkDetails.rmnProxyAddress,
            arbsepoliaNetworkDetails.routerAddress
        );
        rbtArbSepolia.grantMintAndBurnRole(address(arbSepoliaPool));
        RegistryModuleOwnerCustom(arbsepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(rbtArbSepolia)
        );
        TokenAdminRegistry(arbsepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(rbtArbSepolia));
        TokenAdminRegistry(arbsepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(rbtArbSepolia), address(arbSepoliaPool)
        );

        //让两个池子链接
        vm.stopPrank();
        configureTokenPool(
            sepoliaFork,
            address(sepoliaPool),
            arbsepoliaNetworkDetails.chainSelector,
            address(arbSepoliaPool),
            address(rbtArbSepolia)
        );
        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaPool),
            address(rbtSepolia)
        );
    }
    //设置池子的cfg

    function configureTokenPool(
        uint256 fork,
        address tokenPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken
    ) public {
        vm.selectFork(fork);
        vm.prank(owner);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        /*struct ChainUpdate {
    uint64 remoteChainSelector; // ──╮ Remote chain selector
    bool allowed; // ────────────────╯ Whether the chain should be enabled
    bytes remotePoolAddress; //        Address of the remote pool, ABI encoded in the case of a remote EVM chain.
    bytes remoteTokenAddress; //       Address of the remote token, ABI encoded in the case of a remote EVM chain.
    RateLimiter.Config outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
    RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
    }*/
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePool),
            remoteTokenAddress: abi.encode(remoteToken),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(tokenPool).applyChainUpdates(chainsToAdd);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        /* struct EVM2AnyMessage {
    bytes receiver; // abi.encode(receiver address) for dest EVM chains
    bytes data; // Data payload
    EVMTokenAmount[] tokenAmounts; // Token transfers
    address feeToken; // Address of feeToken. address(0) means you will send msg.value.
    bytes extraArgs; // Populate this with _argsToBytes(EVMExtraArgsV2)
    }*/
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1); //设置跨链的几种token，这里只有一种
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge}); //设置每个token具体的地址和数量
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 300_000}))
        }); //设置message 一次跨链调用的“快递包裹”

        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message); //获取跨链fee
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee); //不能用startprank和stopprank因为这个
        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee); //批准router花费link代币
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge); //批准router花费rbt代币
        uint256 localBalanceBefore = localToken.balanceOf(user);
        vm.prank(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message); //router花费link代币发送rbt
        uint256 localBalanceAfter = localToken.balanceOf(user);
        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);
        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork); //切换到arb链以及arb接受的message
        assertEq(remoteToken.balanceOf(user), remoteBalanceBefore + amountToBridge);
    }

    function testBridgeAllTokens() public {
        vm.selectFork(sepoliaFork); //切换到sepolia
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        assertEq(rbtSepolia.balanceOf(user), SEND_VALUE);
        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbsepoliaNetworkDetails,
            rbtSepolia,
            rbtArbSepolia
        ); //发送跨链
    }
}
