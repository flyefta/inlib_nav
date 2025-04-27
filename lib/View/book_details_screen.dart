import 'package:flutter/material.dart';
import 'package:inlib_nav/Model/book.dart';
import 'package:inlib_nav/View/nav_screen.dart';
import 'package:inlib_nav/constants.dart';

class BookDetailsScreen extends StatelessWidget {
  final Book book;

  const BookDetailsScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: scaffoldBackroundColor,
      appBar: myAppBar,
      //appBar: AppBar(title: Text(book.title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Συγγραφέας: ${book.author}',
              style: const TextStyle(fontSize: 18),
            ),
            Text('ISBN: ${book.isbn}', style: const TextStyle(fontSize: 18)),
            Text('Loc: ${book.loc}', style: const TextStyle(fontSize: 18)),
            Text('Ράφι: ${book.shelf}', style: const TextStyle(fontSize: 18)),
            Text(
              'Διάδρομος: ${book.corridor}',
              style: const TextStyle(
                fontSize: 18,
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            // TODO!: ΑΛΛΕΣ ΛΕΠΤΟΜΕΡΕΙΕΣ ΠΟΥ ΜΠΟΡΕΙ ΝΑ ΧΡΕΙΑΣΤΟΥΝ;
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: buttonColor,
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
                        (context) => CorridorScanningScreen(
                          targetCorridor: book.corridor,
                          targetShelf: book.shelf,
                        ),
                  ),
                );
              },
              child: const Text('Πλοήγηση προς το ράφι'),
            ),
          ],
        ),
      ),
    );
  }
}
