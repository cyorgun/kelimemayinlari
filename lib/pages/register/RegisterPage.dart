import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_service.dart';
import '../login/LoginPage.dart';

class RegisterPage extends StatelessWidget {
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final authController = Get.find<AuthService>();

  RegisterPage({super.key});

  bool isPasswordValid(String password) {
    final hasMinLength = password.length >= 8;
    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasLowercase = password.contains(RegExp(r'[a-z]'));
    final hasDigit = password.contains(RegExp(r'\d'));

    return hasMinLength && hasUppercase && hasLowercase && hasDigit;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Kayıt Ol')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: usernameController, decoration: InputDecoration(labelText: 'Kullanıcı Adı')),
            TextField(controller: emailController, decoration: InputDecoration(labelText: 'Email')),
            TextField(controller: passwordController, decoration: InputDecoration(labelText: 'Şifre'), obscureText: true),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final username = usernameController.text.trim();
                final email = emailController.text.trim();
                final password = passwordController.text.trim();

                if (!isPasswordValid(password)) {
                  Get.snackbar(
                    'Geçersiz Şifre',
                    'Şifre en az 8 karakter olmalı, büyük/küçük harf ve rakam içermelidir.',
                    snackPosition: SnackPosition.BOTTOM,
                  );
                  return;
                }

                final exists = await authController.isUsernameTaken(username);
                if (exists) {
                  Get.snackbar(
                    'Kullanıcı Adı Kullanılıyor',
                    'Lütfen başka bir kullanıcı adı seçin.',
                    snackPosition: SnackPosition.BOTTOM,
                  );
                  return;
                }

                authController.registerWithEmailAndPassword(
                  username: username,
                  email: email,
                  password: password,
                );
              },
              child: Text('Kayıt Ol'),
            ),
            TextButton(
              onPressed: () => Get.to(LoginPage()),
              child: Text('Zaten hesabın var mı? Giriş yap'),
            )
          ],
        ),
      ),
    );
  }
}
