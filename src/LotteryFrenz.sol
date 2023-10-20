// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IUniswapV2Router01} from "./interfaces/IUniswapV2Router01.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title LotteryFrenz
/// @author LotteryFrenzDAO
/// @notice This project is to enter a raffle to win dat hella fresh $$$. The protocol should do the following:
/// 1. Call the `enterRaffle` function with the following parameters:
///    1. `address[] participants`: A list of addresses that enter. You can use this to enter yourself multiple times, or yourself and a group of your friends.
/// 2. Duplicate addresses are not allowed
/// 3. Users are allowed to get a refund of their ticket & `value` if they call the `refund` function
/// 4. Every X seconds, the raffle will be able to draw a winner
contract LotteryFrenz is Ownable {
    using Address for address payable;

    uint256 public immutable entranceFee;
    address public immutable usdc;
    address public immutable uniswapRouter;
    address public immutable weth;
    address[] public swapPath;

    address[] public players;
    uint256 public raffleDuration;
    uint256 public raffleStartTime;
    address public previousWinner;

    // We do some storage packing to save gas
    uint64 public totalFees = 0;

    // Events
    event RaffleEnter(address[] newPlayers);
    event RaffleRefunded(address player);

    /// @param _entranceFee the cost in wei to enter the raffle
    /// @param _raffleDuration the duration in seconds of the raffle
    /// @param _usdc the address of the USDC token
    /// @param _swapRouter the address of the uniswap router
    /// @param _weth the address of the WETH token
    constructor(uint256 _entranceFee, uint256 _raffleDuration, address _usdc, address _swapRouter, address _weth) {
        entranceFee = _entranceFee;
        raffleDuration = _raffleDuration;
        raffleStartTime = block.timestamp;
        usdc = _usdc;
        uniswapRouter = _swapRouter;
        weth = _weth;
        swapPath = new address[](2);
        swapPath[0] = _weth;
        swapPath[1] = _usdc;
    }

    /// @notice this is how players enter the raffle
    /// @notice they have to pay the entrance fee * the number of players
    /// @notice duplicate entrants are not allowed
    /// @param newPlayers the list of players to enter the raffle
    function enterRaffle(address[] memory newPlayers) public payable {
        require(msg.value == entranceFee * newPlayers.length, "LotteryFrenz: Must send enough to enter raffle");
        for (uint256 i = 0; i < newPlayers.length; i++) {
            players.push(newPlayers[i]);
        }

        // Check for duplicates
        for (uint256 i = 0; i < players.length - 1; i++) {
            for (uint256 j = i + 1; j < players.length; j++) {
                require(players[i] != players[j], "LotteryFrenz: Duplicate player");
            }
        }
        emit RaffleEnter(newPlayers);
    }

    /// @param playerIndex the index of the player to refund. You can find it externally by calling `getActivePlayerIndex`
    /// @dev This function will allow there to be blank spots in the array
    function refund(uint256 playerIndex) public {
        address playerAddress = players[playerIndex];
        require(playerAddress == msg.sender, "LotteryFrenz: Only the player can refund");
        require(playerAddress != address(0), "LotteryFrenz: Player already refunded, or is not active");

        payable(msg.sender).sendValue(entranceFee);

        players[playerIndex] = address(0);
        emit RaffleRefunded(playerAddress);
    }

    /// @notice a way to get the index in the array
    /// @param player the address of a player in the raffle
    /// @return the index of the player in the array, if they are not active, it returns 0
    function getActivePlayerIndex(address player) external view returns (uint256) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == player) {
                return i;
            }
        }
        return 0;
    }

    /// @notice this function will select a winner
    /// @notice there must be at least 4 players, and the duration has occurred
    /// @notice the previous winner is stored in the previousWinner variable
    /// @dev we use a hash of on-chain data to generate the random numbers
    /// @dev we reset the active players array after the winner is selected
    /// @dev we send 80% of the funds to the winner, the other 20% goes to the owner
    function selectWinner() external {
        require(block.timestamp >= raffleStartTime + raffleDuration, "LotteryFrenz: Raffle not over");
        require(players.length >= 4, "LotteryFrenz: Need at least 4 players");
        uint256 winnerIndex =
            uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp, block.difficulty))) % players.length;
        address winner = players[winnerIndex];
        uint256 totalAmountCollected = players.length * entranceFee;
        uint256 prizePool = (totalAmountCollected * 80) / 100;
        uint256 fee = (totalAmountCollected * 20) / 100;
        totalFees = totalFees + uint64(fee);

        delete players;
        raffleStartTime = block.timestamp;
        previousWinner = winner;
        (bool success,) = winner.call{value: prizePool}("");
        require(success, "LotteryFrenz: Failed to send prize pool to winner");
    }

    /// @notice this function will withdraw the fees to the owner
    function withdrawFees() external {
        require(players.length == 0, "LotteryFrenz: There are currently players active!");
        uint256 feesToWithdraw = totalFees;

        totalFees = 0;

        (bool success,) = payable(owner()).call{value: feesToWithdraw}("");
        require(success, "LotteryFrenz: Failed to withdraw fees");
    }

    function withdrawTokens() external onlyOwner {
        uint256 amount = IERC20(usdc).balanceOf(address(this));
        bool success = IERC20(usdc).transfer(msg.sender, amount);
        require(success, "LotteryFrenz: Failed to withdraw tokens");
    }

    /// @notice this function will return true if the msg.sender is an active player
    function _isActivePlayer() internal view returns (bool) {
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == msg.sender) {
                return true;
            }
        }
        return false;
    }

    /// @notice swap the ETH for USDC to prevent currency risk on uniswapV2
    function sellProfitsForUsdc() public returns (uint256[] memory) {
        uint256 amount = address(this).balance;
        uint256[] memory amounts = IUniswapV2Router01(uniswapRouter).swapExactETHForTokens{value: amount}(
            0, swapPath, owner(), block.timestamp
        );
        return amounts;
    }
}
