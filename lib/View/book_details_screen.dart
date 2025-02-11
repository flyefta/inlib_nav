import 'package:flutter/material.dart';
import 'package:in_lib_nav/Model/book.dart';
import 'package:in_lib_nav/View/text_detector_view.dart';

class BookDetailsScreen extends StatelessWidget {
  final Book book;

  const BookDetailsScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Συγγραφέας: ${book.author}',
                style: const TextStyle(fontSize: 18)),
            Text('ISBN: ${book.isbn}', style: const TextStyle(fontSize: 18)),
            Text('DDC: ${book.ddc}', style: const TextStyle(fontSize: 18)),

            // TODO!: ΑΛΛΕΣ ΛΕΠΤΟΜΕΡΕΙΕΣ ΠΟΥ ΜΠΟΡΕΙ ΝΑ ΧΡΕΙΑΣΤΟΥΝ;

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => TextRecognizerView()));
              },
              child: const Text('Πλοήγηση προς το ράφι'),
            ),
          ],
        ),
      ),
    );
  }
}
