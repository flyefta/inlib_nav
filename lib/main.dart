import 'package:flutter/material.dart';
import 'package:in_lib_nav/View/home_view.dart';
import 'package:in_lib_nav/constants.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'InLib Navigation',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: mainColor),
          useMaterial3: true,
        ),
        home: const HomeView());
  }
}
