// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FHE, ebool, euint8, externalEuint8} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

contract Hangman is ZamaEthereumConfig {
    uint8 public constant MAX_LIVES = 6;
    address public immutable gameMaster;

    struct Game {
        address player;
        euint8[] secret;
        ebool[] revealed;
        euint8[27] guessed; // 1..26
        uint8 lives;
        string category;
        bool secretSet;
        bool gameOver;
        bool won;
    }

    mapping(uint256 => Game) public games;
    uint256 public nextGameId;

    // EVENTS
    event GameStarted(uint256 indexed gameId, address indexed player);
    event SecretWordSet(uint256 indexed gameId, string category);
    event GuessSubmitted(uint256 indexed gameId, address indexed player, uint8 letter);
    event LetterRevealed(uint256 indexed gameId, uint256 index);
    event LifeDecreased(uint256 indexed gameId, uint8 livesLeft);
    event GameOver(uint256 indexed gameId, bool won);

    // MODIFIERS
    modifier onlyGameMaster() {
        require(msg.sender == gameMaster, "Not game master");
        _;
    }

    modifier onlyPlayer(uint256 gameId) {
        require(msg.sender == games[gameId].player, "Not player");
        _;
    }

    constructor() {
        gameMaster = msg.sender;
    }

    /// @notice Player starts a new game
    function startGame() external returns (uint256 gameId) {
        gameId = nextGameId++;

        games[gameId].player = msg.sender;
        games[gameId].lives = MAX_LIVES;

        emit GameStarted(gameId, msg.sender);
    }

    /// @notice Game master sets the secret word (encrypted numeric letters 1-26)
    function setSecretWord(
        uint256 gameId,
        string calldata category,
        externalEuint8[] calldata encryptedLetters,
        bytes calldata proof
    ) external onlyGameMaster {
        Game storage game = games[gameId];
        require(!game.secretSet, "Secret already set");
        require(encryptedLetters.length > 0, "Empty word");

        game.category = category;

        uint256 len = encryptedLetters.length;
        game.secret = new euint8[](uint8(len));
        game.revealed = new ebool[](uint8(len));

        for (uint8 i = 0; i < len; i++) {  
            game.secret[i] = FHE.fromExternal(encryptedLetters[i], proof);
            game.revealed[i] = FHE.asEbool(false);

            FHE.allowThis(game.secret[i]);
            FHE.allow(game.secret[i], game.player);

            FHE.allowThis(game.revealed[i]);
            FHE.allow(game.revealed[i], game.player);
        }

        game.secretSet = true;

        emit SecretWordSet(gameId, category);
    }

    /// @notice Player submits guess
    function submitGuess(
        uint256 gameId,
        uint8 clearLetter
    ) external onlyPlayer(gameId) {
        Game storage game = games[gameId];
        require(msg.sender != address(0), "Invalid address");
        require(game.secretSet, "Not initialized");
        require(!game.gameOver, "Game over");
        require(game.lives > 0, "No lives left");
        require(clearLetter >= 1 && clearLetter <= 26, "Invalid letter");

        // Allow player to decrypt guess off-chain
        FHE.allow(game.guessed[clearLetter], game.player);
        FHE.allowThis(game.guessed[clearLetter]);

        emit GuessSubmitted(gameId, msg.sender, clearLetter);
    }

    // VERIFIER ACTIONS
    function revealLetter(
        uint256 gameId,
        uint256 index
    ) external onlyGameMaster {
        Game storage game = games[gameId];
        require(!game.gameOver, "Game over");
        require(index < game.revealed.length, "Bad index");

        game.revealed[index] = FHE.asEbool(true);

        emit LetterRevealed(gameId, index);
    }

    function decreaseLife(uint256 gameId) external onlyGameMaster {
        Game storage game = games[gameId];
        require(!game.gameOver, "Game over");
        require(game.lives > 0, "No lives");

        game.lives -= 1;

        emit LifeDecreased(gameId, game.lives);

        if (game.lives == 0) {
            game.gameOver = true;
            game.won = false;

            emit GameOver(gameId, game.won);
        }
    }

    function setWon(uint256 gameId) external onlyGameMaster {
        Game storage game = games[gameId];
        require(!game.gameOver, "Game over");

        game.gameOver = true;
        game.won = true;

        emit GameOver(gameId, game.won);
    }
}
