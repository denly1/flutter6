import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'dart:math';

void main() async {
  final game = BattleshipGame();
  await game.start();
}

class BattleshipGame {
  final GameBoard playerBoard = GameBoard();
  final GameBoard aiBoard = GameBoard();
  final AIPlayer ai = AIPlayer();
  final StreamController<GameEvent> _eventController = StreamController<GameEvent>.broadcast();
  
  int playerShots = 0;
  int aiShots = 0;
  int playerHits = 0;
  int playerMisses = 0;
  int aiHits = 0;
  int aiMisses = 0;
  DateTime? gameStartTime;
  DateTime? gameEndTime;
  
  Stream<GameEvent> get events => _eventController.stream;

  Future<void> start() async {
    gameStartTime = DateTime.now();
    
    print('╔════════════════════════════════════════╗');
    print('║       МОРСКОЙ БОЙ - BATTLESHIP        ║');
    print('╚════════════════════════════════════════╝\n');
    
    _eventController.stream.listen((event) {
      print('📢 ${event.message}');
    });

    print('⚓ Расстановка кораблей...\n');
    
    await Future.delayed(Duration(milliseconds: 500));
    await playerBoard.placeShipsRandomly();
    _eventController.add(GameEvent('Ваши корабли расставлены!'));
    
    await Future.delayed(Duration(milliseconds: 500));
    await aiBoard.placeShipsRandomly();
    _eventController.add(GameEvent('Корабли противника расставлены!'));
    
    print('\n🎮 Игра началась!\n');
    
    await gameLoop();
  }

  Future<void> gameLoop() async {
    while (!playerBoard.allShipsSunk() && !aiBoard.allShipsSunk()) {
      displayBoards();
      
      await playerTurn();
      
      if (aiBoard.allShipsSunk()) {
        print('\n🎉 ПОБЕДА! Вы потопили все корабли противника!');
        displayStats();
        break;
      }
      
      await Future.delayed(Duration(milliseconds: 800));
      await aiTurn();
      
      if (playerBoard.allShipsSunk()) {
        print('\n💀 ПОРАЖЕНИЕ! Противник потопил все ваши корабли!');
        displayStats();
        break;
      }
    }
    
    _eventController.close();
  }

  void displayBoards() {
    print('\n┌─────────── ВАШ ФЛОТ ───────────┐  ┌───── ФЛОТ ПРОТИВНИКА ─────┐');
    
    print('    A B C D E F G H I J              A B C D E F G H I J');
    
    for (int i = 0; i < 10; i++) {
      String playerRow = '${i + 1}'.padLeft(2) + '  ';
      String aiRow = '${i + 1}'.padLeft(2) + '  ';
      
      for (int j = 0; j < 10; j++) {
        playerRow += playerBoard.getCellDisplay(i, j, showShips: true) + ' ';
        aiRow += aiBoard.getCellDisplay(i, j, showShips: false) + ' ';
      }
      
      print('$playerRow    $aiRow');
    }
    print('');
  }

  Future<void> playerTurn() async {
    print('🎯 Ваш ход! Введите координаты (например, A5):');
    
    while (true) {
      stdout.write('> ');
      String? input = stdin.readLineSync();
      
      if (input == null || input.isEmpty) {
        print('❌ Введите координаты!');
        continue;
      }
      
      input = input.toUpperCase().trim();
      
      if (!_validateInput(input)) {
        print('❌ Неверный формат! Используйте формат A1-J10');
        continue;
      }
      
      final coords = _parseCoordinates(input);
      final result = await aiBoard.processShot(coords.row, coords.col);
      playerShots++;
      
      if (result.alreadyShot) {
        print('⚠️  Вы уже стреляли в эту клетку!');
        continue;
      }
      
      if (result.hit) {
        playerHits++;
        if (result.sunk) {
          print('💥 ПОТОПИЛ! Корабль уничтожен!');
          _eventController.add(GameEvent('Игрок потопил корабль противника!'));
        } else {
          print('🔥 ПОПАДАНИЕ!');
          _eventController.add(GameEvent('Игрок попал в корабль!'));
        }
      } else {
        playerMisses++;
        print('💧 Мимо!');
        _eventController.add(GameEvent('Игрок промахнулся'));
      }
      
      break;
    }
  }

  Future<void> aiTurn() async {
    print('\n🤖 Ход противника...');
    await Future.delayed(Duration(milliseconds: 500));
    
    final coords = await ai.getNextMove(playerBoard);
    final result = await playerBoard.processShot(coords.row, coords.col);
    aiShots++;
    
    final cellName = '${String.fromCharCode(65 + coords.col)}${coords.row + 1}';
    
    if (result.hit) {
      aiHits++;
      if (result.sunk) {
        print('💥 Противник ПОТОПИЛ ваш корабль в клетке $cellName!');
        _eventController.add(GameEvent('ИИ потопил корабль игрока!'));
        ai.onSunk();
      } else {
        print('🔥 Противник попал в $cellName!');
        _eventController.add(GameEvent('ИИ попал в корабль игрока!'));
        ai.onHit(coords);
      }
    } else {
      aiMisses++;
      print('💧 Противник промахнулся ($cellName)');
      _eventController.add(GameEvent('ИИ промахнулся'));
    }
  }

