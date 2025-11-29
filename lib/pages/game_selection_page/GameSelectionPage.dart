import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/Letter.dart';
import '../game_page/GamePage.dart';

class GameSelectionPage extends StatefulWidget {

  const GameSelectionPage({super.key});

  @override
  State<GameSelectionPage> createState() => _GameSelectionPageState();
}

class _GameSelectionPageState extends State<GameSelectionPage> {
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot>? waitingGameListener;

  void createOrJoinGame(String selectedTime) async {
    final uid = auth.currentUser!.uid;

    // Önce aktif bir oyunumuz var mı kontrol et
    final activeGameCheck = await firestore
        .collection('games')
        .where('status', isEqualTo: 'active')
        .where('duration', isEqualTo: selectedTime)
        .where(Filter.or(
      Filter('player1', isEqualTo: uid),
      Filter('player2', isEqualTo: uid),
    ))
        .limit(1)
        .get();

    if (activeGameCheck.docs.isNotEmpty) {
      // Aktif oyun varsa hiçbir şey yapma
      Get.snackbar('Hata', 'Zaten aktif bir oyunun var.');
      return;
    }

    final waiting = await firestore
        .collection('waitingGames')
        .where('duration', isEqualTo: selectedTime)
        .where('createdAt', isGreaterThan: Timestamp.fromDate(DateTime.now().subtract(Duration(minutes: 1))))
        .get();

    if (waiting.docs.isEmpty) { // oyun aratan başkası yoksa oyun arat
      await firestore.collection('waitingGames').add({
        'creatorId': uid,
        'duration': selectedTime,
        'createdAt': FieldValue.serverTimestamp(),
      });
      Get.snackbar('Yükleniyor', 'Rakip aranıyor...');

      // rakip bulunacak mı diye dinliyoruz ve bulunduğunda oyun sayfasına yönlendiriyoruz
      waitingGameListener = firestore.collection('games')
          .where('player1', isEqualTo: uid)
          .where('duration', isEqualTo: selectedTime)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          final gameId = snapshot.docs.first.id;
          waitingGameListener?.cancel();
          Get.off(() => GamePage(gameId: gameId));
        }
      });
    } else { // oyun aratan başkası varsa onunla eşleş ve oyun kur
      final doc = waiting.docs.first;
      final creatorId = doc['creatorId'];

      if (creatorId == uid) {
        Get.snackbar('Eşleşme Başarısız', 'Kendinle eşleşemezsin.');
        return;
      }

      // harf torbası
      List<String> bag = buildLetterBag();
      List<String> player1Letters = drawLetters(bag, 7);
      List<String> player2Letters = drawLetters(bag, 7);

      final player1 = creatorId;
      final player2 = uid;

      final random = Random();
      final turn = random.nextBool() ? player1 : player2;

      final mineRewardData = await generateMinesAndRewards();

      final newGame = await firestore.collection('games').add({
        'player1': player1,
        'player2': player2,
        'duration': selectedTime,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
        'board': generateEmptyBoardMap(),
        'turn': turn,
        'turnStartedAt': FieldValue.serverTimestamp(),
        'player1Score': 0,
        'player2Score': 0,
        'letterBag': bag,
        'player1Letters': player1Letters,
        'player2Letters': player2Letters,
        'mines': mineRewardData['mines'],
        'rewards': mineRewardData['rewards'],
      });

      await firestore.collection('waitingGames').doc(doc.id).delete();

      Get.to(() => GamePage(gameId: newGame.id));
    }
  }

  @override
  void dispose() {
    waitingGameListener?.cancel();
    super.dispose();
  }

  Map<String, String> generateEmptyBoardMap() {
    Map<String, String> board = {};
    for (int y = 0; y < 15; y++) {
      for (int x = 0; x < 15; x++) {
        board['${x}_${y}'] = '';
      }
    }
    return board;
  }

  Future<Map<String, dynamic>> generateMinesAndRewards() async {
    final allKeys = <String>[];

    for (int y = 0; y < 15; y++) {
      for (int x = 0; x < 15; x++) {
        allKeys.add('$x\_$y');
      }
    }

    allKeys.shuffle();

    // Mayın türleri ve adetleri
    final mineTypes = {
      'score_split': 5,
      'score_transfer': 4,
      'letter_reset': 3,
      'disable_multiplier': 2,
      'cancel_word': 2,
    };

    // Ödül türleri ve adetleri
    final rewardTypes = {
      'zone_ban': 2,
      'letter_ban': 3,
      'double_turn': 2,
    };

    final mines = <String, String>{};
    final rewards = <String, dynamic>{};
    int keyIndex = 0;

    // Mayınları yerleştiriyoruz
    for (final entry in mineTypes.entries) {
      for (int i = 0; i < entry.value; i++) {
        final key = allKeys[keyIndex++];
        mines[key] = entry.key;
      }
    }

    // Ödülleri yerleştiriyoruz
    for (final entry in rewardTypes.entries) {
      for (int i = 0; i < entry.value; i++) {
        final key = allKeys[keyIndex++];
        rewards[key] = {
          'type': entry.key,
          'status': 'active',
          'owner': null,
          'activeEffect': null,
        };
      }
    }

    return {
      'mines': mines,
      'rewards': rewards,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Yeni Oyun')),
      body: Container(
        alignment: Alignment.center,
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Süre Seçimi'),
            Expanded(
                child: Column(
                  spacing: 18,
                  mainAxisAlignment: MainAxisAlignment.center,
              children: [
              ElevatedButton(onPressed: () => createOrJoinGame('2dk'), child: Text('2 Dakika')),
              ElevatedButton(onPressed: () => createOrJoinGame('5dk'), child: Text('5 Dakika')),
              ElevatedButton(onPressed: () => createOrJoinGame('12s'), child: Text('12 Saat')),
              ElevatedButton(onPressed: () => createOrJoinGame('24s'), child: Text('24 Saat')),
                SizedBox(height: 18),
              ],)),
          ],
        ),
      ),
    );
  }
}
