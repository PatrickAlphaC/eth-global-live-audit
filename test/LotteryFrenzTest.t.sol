// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma experimental ABIEncoderV2;

import {Test, console} from "forge-std/Test.sol";
import {LotteryFrenz} from "../src/LotteryFrenz.sol";

contract LotteryFrenzTest is Test {
    LotteryFrenz lotteryFrenz;
    uint256 entranceFee = 1e18;
    address playerOne = address(1);
    address playerTwo = address(2);
    address playerThree = address(3);
    address playerFour = address(4);
    uint256 duration = 1 days;

    address owner = makeAddr("owner");

    address constant MAINNET_UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant MAINNET_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant MAINNET_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {
        vm.prank(owner);
        lotteryFrenz = new LotteryFrenz(
            entranceFee,
            duration,
            MAINNET_USDC,
            MAINNET_UNISWAP_V2_ROUTER,
            MAINNET_WETH
        );
    }

    //////////////////////
    /// EnterRaffle    ///
    /////////////////////

    function testCanEnterRaffle() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        lotteryFrenz.enterRaffle{value: entranceFee}(players);
        assertEq(lotteryFrenz.players(0), playerOne);
    }

    function testCantEnterWithoutPaying() public {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        vm.expectRevert("LotteryFrenz: Must send enough to enter raffle");
        lotteryFrenz.enterRaffle(players);
    }

    function testCanEnterRaffleMany() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        lotteryFrenz.enterRaffle{value: entranceFee * 2}(players);
        assertEq(lotteryFrenz.players(0), playerOne);
        assertEq(lotteryFrenz.players(1), playerTwo);
    }

    function testCantEnterWithoutPayingMultiple() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        vm.expectRevert("LotteryFrenz: Must send enough to enter raffle");
        lotteryFrenz.enterRaffle{value: entranceFee}(players);
    }

    function testCantEnterWithDuplicatePlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerOne;
        vm.expectRevert("LotteryFrenz: Duplicate player");
        lotteryFrenz.enterRaffle{value: entranceFee * 2}(players);
    }

    function testCantEnterWithDuplicatePlayersMany() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerOne;
        vm.expectRevert("LotteryFrenz: Duplicate player");
        lotteryFrenz.enterRaffle{value: entranceFee * 3}(players);
    }

    //////////////////////
    /// Refund         ///
    /////////////////////
    modifier playerEntered() {
        address[] memory players = new address[](1);
        players[0] = playerOne;
        lotteryFrenz.enterRaffle{value: entranceFee}(players);
        _;
    }

    function testCanGetRefund() public playerEntered {
        uint256 balanceBefore = address(playerOne).balance;
        uint256 indexOfPlayer = lotteryFrenz.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        lotteryFrenz.refund(indexOfPlayer);

        assertEq(address(playerOne).balance, balanceBefore + entranceFee);
    }

    function testGettingRefundRemovesThemFromArray() public playerEntered {
        uint256 indexOfPlayer = lotteryFrenz.getActivePlayerIndex(playerOne);

        vm.prank(playerOne);
        lotteryFrenz.refund(indexOfPlayer);

        assertEq(lotteryFrenz.players(0), address(0));
    }

    function testOnlyPlayerCanRefundThemself() public playerEntered {
        uint256 indexOfPlayer = lotteryFrenz.getActivePlayerIndex(playerOne);
        vm.expectRevert("LotteryFrenz: Only the player can refund");
        vm.prank(playerTwo);
        lotteryFrenz.refund(indexOfPlayer);
    }

    //////////////////////
    /// getActivePlayerIndex         ///
    /////////////////////
    function testGetActivePlayerIndexManyPlayers() public {
        address[] memory players = new address[](2);
        players[0] = playerOne;
        players[1] = playerTwo;
        lotteryFrenz.enterRaffle{value: entranceFee * 2}(players);

        assertEq(lotteryFrenz.getActivePlayerIndex(playerOne), 0);
        assertEq(lotteryFrenz.getActivePlayerIndex(playerTwo), 1);
    }

    //////////////////////
    /// selectWinner         ///
    /////////////////////
    modifier playersEntered() {
        address[] memory players = new address[](4);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = playerThree;
        players[3] = playerFour;
        lotteryFrenz.enterRaffle{value: entranceFee * 4}(players);
        _;
    }

    function testCantSelectWinnerBeforeRaffleEnds() public playersEntered {
        vm.expectRevert("LotteryFrenz: Raffle not over");
        lotteryFrenz.selectWinner();
    }

    function testCantSelectWinnerWithFewerThanFourPlayers() public {
        address[] memory players = new address[](3);
        players[0] = playerOne;
        players[1] = playerTwo;
        players[2] = address(3);
        lotteryFrenz.enterRaffle{value: entranceFee * 3}(players);

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        vm.expectRevert("LotteryFrenz: Need at least 4 players");
        lotteryFrenz.selectWinner();
    }

    function testSelectWinner() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        lotteryFrenz.selectWinner();
        assertEq(lotteryFrenz.previousWinner(), playerFour);
    }

    function testSelectWinnerGetsPaid() public playersEntered {
        uint256 balanceBefore = address(playerFour).balance;

        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPayout = ((entranceFee * 4) * 80 / 100);

        lotteryFrenz.selectWinner();
        assertEq(address(playerFour).balance, balanceBefore + expectedPayout);
    }

    //////////////////////
    /// withdrawFees         ///
    /////////////////////
    function testCantWithdrawFeesIfPlayersActive() public playersEntered {
        vm.expectRevert("LotteryFrenz: There are currently players active!");
        lotteryFrenz.withdrawFees();
    }

    function testWithdrawFees() public playersEntered {
        vm.warp(block.timestamp + duration + 1);
        vm.roll(block.number + 1);

        uint256 expectedPrizeAmount = ((entranceFee * 4) * 20) / 100;

        lotteryFrenz.selectWinner();
        lotteryFrenz.withdrawFees();
        assertEq(address(lotteryFrenz.owner()).balance, expectedPrizeAmount);
    }
}