  bool _validateInput(String input) {
    final regex = RegExp(r'^[A-J]([1-9]|10)$');
    return regex.hasMatch(input);
  }

  Coordinates _parseCoordinates(String input) {
    final col = input.codeUnitAt(0) - 65;
    final row = int.parse(input.substring(1)) - 1;
    return Coordinates(row, col);
  }

  Future<void> displayStats() async {
    gameEndTime = DateTime.now();
    final duration = gameEndTime!.difference(gameStartTime!);
    final winner = aiBoard.allShipsSunk() ? 'Игрок' : 'ИИ';
    
    print('\n╔════════════════════════════════════════════════════════╗');
    print('║              ИТОГОВАЯ СТАТИСТИКА                      ║');
    print('╠════════════════════════════════════════════════════════╣');
    print('║ Победитель: $winner | Время: ${duration.inMinutes}м ${duration.inSeconds % 60}с                  ║');
    print('╠════════════════════════════════════════════════════════╣');
    print('║ ИГРОК: Выстрелов $playerShots | Попаданий $playerHits | Промахов $playerMisses        ║');
    print('║        Точность ${playerShots > 0 ? (playerHits / playerShots * 100).toStringAsFixed(1) : 0}% | Потоплено ${aiBoard.sunkShips}/10 | Осталось ${10 - playerBoard.sunkShips}/10      ║');
    print('╠════════════════════════════════════════════════════════╣');
    print('║ ИИ: Выстрелов $aiShots | Попаданий $aiHits | Промахов $aiMisses | Точность ${aiShots > 0 ? (aiHits / aiShots * 100).toStringAsFixed(1) : 0}% ║');
    print('╚════════════════════════════════════════════════════════╝');
    
    await _saveStatsToFile(winner, duration);
  }
  
  Future<void> _saveStatsToFile(String winner, Duration duration) async {
    try {
      final dir = Directory('game_stats');
      if (!await dir.exists()) {
        await dir.create();
      }
      
      final timestamp = DateTime.now().toString().replaceAll(':', '-').replaceAll('.', '-');
      final file = File('game_stats/game_$timestamp.txt');
      
      final stats = StringBuffer();
      stats.writeln('═══════════════════════════════════════════════════════════');
      stats.writeln('           МОРСКОЙ БОЙ - СТАТИСТИКА ИГРЫ');
      stats.writeln('═══════════════════════════════════════════════════════════');
      stats.writeln('Дата и время: ${DateTime.now()}');
      stats.writeln('Победитель: $winner');
      stats.writeln('Продолжительность: ${duration.inMinutes}м ${duration.inSeconds % 60}с');
      stats.writeln('');
      stats.writeln('ИГРОК:');
      stats.writeln('  Всего выстрелов: $playerShots');
      stats.writeln('  Попаданий: $playerHits');
      stats.writeln('  Промахов: $playerMisses');
      stats.writeln('  Точность: ${playerShots > 0 ? (playerHits / playerShots * 100).toStringAsFixed(1) : 0}%');
      stats.writeln('  Потоплено кораблей противника: ${aiBoard.sunkShips}/10');
      stats.writeln('  Потеряно своих кораблей: ${playerBoard.sunkShips}/10');
      stats.writeln('  Осталось своих кораблей: ${10 - playerBoard.sunkShips}/10');
      stats.writeln('');
      stats.writeln('ПРОТИВНИК (ИИ):');
      stats.writeln('  Всего выстрелов: $aiShots');
      stats.writeln('  Попаданий: $aiHits');
      stats.writeln('  Промахов: $aiMisses');
      stats.writeln('  Точность: ${aiShots > 0 ? (aiHits / aiShots * 100).toStringAsFixed(1) : 0}%');
      stats.writeln('  Потоплено кораблей игрока: ${playerBoard.sunkShips}/10');
      stats.writeln('  Потеряно своих кораблей: ${aiBoard.sunkShips}/10');
      stats.writeln('  Осталось своих кораблей: ${10 - aiBoard.sunkShips}/10');
      stats.writeln('');
      stats.writeln('ИТОГ:');
      if (winner == 'Игрок') {
        stats.writeln('  Игрок победил, разрушив все ${aiBoard.sunkShips} кораблей противника');
        stats.writeln('  и потеряв ${playerBoard.sunkShips} своих кораблей.');
        stats.writeln('  На поле игрока осталось ${10 - playerBoard.sunkShips}/10 кораблей.');
      } else {
        stats.writeln('  ИИ победил, разрушив все ${playerBoard.sunkShips} кораблей игрока');
        stats.writeln('  и потеряв ${aiBoard.sunkShips} своих кораблей.');
        stats.writeln('  На поле ИИ осталось ${10 - aiBoard.sunkShips}/10 кораблей.');
      }
      stats.writeln('  За всю игру игрок сделал $playerHits попаданий и $playerMisses промахов.');
      stats.writeln('  За всю игру ИИ сделал $aiHits попаданий и $aiMisses промахов.');
      stats.writeln('═══════════════════════════════════════════════════════════');
      
      await file.writeAsString(stats.toString());
      print('\n💾 Статистика сохранена в файл: ${file.path}');
      
    } catch (e) {
      print('\n⚠️  Ошибка при сохранении статистики: $e');
    }
  }
}

