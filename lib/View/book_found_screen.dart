import 'package:flutter/material.dart';
import 'package:inlib_nav/View/home_view.dart'; // Για επιστροφή στην αρχική
import 'package:inlib_nav/constants.dart'; // Για το myAppBar και χρώματα

class BookFoundScreen extends StatelessWidget {
  final String bookTitle;
  final String bookAuthor;
  final String bookIsbn;
  final String bookLoc;
  final int shelfNumber;
  final String corridorLabel;
  final Duration? timeTaken;

  const BookFoundScreen({
    super.key,
    required this.bookTitle,
    required this.bookAuthor,
    required this.bookIsbn,
    required this.bookLoc,
    required this.shelfNumber,
    required this.corridorLabel,
    this.timeTaken,
  });

  String _formatDuration(Duration? duration) {
    if (duration == null) return 'N/A';
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    } else if (duration.inMinutes > 0) {
      return "$twoDigitMinutes λεπτά και $twoDigitSeconds δευτερόλεπτα";
    } else {
      return "$twoDigitSeconds δευτερόλεπτα";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: scaffoldBackroundColor,
      appBar: myAppBar,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.green[700],
                size: 80,
              ),
              const SizedBox(height: 20),
              const Text(
                'Το Βιβλίο Βρέθηκε Επιτυχώς!',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: mainColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              Text('Τίτλος: $bookTitle', style: const TextStyle(fontSize: 18)),
              Text(
                'Συγγραφέας: $bookAuthor',
                style: const TextStyle(fontSize: 18),
              ),
              Text('ISBN: $bookIsbn', style: const TextStyle(fontSize: 18)),
              Text('LOC: $bookLoc', style: const TextStyle(fontSize: 18)),
              Text(
                'Διάδρομος: $corridorLabel',
                style: const TextStyle(fontSize: 18),
              ),
              Text('Ράφι: $shelfNumber', style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              if (timeTaken != null)
                Text(
                  'Χρόνος Εύρεσης: ${_formatDuration(timeTaken)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[700],
                  ),
                ),
              const SizedBox(height: 40),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const HomeView()),
                    (Route<dynamic> route) => false,
                  );
                },
                child: const Text('Νέα Αναζήτηση'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
