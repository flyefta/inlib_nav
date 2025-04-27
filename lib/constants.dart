import 'package:flutter/material.dart';

const mainColor = Color(0xFF1f8fce);
const buttonColor = Color(0xFF63a44a);
const scaffoldBackroundColor = Color(0xFFE0F7FA);

AppBar myAppBar = AppBar(
  backgroundColor: mainColor,
  title: Row(
    children: [
      Image.asset('assets/images/inlib_logo2_trsp.png', height: 50.0),
      const SizedBox(width: 15.0),
      const Text(
        'InLib Navigation',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
    ],
  ),
);