class GameBoard {
  final List<List<Cell>> grid = List.generate(10, (i) => List.generate(10, (j) => Cell()));
  final List<Ship> ships = [];
  int sunkShips = 0;

  Future<void> placeShipsRandomly() async {
    final shipSizes = [4, 3, 3, 2, 2, 2, 1, 1, 1, 1];
    final random = Random();
    
    for (int size in shipSizes) {
      bool placed = false;
      int attempts = 0;
      
      while (!placed && attempts < 1000) {
        attempts++;
        final row = random.nextInt(10);
        final col = random.nextInt(10);
        final horizontal = random.nextBool();
        
        if (_canPlaceShip(row, col, size, horizontal)) {
          _placeShip(row, col, size, horizontal);
          placed = true;
        }
      }
      
      await Future.delayed(Duration(milliseconds: 50));
    }
  }

  bool _canPlaceShip(int row, int col, int size, bool horizontal) {
    if (horizontal) {
      if (col + size > 10) return false;
      for (int c = col; c < col + size; c++) {
        if (!_isCellFree(row, c)) return false;
      }
    } else {
      if (row + size > 10) return false;
      for (int r = row; r < row + size; r++) {
        if (!_isCellFree(r, col)) return false;
      }
    }
    return true;
  }

  bool _isCellFree(int row, int col) {
    for (int dr = -1; dr <= 1; dr++) {
      for (int dc = -1; dc <= 1; dc++) {
        final r = row + dr;
        final c = col + dc;
        if (r >= 0 && r < 10 && c >= 0 && c < 10) {
          if (grid[r][c].hasShip) return false;
        }
      }
    }
    return true;
  }

  void _placeShip(int row, int col, int size, bool horizontal) {
    final ship = Ship(size);
    
    if (horizontal) {
      for (int c = col; c < col + size; c++) {
        grid[row][c].hasShip = true;
        grid[row][c].ship = ship;
        ship.positions.add(Coordinates(row, c));
      }
    } else {
      for (int r = row; r < row + size; r++) {
        grid[r][col].hasShip = true;
        grid[r][col].ship = ship;
        ship.positions.add(Coordinates(r, col));
      }
    }
    
    ships.add(ship);
  }

  Future<ShotResult> processShot(int row, int col) async {
    await Future.delayed(Duration(milliseconds: 100));
    
    final cell = grid[row][col];
    
    if (cell.isHit || cell.isMiss) {
      return ShotResult(hit: false, sunk: false, alreadyShot: true);
    }
    
    if (cell.hasShip) {
      cell.isHit = true;
      cell.ship!.hits++;
      
      if (cell.ship!.isSunk()) {
        _markSunkShip(cell.ship!);
        sunkShips++;
        return ShotResult(hit: true, sunk: true);
      }
      
      return ShotResult(hit: true, sunk: false);
    } else {
      cell.isMiss = true;
      return ShotResult(hit: false, sunk: false);
    }
  }

  void _markSunkShip(Ship ship) {
    for (var pos in ship.positions) {
      for (int dr = -1; dr <= 1; dr++) {
        for (int dc = -1; dc <= 1; dc++) {
          final r = pos.row + dr;
          final c = pos.col + dc;
          if (r >= 0 && r < 10 && c >= 0 && c < 10) {
            if (!grid[r][c].hasShip) {
              grid[r][c].isMiss = true;
            }
          }
        }
      }
    }
  }

  String getCellDisplay(int row, int col, {required bool showShips}) {
    final cell = grid[row][col];
    
    if (cell.isHit) return '✗';
    if (cell.isMiss) return '·';
    if (showShips && cell.hasShip) return '▓';
    return '~';
  }

  bool allShipsSunk() => sunkShips >= ships.length;
}

