import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../game_result_page/GameResultPage.dart';

class FinishedGamesPage extends StatelessWidget {
  final uid = FirebaseAuth.instance.currentUser!.uid;

  Future<String> getOpponentUsername(String myUid, Map<String, dynamic> data) async {
    final opponentUid = data['player1'] == myUid ? data['player2'] : data['player1'];
    final doc = await FirebaseFirestore.instance.collection('users').doc(opponentUid).get();
    return doc.data()?['username'] ?? 'Bilinmeyen';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Biten Oyunlar')),
      body: FutureBuilder<QuerySnapshot>(
        future: FirebaseFirestore.instance
            .collection('games')
            .where('status', isEqualTo: 'finished')
            .where(Filter.or(
          Filter('player1', isEqualTo: uid),
          Filter('player2', isEqualTo: uid),
        ))
            .get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) return Center(child: Text('Henüz biten oyunun yok.'));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final yourScore = data['player1'] == uid ? data['player1Score'] : data['player2Score'];
              final opponentScore = data['player1'] == uid ? data['player2Score'] : data['player1Score'];
              final isDraw = data['winner'] == 'draw';
              final youWon = data['winner'] == uid;

              return FutureBuilder<String>(
                future: getOpponentUsername(uid, data),
                builder: (context, usernameSnapshot) {
                  final opponentName = usernameSnapshot.data ?? 'Rakip';

                  return ListTile(
                    title: Text(
                      isDraw
                          ? 'Berabere 🤝'
                          : youWon
                          ? 'Kazandın 🎉'
                          : 'Kaybettin 😢',
                    ),
                    subtitle: Text('$opponentName - Sen: $yourScore | Rakip: $opponentScore'),
                    onTap: () {
                      Get.to(() => GameResultPage(
                        winner: data['winner'],
                        myUid: uid,
                        player1Score: data['player1Score'],
                        player2Score: data['player2Score'],
                        player1Id: data['player1'],
                        player2Id: data['player2'],
                      ));
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
