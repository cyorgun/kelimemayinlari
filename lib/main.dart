import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:kelimemayinlari/pages/login/LoginPage.dart';

import 'controllers/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  Get.put(AuthService());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(builder: (theme, darkTheme) {
      return GetMaterialApp(
        debugShowCheckedModeBanner: false,
        key: const Key('GetMaterialApp'),
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
          useMaterial3: true,
        ),
        title: 'kelimemayinlari',
        enableLog: true,
        home: LoginPage(),
      );
    });
  }
}