class AIPlayer {
  final List<Coordinates> targetQueue = [];
  final List<Coordinates> hitPositions = [];
  final Random random = Random();

  Future<Coordinates> getNextMove(GameBoard board) async {
    final receivePort = ReceivePort();
    
    final gridState = List.generate(
      10,
      (i) => List.generate(10, (j) {
        final cell = board.grid[i][j];
        return cell.isHit ? 1 : (cell.isMiss ? 2 : 0);
      }),
    );
    
    final data = AIData(
      gridState: gridState,
      targetQueue: List.from(targetQueue),
      hitPositions: List.from(hitPositions),
    );
    
    await Isolate.spawn(_computeMove, IsolateMessage(receivePort.sendPort, data));
    
    final result = await receivePort.first as AIResult;
    
    targetQueue.clear();
    targetQueue.addAll(result.targetQueue);
    hitPositions.clear();
    hitPositions.addAll(result.hitPositions);
    
    return result.nextMove;
  }

  static void _computeMove(IsolateMessage message) {
    final data = message.data;
    final random = Random();
    Coordinates? nextMove;
    
    final targetQueue = List<Coordinates>.from(data.targetQueue);
    final hitPositions = List<Coordinates>.from(data.hitPositions);
    
    if (targetQueue.isNotEmpty) {
      nextMove = targetQueue.removeAt(0);
    } else if (hitPositions.isNotEmpty) {
      final lastHit = hitPositions.last;
      final adjacent = [
        Coordinates(lastHit.row - 1, lastHit.col),
        Coordinates(lastHit.row + 1, lastHit.col),
        Coordinates(lastHit.row, lastHit.col - 1),
        Coordinates(lastHit.row, lastHit.col + 1),
      ];
      
      for (var pos in adjacent) {
        if (pos.row >= 0 && pos.row < 10 && pos.col >= 0 && pos.col < 10) {
          if (data.gridState[pos.row][pos.col] == 0) {
            nextMove = pos;
            break;
          }
        }
      }
    }
    
    if (nextMove == null) {
      final available = <Coordinates>[];
      for (int i = 0; i < 10; i++) {
        for (int j = 0; j < 10; j++) {
          if (data.gridState[i][j] == 0) {
            available.add(Coordinates(i, j));
          }
        }
      }
      
      if (available.isNotEmpty) {
        nextMove = available[random.nextInt(available.length)];
      } else {
        nextMove = Coordinates(0, 0);
      }
    }
    
    final result = AIResult(
      nextMove: nextMove,
      targetQueue: targetQueue,
      hitPositions: hitPositions,
    );
    
    message.sendPort.send(result);
  }

  void onHit(Coordinates coords) {
    if (!hitPositions.contains(coords)) {
      hitPositions.add(coords);
      
      final adjacent = [
        Coordinates(coords.row - 1, coords.col),
        Coordinates(coords.row + 1, coords.col),
        Coordinates(coords.row, coords.col - 1),
        Coordinates(coords.row, coords.col + 1),
      ];
      
      for (var pos in adjacent) {
        if (pos.row >= 0 && pos.row < 10 && pos.col >= 0 && pos.col < 10) {
          if (!targetQueue.contains(pos)) {
            targetQueue.add(pos);
          }
        }
      }
    }
  }

  void onSunk() {
    hitPositions.clear();
    targetQueue.clear();
  }
}

class Cell {
  bool hasShip = false;
  bool isHit = false;
  bool isMiss = false;
  Ship? ship;
}

class Ship {
  final int size;
  int hits = 0;
  final List<Coordinates> positions = [];

  Ship(this.size);

  bool isSunk() => hits >= size;
}

class Coordinates {
  final int row;
  final int col;

  Coordinates(this.row, this.col);

  @override
  bool operator ==(Object other) =>
      other is Coordinates && row == other.row && col == other.col;

  @override
  int get hashCode => row.hashCode ^ col.hashCode;
}

class ShotResult {
  final bool hit;
  final bool sunk;
  final bool alreadyShot;

  ShotResult({required this.hit, required this.sunk, this.alreadyShot = false});
}

class GameEvent {
  final String message;
  GameEvent(this.message);
}

class IsolateMessage {
  final SendPort sendPort;
  final AIData data;

  IsolateMessage(this.sendPort, this.data);
}

class AIData {
  final List<List<int>> gridState;
  final List<Coordinates> targetQueue;
  final List<Coordinates> hitPositions;

  AIData({
    required this.gridState,
    required this.targetQueue,
    required this.hitPositions,
  });
}

class AIResult {
  final Coordinates nextMove;
  final List<Coordinates> targetQueue;
  final List<Coordinates> hitPositions;

  AIResult({
    required this.nextMove,
    required this.targetQueue,
    required this.hitPositions,
  });
}
