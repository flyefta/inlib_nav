import 'package:flutter/material.dart';
import 'package:inlib_nav/Services/camera_service.dart';
import 'package:inlib_nav/View/home_view.dart';
import 'package:inlib_nav/constants.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      // Χρήσιμο αν έχεις πολλούς providers
      providers: [
        ChangeNotifierProvider(create: (_) => CameraService()),
        // ChangeNotifierProvider(create: (_) => OcrService()), // Αν φτιάξω κι άλλους providers
        // ChangeNotifierProvider(create: (_) => AudioService()),
      ],
      child: const MainApp(),
    ),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InLib Navigation',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSwatch().copyWith(primary: mainColor),
      ),
      home: const HomeView(),
    );
  }
}
