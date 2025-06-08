import 'package:flutter/material.dart';
import 'package:inlib_nav/Model/book.dart';
import 'package:inlib_nav/View/qr_scanning_screen.dart';
import 'package:inlib_nav/constants.dart';

/// Οθόνη που εμφανίζει τις λεπτομέρειες ενός βιβλίου
/// και παρέχει το κουμπί για έναρξη πλοήγησης/σάρωσης.
class BookDetailsScreen extends StatelessWidget {
  final Book book;

  const BookDetailsScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: scaffoldBackroundColor,
      appBar: myAppBar,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Συγγραφέας: ${book.author}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text('ISBN: ${book.isbn}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),

            Text(
              'Ταξινόμηση (LOC): ${book.loc}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),

            Text('Ράφι: ${book.shelf}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),

            Text(
              'Διάδρομος: ${book.corridor}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: buttonColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (context) => QrScanningScreen(
                          targetCorridorLabel: book.corridor,
                          targetBookLoc: book.loc,
                          targetShelf: book.shelf,

                          bookTitle: book.title,
                          bookAuthor: book.author,
                          bookIsbn: book.isbn,
                        ),
                  ),
                );
              },
              child: const Text('Έναρξη Σάρωσης για Διάδρομο'),
            ),
          ],
        ),
      ),
    );
  }
}
