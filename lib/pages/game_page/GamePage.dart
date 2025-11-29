import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:get/get.dart';

import '../../models/Letter.dart';
import '../game_result_page/GameResultPage.dart';

class GamePage extends StatefulWidget {
  final String gameId;

  const GamePage({super.key, required this.gameId});

  @override
  _GamePageState createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  Map<String, String> board = {};
  List<String> bag = [];
  List<String> playerLetters = [];
  String? selectedLetter;
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;
  bool isMyTurn = false;
  String myUid = '';
  List<String> placedKeys = []; // Bu turda konan hücrelerin keyleri
  Map<String, dynamic> gameData = {};
  Timer? countdownTimer;
  Duration remainingTime = Duration.zero;
  String? selectedBoardTileKey;
  Map<String, String> jokerReplacements = {};
  StreamSubscription<DocumentSnapshot>? gameSubscription;
  bool placedNewLetter = false;
  bool movedExistingLetter = false;
  bool _isProcessing = false;
  Map<String, String> committedBoard = {};

  @override
  void dispose() {
    gameSubscription?.cancel();
    countdownTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    myUid = auth.currentUser!.uid;

    gameSubscription = firestore.collection('games').doc(widget.gameId).snapshots().listen((snapshot) {
      if (!snapshot.exists) return;

      if (_isProcessing) return;

      final data = snapshot.data();
      if (data == null) return;
      if (data['turnStartedAt'] == null) {
        gameData = data;
        return;
      }

      gameData = data;
      if (gameData['jokerReplacements'] != null) {
        if ((gameData['jokerReplacements'] as Map<String, dynamic>).length >= jokerReplacements.length) { // to avoid data inconsistency. because this is a stream. lokal datayla uyumsuzluk yaşamayalım
          jokerReplacements = Map<String, String>.from(gameData['jokerReplacements'] ?? {});
        }
      }

      // Eğer oyun bitmişse result page'e git
      if (gameData['status'] == 'finished') {
        final winner = gameData['winner'];
        final p1 = gameData['player1'];
        final p2 = gameData['player2'];
        final p1Score = gameData['player1Score'] ?? 0;
        final p2Score = gameData['player2Score'] ?? 0;

        if (ModalRoute.of(context)?.settings.name != '/game_result') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Get.off(() => GameResultPage(
              winner: winner,
              myUid: myUid,
              player1Score: p1Score,
              player2Score: p2Score,
              player1Id: p1,
              player2Id: p2,
            ));
          });
        }
        return;
      }

