import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:kelimemayinlari/pages/login/LoginPage.dart';

import '../pages/home/HomePage.dart';

class AuthService extends GetxController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Kullanıcı kaydı
  Future<void> registerWithEmailAndPassword({
    required String email,
    required String username,
    required String password,
  }) async {
    try {
      UserCredential result =
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      if (result.user != null) {
        // Kullanıcı Firestore'a eklenecek
        await _firestore.collection('users').doc(result.user?.uid).set({
          'email': email,
          'username': username,
          'uid': result.user?.uid,
        },);
      }
      Get.offAll(() => HomePage());
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        Get.snackbar('Hata', 'Bu email zaten kullanımda.', snackPosition: SnackPosition.BOTTOM);
      } else if (e.code == 'invalid-email') {
        Get.snackbar('Hata', 'Email formatı geçersiz.', snackPosition: SnackPosition.BOTTOM);
      } else if (e.code == 'weak-password') {
        Get.snackbar('Hata', 'Şifre çok zayıf. Lütfen daha güçlü bir şifre girin.', snackPosition: SnackPosition.BOTTOM);
      } else {
        Get.snackbar('Hata', 'Kayıt olurken bir hata oluştu: ${e.message}', snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      Get.snackbar('Hata', 'Beklenmedik bir hata oluştu.', snackPosition: SnackPosition.BOTTOM);
    }
  }

  // Kullanıcı girişi
  Future<void> loginWithUsername({required String username, required String password}) async {
    final result = await _firestore
        .collection('users')
        .where('username', isEqualTo: username)
        .get();

    if (result.docs.isEmpty) {
      Get.snackbar('Hata', 'Kullanıcı bulunamadı');
      return;
    }

    final email = result.docs.first['email'];
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    Get.offAll(() => HomePage());
  }

  Future<bool> isUsernameTaken(String username) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    Get.offAll(() => LoginPage());
  }
}
