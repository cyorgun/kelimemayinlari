import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../controllers/auth_service.dart';
import '../register/RegisterPage.dart';

class LoginPage extends StatelessWidget {
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  final authController = Get.find<AuthService>();

  LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Giriş Yap')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(controller: usernameController, decoration: InputDecoration(labelText: 'Kullanıcı Adı')),
            TextField(controller: passwordController, decoration: InputDecoration(labelText: 'Şifre'), obscureText: true),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                authController.loginWithUsername(
                  username: usernameController.text.trim(),
                  password: passwordController.text.trim(),
                );
              },
              child: Text('Giriş Yap'),
            ),
            TextButton(
              onPressed: () => Get.to(RegisterPage()),
              child: Text('Hesabın yok mu? Kayıt ol'),
            )
          ],
        ),
      ),
    );
  }
}