      setState(() {
        committedBoard = Map<String, String>.from(data['board'] ?? {});
        board = Map<String, String>.from(gameData['board'] ?? {});
        isMyTurn = gameData['turn'] == myUid;
        if (isMyTurn) startCountdownTimer();
        playerLetters = List<String>.from(
          gameData['player1'] == myUid ? gameData['player1Letters'] ?? [] : gameData['player2Letters'] ?? [],
        );
      });
    });
  }

  Future<void> clearUsedRewardEffects() async {
    final docRef = firestore.collection('games').doc(widget.gameId);
    final rewards = Map<String, dynamic>.from(gameData['rewards'] ?? {});
    final myUid = auth.currentUser!.uid;

    final Map<String, dynamic> updates = {};

    rewards.forEach((key, reward) {
      final status = reward['status'];
      final owner = reward['owner'];
      final activeEffect = reward['activeEffect'];

      if (status == 'used' && owner != myUid) {
        // Sadece rakibin kullandığı ödülleri temizleyeceğiz
        if (activeEffect != null) {
          updates['rewards.$key.activeEffect'] = FieldValue.delete();
        }
      }
    });

    if (updates.isNotEmpty) {
      await docRef.update(updates);
    }
  }

  Future<void> applyZoneBanReward(String rewardKey) async {
    final docRef = firestore.collection('games').doc(widget.gameId);

    final isPlayer1 = gameData['player1'] == myUid;
    final opponentUid = isPlayer1 ? gameData['player2'] : gameData['player1'];

    // Sol mu sağ mı diye sor
    final selectedZone = await Get.dialog<String>(
      AlertDialog(
        title: Text('Bölge Seçimi'),
        content: Text('Rakibin hangi tarafını yasaklamak istiyorsun?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: 'left'),
            child: Text('Sol'),
          ),
          TextButton(
            onPressed: () => Get.back(result: 'right'),
            child: Text('Sağ'),
          ),
        ],
      ),
    );

    if (selectedZone == null) return; // Seçim yapmadıysa iptal

    // rewards içindeki ilgili ödüle activeEffect ekle
    await docRef.update({
      'rewards.$rewardKey.activeEffect': {
        'target': opponentUid,
        'zone': selectedZone,
      },
      'rewards.$rewardKey.status': 'used',
    });

    Get.back();
  }

  void applyLetterBanReward(String rewardKey) async {
    final docRef = firestore.collection('games').doc(widget.gameId);
    final rewardPath = 'rewards.$rewardKey';

    final isPlayer1 = gameData['player1'] == myUid;
    final opponentUid = isPlayer1 ? gameData['player2'] : gameData['player1'];

    // Rakibin harfleri
    final opponentLetters = List<String>.from(
      gameData[isPlayer1 ? 'player2Letters' : 'player1Letters'] ?? [],
    );

    if (opponentLetters.length < 2) {
      Get.snackbar('Hata', 'Rakibin yeterli harfi yok.');
      return;
    }

    // Rastgele 2 harf seçelim
    opponentLetters.shuffle();
    final selected = opponentLetters.take(2).toList();

    await docRef.update({
      '$rewardPath.status': 'used',
      '$rewardPath.activeEffect': {
        'target': opponentUid,
        'letters': selected,
      },
    });

    Get.back();
  }

  void applyDoubleTurnReward(String rewardKey) async {
    final docRef = firestore.collection('games').doc(widget.gameId);
    final rewardPath = 'rewards.$rewardKey';

    await docRef.update({
      '$rewardPath.status': 'used',
      '$rewardPath.activeEffect': {
        'target': myUid,
      },
    });

    Get.back();
  }

  void surrender() async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: Text('Teslim Ol'),
        content: Text('Gerçekten teslim olmak istiyor musun?'),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: Text('Hayır')),
          TextButton(onPressed: () => Get.back(result: true), child: Text('Evet')),
        ],
      ),
    );

    if (confirm != true) return;

    final docRef = firestore.collection('games').doc(widget.gameId);
    final data = gameData;
    final isPlayer1 = data['player1'] == myUid;
    final opponent = isPlayer1 ? data['player2'] : data['player1'];

    await docRef.update({
      'status': 'finished',
      'winner': opponent,
      'player1Score': data['player1Score'] ?? 0,
      'player2Score': data['player2Score'] ?? 0,
    });

    Get.off(() => GameResultPage(
      winner: opponent,
      myUid: myUid,
      player1Score: data['player1Score'],
      player2Score: data['player2Score'],
      player1Id: data['player1'],
      player2Id: data['player2'],
    ));
  }

  Widget buildCountdownDisplay() {
    if (!isMyTurn || remainingTime == Duration.zero) return SizedBox();

    final hours = remainingTime.inHours.remainder(60).toString().padLeft(2, '0');
    final minutes = remainingTime.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = remainingTime.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        '$hours:$minutes:$seconds',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent),
      ),
    );
  }

  void startCountdownTimer() {
    countdownTimer?.cancel();

    if (gameData['status'] == 'finished') return;
    final initial = getRemainingTime(gameData);
    remainingTime = initial;

    countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        if (remainingTime.inSeconds > 0) {
          remainingTime -= Duration(seconds: 1);
        } else {
          timer.cancel();
          checkForTimeoutLoss();
        }
      });
    });
  }

  void showJokerSelectionModal(BuildContext context, String key) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        final letters = 'ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ'.split('');

        return Container(
          padding: EdgeInsets.all(16),
          child: Wrap(
            children: letters.map((char) {
              return InkWell(
                onTap: () {
                  jokerReplacements[key] = char;
                  Navigator.pop(context);
                },
                child: Container(
                  margin: EdgeInsets.all(4),
                  padding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(char, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  bool isTileBlocked(int x, int y) {
    final rewards = Map<String, dynamic>.from(gameData['rewards'] ?? {});

    for (final reward in rewards.values) {
      if (reward['type'] == 'zone_ban' &&
          reward['activeEffect'] != null &&
          reward['activeEffect']['target'] == myUid) {
        final zone = reward['activeEffect']['zone'];

        if (zone == 'left' && x < 7) return true;
        if (zone == 'right' && x > 7) return true;
      }
    }

    return false;
  }

  void handleBoardTap(int x, int y) async {
    if (isTileBlocked(x, y)) {
      Get.snackbar('Yasaklı Alan', 'Bu bölgeye hamle yapamazsın.', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final key = '${x}_${y}';

    // Elindeki harfi yerleştirme (klasik hamle)
    if (movedExistingLetter) {
      Get.snackbar('Hatalı Hamle', 'Taş kaydırdıktan sonra harf koyamazsın.');
      return;
    }

    if (selectedLetter != null && isMyTurn && (board[key]?.isEmpty ?? true)) {
      board[key] = selectedLetter!;
      playerLetters.remove(selectedLetter);
      placedKeys.add(key);

      if (selectedLetter == '*') {
        showJokerSelectionModal(context, key);
      }

      setState(() {
        selectedLetter = null;
        selectedBoardTileKey = null;
        placedNewLetter = true;
      });
      return;
    }

    final isEmpty = board[key]?.isEmpty ?? true;

    // Eğer seçili bir taş yoksa ve bu hücre doluysa taş seçimi yap
    if (selectedBoardTileKey == null && !isEmpty) {
      if (placedNewLetter) {
        Get.snackbar('Hatalı Hamle', 'Harf koyduktan sonra taşı kaydıramazsın.');
        return;
      }

      setState(() {
        selectedBoardTileKey = key;
      });
      return;
    }

    // Seçili taş varsa ve tıklanan boşsa taşı kaydırmayı dene
    if (selectedBoardTileKey != null && isEmpty) {
      final srcKey = selectedBoardTileKey!;
      final parts = srcKey.split('_');
      final sx = int.parse(parts[0]);
      final sy = int.parse(parts[1]);

      final dx = (sx - x).abs();
      final dy = (sy - y).abs();

      final isOneStep = (dx + dy == 1);

      if (!isOneStep) {
        Get.snackbar('Hatalı Hamle', 'Taşı sadece 1 kare yatay veya dikey hareket ettirebilirsin.');
        setState(() {
          selectedBoardTileKey = null;
        });
        return;
      }

      if (placedNewLetter) {
        Get.snackbar('Hatalı Hamle', 'Harf koyduktan sonra taşı kaydıramazsın.');
        setState(() {
          selectedBoardTileKey = null;
        });
        return;
      }

      // Harfi geçici olarak yeni yere koy
      final letter = board[srcKey]!;
      board[srcKey] = '';
      board[key] = letter;

      placedKeys.add(key); // simulate adding key from hand. workaround

      final words = findAllNewWords(board, placedKeys);
      if (words.isEmpty) {
        final diagonalWord = findSingleDiagonalWord(board, placedKeys);
        if (diagonalWord != null) {
          words.add(diagonalWord);
        }
      }

      var isValid = false;

      if (words.isNotEmpty) {
        final dictionary = await loadDictionary();
        isValid = words.every((wordInfo) => dictionary.contains(wordInfo.word));
      }

      if (isValid) {
        movedExistingLetter = true;

        final docRef = firestore.collection('games').doc(widget.gameId);
        final data = gameData;
        final isPlayer1 = data['player1'] == myUid;
        final opponent = isPlayer1 ? data['player2'] : data['player1'];

        await docRef.update({
          'board': board,
          'turn': opponent,
          'turnStartedAt': FieldValue.serverTimestamp(),
          'consecutivePasses': 0,
        });

        setState(() {
          selectedBoardTileKey = null;
          movedExistingLetter = false;
          placedNewLetter = false;
        });

        return;
      } else {
        // Geçersiz. harfi geri al
        placedKeys.clear();
        board[srcKey] = letter;
        board[key] = '';
        Get.snackbar('Geçersiz Hamle', 'Taşıdığın harf anlamlı bir kelime oluşturmalı.');
        movedExistingLetter = false;
        placedNewLetter = false;
      }

      setState(() {
        selectedBoardTileKey = null;
      });
    }
  }

  String getLetterAt(Map<String, dynamic> board, String key) {
    final raw = board[key] ?? '';
    return raw == '*' ? (jokerReplacements[key] ?? '*') : raw;
  }

  Duration getRemainingTime(Map<String, dynamic>? data) {
    if (data == null || data['turnStartedAt'] == null) {
      return Duration(minutes: 0);
    }
    final Timestamp turnStartedAt = data['turnStartedAt'];
    final DateTime started = turnStartedAt.toDate();

    final String durationString = data['duration'];

    Duration totalTime;
    switch (durationString) {
      case '2dk':
        totalTime = Duration(minutes: 2);
        break;
      case '5dk':
        totalTime = Duration(minutes: 5);
        break;
      case '12s':
        totalTime = Duration(hours: 12);
        break;
      case '24s':
        totalTime = Duration(hours: 24);
        break;
      default:
        totalTime = Duration(minutes: 2); // varsayılan
    }

    // İlk tur için 1 saat kuralı
    final bool isFirstTurn = data['player1Score'] == 0 && data['player2Score'] == 0;
    if (isFirstTurn) {
      totalTime = Duration(hours: 1);
    }

    final elapsed = DateTime.now().difference(started);
    final remaining = totalTime - elapsed;

    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool hasAtLeastOneAdjacentTile(Map<String, String> board, List<String> placedKeys) {
    final placedSet = placedKeys.toSet();

    for (final key in placedKeys) {
      final parts = key.split('_');
      final x = int.parse(parts[0]);
      final y = int.parse(parts[1]);

      // Altı yöne bak
      for (final offset in [
        {'dx': 0, 'dy': -1}, // yukarı
        {'dx': 0, 'dy': 1}, // aşağı
        {'dx': -1, 'dy': 0}, // sol
        {'dx': 1, 'dy': 0}, // sağ
        {'dx': -1, 'dy': -1}, // sol üst çapraz
        {'dx': 1, 'dy': 1}, // sağ alt çapraz
      ]) {
        final nx = x + offset['dx']!;
        final ny = y + offset['dy']!;
        final neighborKey = '${nx}_${ny}';

        // Komşu hücrede harf varsa ve bu yeni yerleştirilenlerden biri değilse
        if (board[neighborKey]?.isNotEmpty == true && !placedSet.contains(neighborKey)) {
          return true;
        }
      }
    }

    return false;
  }

  bool isValidFirstMove(List<String> placedKeys) {
    return placedKeys.contains('7_7') && placedKeys.length > 1;
  }

  void restorePlacedLetters() {
    for (final key in placedKeys) {
      final letter = board[key];
      if (letter != null && letter.isNotEmpty) {
        playerLetters.add(letter);
        board.remove(key);
      }
    }

    placedKeys.clear();
    selectedLetter = null;

    setState(() {});
  }

  bool isAlignedWithoutGaps(List<String> placedKeys, Map<String, String> board) {
    if (placedKeys.length < 2) return true;

    final coords = placedKeys.map((k) {
      final parts = k.split('_');
      return {'x': int.parse(parts[0]), 'y': int.parse(parts[1])};
    }).toList();

    final allX = coords.map((c) => c['x']!).toSet();
    final allY = coords.map((c) => c['y']!).toSet();

    // Aynı satır mı (yatay)?
    if (allY.length == 1) {
      final row = allY.first;
      final xs = allX.toList()..sort();
      for (int x = xs.first; x <= xs.last; x++) {
        final key = '${x}_$row';
        if (!board.containsKey(key) || board[key]!.isEmpty) return false;
      }
      return true;
    }

    // Aynı sütun mu (dikey)?
    if (allX.length == 1) {
      final col = allX.first;
      final ys = coords.map((c) => c['y']!).toList()..sort();
      for (int y = ys.first; y <= ys.last; y++) {
        final key = '${col}_$y';
        if (!board.containsKey(key) || board[key]!.isEmpty) return false;
      }
      return true;
    }

    // Sol üstten sağ alt çapraz mı?
    final sorted = coords..sort((a, b) {
      if (a['x'] == b['x']) {
        return a['y']!.compareTo(b['y']!);
      }
      return a['x']!.compareTo(b['x']!);
    });

    for (int i = 0; i < sorted.length - 1; i++) {
      final current = sorted[i];
      final next = sorted[i + 1];

      if (next['x'] != current['x']! + 1 || next['y'] != current['y']! + 1) {
        return false; // Bir sonraki harf tam çaprazında değilse invalid
      }
    }

    // Hepsi doğru çapraz bağlıysa ek olarak boşluk kontrolü yap
    final start = sorted.first;
    final end = sorted.last;

    int x = start['x']!;
    int y = start['y']!;

    try {
      while (x <= end['x']! && y <= end['y']!) {
        final key = '${x}_${y}';
        if (!board.containsKey(key) || board[key]!.isEmpty) return false;
        x++;
        y++;
      }
    } catch (e) {
      return false;
    }

    return true;
  }

  Future<void> passTurn() async {
    final docRef = firestore.collection('games').doc(widget.gameId);
    final snapshot = await docRef.get();
    final data = snapshot.data()!;
    final isPlayer1 = data['player1'] == myUid;
    final opponent = isPlayer1 ? data['player2'] : data['player1'];
    final currentPasses = data['consecutivePasses'] ?? 0;

    final newPasses = currentPasses + 1;

    if (newPasses >= 2) {
      final p1Score = data['player1Score'];
      final p2Score = data['player2Score'];

      String winner;
      if (p1Score > p2Score) {
        winner = data['player1'];
      } else if (p2Score > p1Score) {
        winner = data['player2'];
      } else {
        winner = 'draw';
      }

      await docRef.update({
        'status': 'finished',
        'winner': winner,
      });

      Get.off(() => GameResultPage(
        winner: winner,
        myUid: myUid,
        player1Score: p1Score,
        player2Score: p2Score,
        player1Id: data['player1'],
        player2Id: data['player2'],
      ));
    } else {
      final rewards = Map<String, dynamic>.from(gameData['rewards'] ?? {});
      String? rewardKey;
      final hasActiveDoubleTurn = rewards.entries.any((entry) {
        final r = entry.value;
        if (r['owner'] == myUid &&
            r['type'] == 'double_turn' &&
            r['activeEffect'] != null &&
            r['status'] == 'used') {
          rewardKey = entry.key;
          return true;
        }
        return false;
      });

      if (hasActiveDoubleTurn) {
        final docRef = firestore.collection('games').doc(widget.gameId);
        final rewardPath = 'rewards.$rewardKey';
        await docRef.update({
          '$rewardPath.activeEffect': FieldValue.delete()
        });
      }
      await clearUsedRewardEffects();
      await docRef.update({
        'turn': opponent,
        'turnStartedAt': FieldValue.serverTimestamp(),
        'consecutivePasses': newPasses,
      });
    }
  }

  String mapMineToTurkish(String type) {
    switch (type) {
      case 'score_split':
        return 'Puan Bölünmesi';
      case 'score_transfer':
        return 'Puan Transferi';
      case 'letter_reset':
        return 'Harf Kaybı';
      case 'disable_multiplier':
        return 'Ekstra Hamle Engeli';
      case 'cancel_word':
        return 'Kelime İptali';
      default:
        return 'Bilinmeyen Mayın';
    }
  }

  String mapRewardToTurkish(String type) {
    switch (type) {
      case 'zone_ban':
        return 'Bölge Yasağı';
      case 'letter_ban':
        return 'Harf Yasağı';
      case 'double_turn':
        return 'Ekstra Hamle Jokeri';
      default:
        return 'Bilinmeyen Ödül';
    }
  }

  Future<void> finishTurn() async {
    _isProcessing = true;
    final isFirstMove = board.values.where((v) => v.isNotEmpty).length == placedKeys.length;
    if (isFirstMove && !isValidFirstMove(placedKeys)) {
      restorePlacedLetters();
      Get.snackbar('Geçersiz Hamle', 'İlk kelime tahtanın ortasına temas etmelidir.');
      return;
    }

    if (!isAlignedWithoutGaps(placedKeys, board)) {
      restorePlacedLetters();
      Get.snackbar('Geçersiz Hamle', 'Yeni harfler boşluksuz ve yatay veya dikey yerleştirilmeli.');
      return;
    }

    if (!isFirstMove && !hasAtLeastOneAdjacentTile(board, placedKeys)) {
      restorePlacedLetters();
      Get.snackbar('Geçersiz Hamle', 'Yeni harfler mevcut taşlara temas etmeli.');
      return;
    }

    final docRef = firestore.collection('games').doc(widget.gameId);
    final isPlayer1 = gameData['player1'] == myUid;

    List<String> letterBag = List<String>.from(gameData['letterBag'] ?? []);

    final words = findAllNewWords(board, placedKeys); // yatay ve dikey
    if (words.isEmpty) {
      final diagonalWord = findSingleDiagonalWord(board, placedKeys);
      if (diagonalWord != null) {
        words.add(diagonalWord);
      }
    }

    var isValid = false;

    if (words.isNotEmpty) {
      final dictionary = await loadDictionary();
      isValid = words.every((wordInfo) {
        String rawWord = "";
        for (var key in wordInfo.keys) {
          rawWord += getLetterAt(board, key);
        }
        return dictionary.contains(rawWord);
      });
    }

    if (!isValid) {
      restorePlacedLetters();
      placedNewLetter = false;
      movedExistingLetter = false;
      Get.snackbar('Geçersiz kelime', 'Oluşan kelimeler sözlükte bulunamadı.');
      return;
    }

    List<String> triggeredMineTypes = [];

    bool triggeredLetterReset = false;

    for (final key in placedKeys) {
      // Ödül kontrolü
      if (gameData['rewards'] != null && gameData['rewards'][key] != null) {
        final reward = gameData['rewards'][key];
        if (reward['status'] == 'active') {
          await firestore.collection('games').doc(widget.gameId).update({
            'rewards.$key.owner': myUid,
          });

          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text('Ödül Kazandın!'),
                content: Text('${mapRewardToTurkish(reward['type'])} ödülünü kazandın!'),
                actions: [TextButton(onPressed: () => Get.back(), child: Text('Tamam'))],
              ),
            );
          });
        }
      }

      // Mayın kontrolü
      if (gameData['mines'] != null && gameData['mines'][key] != null) {
        final type = gameData['mines'][key];
          triggeredMineTypes.add(type);

          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text('Mayına Bastın!'),
                content: Text('${mapMineToTurkish(type)} mayınına bastın!'),
                actions: [TextButton(onPressed: () => Get.back(), child: Text('Tamam'))],
              ),
            );
          });

          if (type == 'letter_reset') {
            letterBag.addAll(playerLetters);
            playerLetters.clear();
            for (int i = 0; i < 7 && letterBag.isNotEmpty; i++) {
              playerLetters.add(letterBag.removeAt(0));
            }
            triggeredLetterReset = true;
          }
      }
    }

    if (!triggeredLetterReset) {
      int toDraw = 7 - playerLetters.length;
    for (int i = 0; i < toDraw && letterBag.isNotEmpty; i++) {
      playerLetters.add(letterBag.removeAt(0));
    }}

    String newTurn;

    // Eğer rewards içinde bana ait aktif bir double_turn varsa, sıra yine bende kalmalı
    final rewards = Map<String, dynamic>.from(gameData['rewards'] ?? {});
    String? rewardKey;
    final hasActiveDoubleTurn = rewards.entries.any((entry) {
      final r = entry.value;
      if (r['owner'] == myUid &&
          r['type'] == 'double_turn' &&
          r['activeEffect'] != null &&
          r['status'] == 'used') {
        rewardKey = entry.key;
        return true;
      }
      return false;
    });

    if (hasActiveDoubleTurn) {
      newTurn = myUid;
      final docRef = firestore.collection('games').doc(widget.gameId);
      final rewardPath = 'rewards.$rewardKey';
      await docRef.update({
        '$rewardPath.activeEffect': FieldValue.delete()
      });
    } else {
      newTurn = isPlayer1 ? gameData['player2'] : gameData['player1'];
    }

    // skor ekleme

    final wordScores = words.map((w) =>
        calculateWordScore(w, letterScores, placedKeys, disableMultiplier: triggeredMineTypes.contains('disable_multiplier'))
    );
    var totalScore = 0;
    for (int score in wordScores) {
      totalScore += score;
    }

    if (triggeredMineTypes.contains('score_split')) {
      totalScore = (totalScore * 0.3).round();
    }
    if (triggeredMineTypes.contains('cancel_word')) {
      totalScore = 0;
    }
    if (triggeredMineTypes.contains('score_transfer')) {
      final opponentScore = (isPlayer1 ? gameData['player2Score'] : gameData['player1Score']) ?? 0;
      await docRef.update({
        isPlayer1 ? 'player2Score' : 'player1Score': opponentScore + totalScore,
      });
      totalScore = 0;
    }

    final newScore = (isPlayer1 ? gameData['player1Score'] : gameData['player2Score']) ?? 0;
    final updatedScore = newScore + totalScore;

    // firebase güncelleme

    final updates = {
      isPlayer1 ? 'player1Letters' : 'player2Letters': playerLetters,
      isPlayer1 ? 'player1Score' : 'player2Score': updatedScore,
      'letterBag': letterBag,
      'turn': newTurn,
      'turnStartedAt': FieldValue.serverTimestamp(),
      'board': board,
      'jokerReplacements': jokerReplacements,
      'consecutivePasses': 0,
    };

    _isProcessing = false;
    await docRef.update(updates);

    placedNewLetter = false;
    movedExistingLetter = false;

    await clearUsedRewardEffects();

    setState(() {
      selectedLetter = null;
      placedKeys.clear();
    });

    // Oyun sonu kontrolü
    if (letterBag.isEmpty &&
        (playerLetters.isEmpty || (isPlayer1 ? gameData['player2Letters'] : gameData['player1Letters']).isEmpty)) {

      // Skorlar
      int p1Score;
      int p2Score;

      if (isPlayer1) {
        p1Score = updatedScore; // bizim lokal skorumuz
        p2Score = gameData['player2Score'] ?? 0; // karşı tarafın eski skoru
      } else {
        p1Score = gameData['player1Score'] ?? 0; // karşı tarafın eski skoru
        p2Score = updatedScore; // bizim lokal skorumuz
      }

      // Harf listeleri
      List<String> p1Letters;
      List<String> p2Letters;

      if (isPlayer1) {
        p1Letters = []; // bizim playerLetters zaten boş
        p2Letters = List<String>.from(gameData['player2Letters'] ?? []);
      } else {
        p2Letters = []; // bizim playerLetters zaten boş
        p1Letters = List<String>.from(gameData['player1Letters'] ?? []);
      }

      // Puan hesaplamak için harf puan tablosu
      final letterScores = {
        for (final l in letterPool) l.char: l.score,
      };

      int p1Penalty = p1Letters.map((c) => letterScores[c] ?? 0).fold(0, (a, b) => a + b);
      int p2Penalty = p2Letters.map((c) => letterScores[c] ?? 0).fold(0, (a, b) => a + b);

      if (p1Letters.isEmpty) {
        p1Score += p2Penalty;
        p2Score -= p2Penalty;
      } else if (p2Letters.isEmpty) {
        p2Score += p1Penalty;
        p1Score -= p1Penalty;
      }

      // Kazananı belirle
      String winner;
      if (p1Score > p2Score) {
        winner = gameData['player1'];
      } else if (p2Score > p1Score) {
        winner = gameData['player2'];
      } else {
        winner = 'draw';
      }

      await docRef.update({
        'status': 'finished',
        'winner': winner,
        'player1Score': p1Score,
        'player2Score': p2Score,
      });

      Get.off(() => GameResultPage(
        winner: winner,
        myUid: myUid,
        player1Score: p1Score,
        player2Score: p2Score,
        player1Id: gameData['player1'],
        player2Id: gameData['player2'],
      ));
    }
  }

  int calculateWordScore(
      WordInfo wordInfo,
      Map<String, int> letterScores,
      List<String> placedKeys,
      {bool disableMultiplier = false}
      ) {
    int total = 0;
    int wordMultiplier = 1;

    for (int i = 0; i < wordInfo.word.length; i++) {
      final letter = wordInfo.word[i];
      final key = wordInfo.keys[i];
      int score = letterScores[letter] ?? 0;

      final isNewLetter = placedKeys.contains(key);

      if (disableMultiplier) {
        total += score;
        continue;
      }

      if (isNewLetter) {
        // Yeni konulan harfe çarpan uygula
        if (doubleLetterTiles.contains(key)) {
          score *= 2;
        } else if (tripleLetterTiles.contains(key)) {
          score *= 3;
        }

        if (doubleWordTiles.contains(key)) {
          wordMultiplier *= 2;
        } else if (tripleWordTiles.contains(key)) {
          wordMultiplier *= 3;
        }
      }

      total += score;
    }

    return total * wordMultiplier;
  }

  Widget buildEndTurnButton() {
    return ElevatedButton(
      onPressed: isMyTurn && placedKeys.isNotEmpty ? finishTurn : null,
      child: Text('Hamleyi Bitir'),
    );
  }

  String getSpecialTileDisplay(String key) {
    if (gameData['mines'] != null && gameData['mines'][key] != null) {
      return '💣';
    }
    if (gameData['rewards'] != null && gameData['rewards'][key] != null) {
      return '🎁';
    }
    return getTileSymbol(key);
  }

  Widget buildBoard() {
    return Column(
      children: List.generate(15, (y) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(15, (x) {
            final key = '${x}_${y}';
            final letter = board[key] ?? '';
            final isSelected = selectedBoardTileKey == key;
            final isCommittedLetter = committedBoard.containsKey('$x\_$y') && committedBoard['$x\_$y']!.isNotEmpty;

            return GestureDetector(
              onTap: () => handleBoardTap(x, y),
              child: Container(
                width: 24,
                height: 24,
                margin: EdgeInsets.all(0.7),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.greenAccent : letter.isEmpty ? getTileColor(key) : Colors.grey[300],
                  border: Border.all(color: Colors.black26),
                ),
                alignment: Alignment.center,
                child: (letter.isEmpty && x == 7 && y == 7) ? Container(color: Colors.yellow, child: Icon(Icons.star, color: Colors.deepOrangeAccent,),) : Container(
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.grey[0] : isCommittedLetter ? Colors.yellow[300] : Colors.grey[0],
                    border: Border.all(
                      color: isCommittedLetter ? Colors.green : Colors.black,
                      width: isCommittedLetter ? 1.5 : 0.3,
                    ),
                    borderRadius: BorderRadius.circular(1),
                  ),
                  child: Stack(
                                children: [
                                Align(
                                alignment: Alignment.center,
                  child: Text(
                    letter.isEmpty
                        ? getSpecialTileDisplay(key)
                        : letter,
                    style: TextStyle(fontSize: 14),
                  ),
                                ),
                                Align(
                  alignment: Alignment.topRight,
                  child: Text(
                    letter.isEmpty
                        ? getTileCoefficient(key)
                        : (returnLetterObject(letter)?.score.toString() ?? ""),
                    style: TextStyle(fontSize: 10),
                  ),
                                ),
                                ],
                              ),
                ),

            ),
            );
          }),
        );
      }),
    );
  }

  Color getTileColor(String key) {
    Color tileColor;
    if (tripleLetterTiles.contains(key)) {
      tileColor = Colors.pink[200]!;
    } else if (doubleLetterTiles.contains(key)) {
      tileColor = Colors.blue[200]!;
    } else if (tripleWordTiles.contains(key)) {
      tileColor = Colors.brown[200]!;
    } else if (doubleWordTiles.contains(key)) {
      tileColor = Colors.green[200]!;
    } else {
      tileColor = Colors.grey[300]!;
    }
    return tileColor;
  }

  String getTileSymbol(String key) {
    if (tripleWordTiles.contains(key) || doubleWordTiles.contains(key)) return 'K';
    if (tripleLetterTiles.contains(key) || doubleLetterTiles.contains(key)) return 'H';
    return "";
  }

  String getTileCoefficient(String key) {
    if (tripleWordTiles.contains(key) || tripleLetterTiles.contains(key)) return "3";
    if (doubleWordTiles.contains(key) || doubleLetterTiles.contains(key)) return "2";
    return "";
  }

  Widget buildPlayerLetters() {
    final isDisabled = !isMyTurn;

    List<String> bannedLetters = [];
    final rewards = Map<String, dynamic>.from(gameData['rewards'] ?? {});

    rewards.forEach((key, value) {
      if (value['type'] == 'letter_ban' &&
          value['activeEffect'] != null &&
          value['activeEffect']['target'] == myUid) {
        bannedLetters = List<String>.from(value['activeEffect']['letters'] ?? []);
      }
    });

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: playerLetters.map((letter) {
        final isSelected = selectedLetter == letter;
        final isBanned = bannedLetters.contains(letter);

        final color = (isDisabled || isBanned)
            ? Colors.grey[400]
            : (isSelected ? Colors.blue : Colors.amber);

        final score = returnLetterObject(letter)?.score ?? 0;

        return GestureDetector(
          onTap: (isDisabled || isBanned)
              ? null
              : () {
            setState(() {
              selectedLetter = isSelected ? null : letter;
            });
          },
          child: Container(
            width: 40,
            height: 40,
            margin: EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: (isDisabled || isBanned) ? Colors.black54 : Colors.black,
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 4,
                  child: Text(
                    '$score',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.black54,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  String normalizeTurkishWord(String input) {
    return input
        .replaceAll('i', 'İ')
        .replaceAll('ı', 'I')
        .toUpperCase();
  }

  Future<Set<String>> loadDictionary() async {
    final content = await rootBundle.loadString('assets/turkce_kelime_listesi.txt');
    final words = content
        .split('\n')
        .map((w) => normalizeTurkishWord(w.trim()))
        .where((w) => w.length > 1)
        .toSet();
    return words;
  }

  bool areAllWordsValid(List<String> words, Set<String> dictionary) {
    if (words.isEmpty) return false;
    return words.every((word) {
      final upperWord = word.toUpperCase().replaceAll('i', 'İ').replaceAll('ı', 'I'); // workaround
      return dictionary.contains(upperWord);});
  }

  WordInfo _scanWord(Map<String, String> board, int x, int y, {required int dx, required int dy}) {
    // Geri git - kelimenin başına kadar
    while (_hasLetter(board, x - dx, y - dy)) {
      x -= dx;
      y -= dy;
    }

    final buffer = StringBuffer();
    final keys = <String>[];

    while (_hasLetter(board, x, y)) {
      buffer.write(board['${x}_$y']);
      keys.add('${x}_${y}');
      x += dx;
      y += dy;
    }

    return WordInfo(word: buffer.toString(), keys: keys);
  }

  bool _hasLetter(Map<String, String> board, int x, int y) {
    if (x < 0 || y < 0 || x >= 15 || y >= 15) return false;
    final letter = board['${x}_${y}'];
    return letter != null && letter.trim().isNotEmpty;
  }

  List<WordInfo> findAllNewWords(Map<String, String> board, List<String> placedKeys) {
    final Set<String> visited = {}; // zaten bulunan kelimeleri tekrar eklememek için
    final List<WordInfo> foundWords = [];

    for (final key in placedKeys) {
      final parts = key.split('_');
      final x = int.parse(parts[0]);
      final y = int.parse(parts[1]);

      final horizontalWordInfo = _scanWord(board, x, y, dx: 1, dy: 0);
      if (horizontalWordInfo.word.length > 1 && !visited.contains(horizontalWordInfo.word)) {
        visited.add(horizontalWordInfo.word);
        foundWords.add(horizontalWordInfo);
      }

      final verticalWordInfo = _scanWord(board, x, y, dx: 0, dy: 1);
      if (verticalWordInfo.word.length > 1 && !visited.contains(verticalWordInfo.word)) {
        visited.add(verticalWordInfo.word);
        foundWords.add(verticalWordInfo);
      }
    }

    return foundWords;
  }

  WordInfo? findSingleDiagonalWord(Map<String, String> board, List<String> placedKeys) {
  if (placedKeys.isEmpty) return null;

  final key = placedKeys.first;
  final parts = key.split('_');
  final x = int.parse(parts[0]);
  final y = int.parse(parts[1]);

  int startX = x;
  int startY = y;

  while (_hasLetter(board, startX - 1, startY - 1)) {
  startX--;
  startY--;
  }

  final buffer = StringBuffer();
  final usedKeys = <String>[];

  int currX = startX;
  int currY = startY;

  while (_hasLetter(board, currX, currY)) {
  buffer.write(board['${currX}_${currY}']);
  usedKeys.add('${currX}_${currY}');
  currX++;
  currY++;
  }

  final word = buffer.toString();
  if (word.length > 1) {
  return WordInfo(word: word, keys: usedKeys);
  }

  return null;
  }

  Widget buildInfoBar() {
    final isPlayer1 = gameData['player1'] == myUid;
    final myScore = isPlayer1 ? gameData['player1Score'] ?? 0 : gameData['player2Score'] ?? 0;
    final opponentScore = isPlayer1 ? gameData['player2Score'] ?? 0 : gameData['player1Score'] ?? 0;
    final remaining = (gameData['letterBag'] as List?)?.length ?? 0;

    final p1Uid = gameData['player1'];
    final p2Uid = gameData['player2'];

    final myUidToFetch = isPlayer1 ? p1Uid : p2Uid;
    final opponentUidToFetch = isPlayer1 ? p2Uid : p1Uid;

    final myUserFuture = FirebaseFirestore.instance.collection('users').doc(myUidToFetch).get();
    final opponentUserFuture = FirebaseFirestore.instance.collection('users').doc(opponentUidToFetch).get();

    return FutureBuilder<List<DocumentSnapshot>>(
      future: Future.wait([myUserFuture, opponentUserFuture]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }

        final myUsername = snapshot.data![0].data() != null ? snapshot.data![0].get('username') : 'Sen';
        final opponentUsername = snapshot.data![1].data() != null ? snapshot.data![1].get('username') : 'Rakip';

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Sol: Ben
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(myUsername, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Puan: $myScore'),
                ],
              ),
              // Orta: Kalan harf
              Row(
                children: [
                  Text('$remaining', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  SizedBox(width: 10,),
                  Text("|"),
                  SizedBox(width: 10,),
                  buildCountdownDisplay(),
                ],
              ),
              // Sağ: Rakip
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(opponentUsername, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Puan: $opponentScore'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void checkForTimeoutLoss() async {
    if (gameData['status'] == 'finished') return;

    final remaining = getRemainingTime(gameData);
    if (remaining > Duration.zero) return;

    final currentTurnPlayer = gameData['turn'];
    final winner = (currentTurnPlayer == gameData['player1'])
        ? gameData['player2']
        : gameData['player1'];

    await firestore.collection('games').doc(widget.gameId).update({
      'status': 'finished',
      'winner': winner,
    });

    if (myUid == winner || myUid == currentTurnPlayer) {
      Get.off(() => GameResultPage(
        winner: winner,
        myUid: myUid,
        player1Score: gameData['player1Score'],
        player2Score: gameData['player2Score'],
        player1Id: gameData['player1'],
        player2Id: gameData['player2'],
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Oyun')),
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: 10),
              buildBoard(),
              SizedBox(height: 20),
              buildInfoBar(),
              SizedBox(height: 20),
              buildPlayerLetters(),
              SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    buildEndTurnButton(),
                    buildRewardButton(),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'pass') {
                          isMyTurn ? passTurn() : null;
                        } else if (value == 'surrender') {
                          surrender();
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'pass',
                          child: Text('Pas Geç'),
                        ),
                        PopupMenuItem(
                          value: 'surrender',
                          child: Text('Teslim Ol'),
                        ),
                      ],
                      icon: Icon(Icons.more_vert),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildRewardButton() {
    return FutureBuilder<DocumentSnapshot>(
      future: firestore.collection('games').doc(widget.gameId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return SizedBox();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final rewards = Map<String, dynamic>.from(data['rewards'] ?? {});

        final myRewards = rewards.values.where((reward) {
          return reward['owner'] == myUid && reward['status'] == 'active';
        }).toList();

        return Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: ElevatedButton.icon(
            onPressed: () {
              if (data['turn'] == myUid) {
                showRewardDialog(rewards);
              }
            },
            icon: Icon(Icons.card_giftcard),
            label: Text('Ödüllerim (${myRewards.length})'),
            style: ElevatedButton.styleFrom(),
          ),
        );
      },
    );
  }

  void applyReward(String rewardKey, String rewardType) {
    if (rewardType == 'zone_ban') {
      applyZoneBanReward(rewardKey);
    } else if (rewardType == 'letter_ban') {
      applyLetterBanReward(rewardKey);
    } else if (rewardType == 'double_turn') {
      applyDoubleTurnReward(rewardKey);
    }
  }

  void showRewardDialog(Map<String, dynamic> rewards) {
    final myRewards = rewards.entries.where((entry) {
      final reward = entry.value;
      return reward['owner'] == myUid && reward['status'] == "active";
    }).toList();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Kazandığın Ödüller'),
        content: myRewards.isEmpty
            ? Text('Henüz ödülün yok.')
            : SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: myRewards.map((entry) {
              final rewardType = entry.value['type'];

              // Eğer status active ise, kullanılabilir
              final isActive = entry.value['status'] == 'active';

              if (isActive) {
                // Kullanılabilir ödüller için buton
                return ElevatedButton(
                  onPressed: () {
                    applyReward(entry.key, rewardType);
                  },
                  child: Text(mapRewardToTurkish(rewardType)),
                );
              } else {
                // Kullanılmış ödüller için sadece yazı
                return ListTile(
                  title: Text(
                    mapRewardToTurkish(rewardType),
                    style: TextStyle(color: Colors.grey),
                  ),
                  subtitle: Text('Kullanıldı'),
                );
              }
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('Kapat'),
          ),
        ],
      ),
    );
  }

}

const doubleLetterTiles = {
  '0_5', '0_9', '1_6', '1_8',
  '5_0', '5_5', '5_9', '5_14',
  '6_1', '6_6', '6_8', '6_13',
  '8_1', '8_6', '8_8', '8_13',
  '9_0', '9_5', '9_9', '9_14',
  '13_6', '13_8', '14_5', '14_9',
};

const doubleWordTiles = {
  '2_7', '3_3',
  '3_11', '7_2',
  '7_12', '11_3',
  '11_11', '12_7', '7_7'
};

const tripleLetterTiles = {'1_1', '1_13',
  '4_4', '4_10', '10_4', '10_10',
  '13_1', '13_13',
};

const tripleWordTiles = {'0_2', '2_0', '0_12',
  '2_14', '12_0',
  '14_2', '12_14', '14_12',
};

class WordInfo {
  final String word;
  final List<String> keys;

  WordInfo({required this.word, required this.keys});
}