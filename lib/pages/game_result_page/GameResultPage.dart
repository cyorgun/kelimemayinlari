import 'package:flutter/material.dart';

class GameResultPage extends StatelessWidget {
  final String winner;
  final String myUid;
  final int player1Score;
  final int player2Score;
  final String player1Id;
  final String player2Id;

  const GameResultPage({
    required this.winner,
    required this.myUid,
    required this.player1Score,
    required this.player2Score,
    required this.player1Id,
    required this.player2Id,
  });

  @override
  Widget build(BuildContext context) {
    final isDraw = winner == 'draw';
    final isWinner = winner == myUid;

    return Scaffold(
      appBar: AppBar(title: Text('Oyun Bitti')),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isDraw
                  ? 'Berabere 🤝'
                  : isWinner
                  ? 'Kazandın 🎉'
                  : 'Kaybettin 😢',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            Text(
              'Skorlar',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              '${player1Id == myUid ? "Sen" : "Rakip"}: $player1Score',
              style: TextStyle(fontSize: 20),
            ),
            Text(
              '${player2Id == myUid ? "Sen" : "Rakip"}: $player2Score',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Anasayfaya Dön'),
            ),
          ],
        ),
      ),
    );
  }
}
