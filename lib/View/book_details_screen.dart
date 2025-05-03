import 'package:flutter/material.dart';
import 'package:inlib_nav/Model/book.dart';
// Εισάγουμε τη μετονομασμένη οθόνη σάρωσης
import 'package:inlib_nav/View/item_scanning_screen.dart';
import 'package:inlib_nav/constants.dart'; // Για τα χρώματα και το AppBar (αν χρησιμοποιούνται)

/// Οθόνη που εμφανίζει τις λεπτομέρειες ενός βιβλίου
/// και παρέχει το κουμπί για έναρξη πλοήγησης/σάρωσης.
class BookDetailsScreen extends StatelessWidget {
  // Το αντικείμενο Book που θα εμφανιστεί
  final Book book;

  const BookDetailsScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Χρησιμοποιούμε τα χρώματα και το AppBar από τα constants
      backgroundColor: scaffoldBackroundColor,
      appBar: myAppBar,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          // Στοίχιση των στοιχείων στην αρχή (αριστερά)
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Εμφάνιση λεπτομερειών του βιβλίου
            Text(
              'Συγγραφέας: ${book.author}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8), // Μικρό κενό
            Text('ISBN: ${book.isbn}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            // Εμφάνιση του κωδικού LOC
            Text(
              'Ταξινόμηση (LOC): ${book.loc}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            // Εμφάνιση του αριθμού ραφιού
            Text('Ράφι: ${book.shelf}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            // Εμφάνιση του διαδρόμου (με τη νέα μορφή "ΔΙΑΔΡΟΜΟΣ Χ")
            Text(
              'Διάδρομος: ${book.corridor}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold, // Έντονα γράμματα για έμφαση
              ),
            ),
            const SizedBox(height: 20), // Μεγαλύτερο κενό πριν το κουμπί
            // Κουμπί για έναρξη σάρωσης/πλοήγησης
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                // Χρώματα και padding από τα constants
                foregroundColor: Colors.white, // Χρώμα κειμένου κουμπιού
                backgroundColor: buttonColor,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
              ),
              onPressed: () {
                // Όταν πατηθεί το κουμπί:
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    // Δημιουργία και πλοήγηση στην ItemScanningScreen
                    builder:
                        (context) => ItemScanningScreen(
                          // Πέρασμα των απαραίτητων παραμέτρων:
                          targetCorridorLabel:
                              book.corridor, // Η ετικέτα διαδρόμου (π.χ., "ΔΙΑΔΡΟΜΟΣ 1")
                          targetBookLoc: book.loc, // Ο κωδικός LOC
                          targetShelf: book.shelf, // Ο αριθμός ραφιού (int)
                        ),
                  ),
                );
              },
              child: const Text(
                'Έναρξη Σάρωσης για Διάδρομο',
              ), // Ενημερωμένο κείμενο κουμπιού
            ),
          ],
        ),
      ),
    );
  }
}
