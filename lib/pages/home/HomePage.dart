import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

import '../../controllers/auth_service.dart';
import '../active_games_page/ActiveGamesPage.dart';
import '../finished_games_page/FinishedGamesPage.dart';
import '../game_selection_page/GameSelectionPage.dart';

class HomePage extends StatelessWidget {
  final auth = FirebaseAuth.instance;
  final firestore = FirebaseFirestore.instance;
  final authController = Get.find<AuthService>();

  HomePage({super.key});

  void signOut() async{
    await authController.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: firestore
          .collection('games')
          .where('status', isEqualTo: 'finished')
          .where(Filter.or(
        Filter('player1', isEqualTo: auth.currentUser!.uid),
        Filter('player2', isEqualTo: auth.currentUser!.uid),
      ))
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final games = snapshot.data!.docs;
        final total = games.length;
        final wins = games.where((doc) => doc['winner'] == auth.currentUser!.uid).length;
        final successRate = total == 0 ? '0' : (wins / total * 100).toStringAsFixed(1);

        return Scaffold(
          appBar: AppBar(title: Text('Kelime Mayınları')),
          floatingActionButton: FloatingActionButton.small(
            onPressed: signOut,
          child: Text("X"),),
          body: Container(
            alignment: Alignment.center,
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Hoş geldin, ${auth.currentUser!.email}'),
                SizedBox(height: 8),
                Text('Başarı Yüzdesi: %$successRate'),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          Get.to(() => GameSelectionPage());
                        },
                        child: Text('Yeni Oyun'),
                      ),
                      SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Get.to(() => ActiveGamesPage()),
                        child: Text('Aktif Oyunlar'),
                      ),
                      SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () => Get.to(() => FinishedGamesPage()),
                        child: Text('Biten Oyunlar'),
                      ),
                      SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
