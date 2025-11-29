import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../game_page/GamePage.dart';

class ActiveGamesPage extends StatelessWidget {
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;

  ActiveGamesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final myUid = auth.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: Text('Aktif Oyunlar')),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore
            .collection('games')
            .where('status', isEqualTo: 'active')
            .where(Filter.or(
          Filter('player1', isEqualTo: myUid),
          Filter('player2', isEqualTo: myUid),
        ))
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

          final games = snapshot.data!.docs;

          if (games.isEmpty) {
            return Center(child: Text('Aktif oyun yok'));
          }

          return ListView.builder(
            itemCount: games.length,
            itemBuilder: (context, index) {
              final data = games[index].data() as Map<String, dynamic>;
              final gameId = games[index].id;
              final isPlayer1 = data['player1'] == myUid;
              final opponentId = isPlayer1 ? data['player2'] : data['player1'];
              final myScore = isPlayer1 ? data['player1Score'] ?? 0 : data['player2Score'] ?? 0;
              final oppScore = isPlayer1 ? data['player2Score'] ?? 0 : data['player1Score'] ?? 0;
              final isMyTurn = data['turn'] == myUid;

              return FutureBuilder<DocumentSnapshot>(
                future: firestore.collection('users').doc(opponentId).get(),
                builder: (context, userSnap) {
                  final opponentName = userSnap.data?.get('username') ?? '...';

                  return ListTile(
                    title: Text('Rakip: $opponentName'),
                    subtitle: Text('Sen: $myScore - Rakip: $oppScore'),
                    trailing: Text(isMyTurn ? 'Sıra sende' : 'Rakipte'),
                    onTap: () => Get.to(() => GamePage(gameId: gameId)),
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
