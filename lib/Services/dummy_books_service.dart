import 'package:inlib_nav/Model/book.dart'; // Εισαγωγή του Book model

// --- Δεδομένα Ραφιών από φώτογραφίες---

final List<Map<String, dynamic>> _shelfRanges = [
  {'shelf': 1, 'from': 'b29.h5816.1993', 'to': 'Qa76.575.v3816.2008'},
  {'shelf': 2, 'from': 'Qa76.575.v44.2006', 'to': 'Qa76.73.j38.s43162.2005'},
  {'shelf': 3, 'from': 'Qa76.73.j38.s535.2005', 'to': 'Qa76.9.a43.b69.2005'},
  {'shelf': 4, 'from': 'Qa76.9.a43.b69.2005', 'to': 'Qa276.2.233.2002'},
  {'shelf': 5, 'from': 'qa303.m95.2010', 'to': 'Qc174.8.937.1995'},
  {'shelf': 6, 'from': 'Qc271.m344.1988', 'to': 'TA654.k36.1998'},
  {'shelf': 7, 'from': 'TA660.p55.w38.2000', 'to': 'TK2000.C4616.2020'},
  {'shelf': 8, 'from': 'TK2000.T73.1997', 'to': 'TK5105.888.K37.2014'},
  {'shelf': 9, 'from': 'TK5105.888.K44.2009', 'to': 'TS155.6.M65.2020'},
  {'shelf': 10, 'from': 'TS156.K587.2003', 'to': 'TS157.5.P377.2006'},
  //! Προσθέτω τα ράφια
];

// --- Συνάρτηση Υπολογισμού Ραφιού ---
int calculateShelfForLOC(String loc) {
  if (loc.isEmpty) return 20;

  final lowerCaseLoc = loc.toLowerCase();
  for (var range in _shelfRanges) {
    final lowerCaseFrom = (range['from'] as String?)?.toLowerCase() ?? '';
    final lowerCaseTo = (range['to'] as String?)?.toLowerCase() ?? '';

    if (lowerCaseFrom.isEmpty || lowerCaseTo.isEmpty) continue;

    // Απλή σύγκριση ως String
    if (lowerCaseLoc.compareTo(lowerCaseFrom) >= 0 &&
        lowerCaseLoc.compareTo(lowerCaseTo) <= 0) {
      return range['shelf'] as int;
    }
  }
  return 20; // Default shelf
}

// --- Συνάρτηση Υπολογισμού Διάδρομου ---
String calculateCorridor(int shelf) {
  String corridorBase = "ΔΙΑΔΡΟΜΟΣ";

  if (shelf < 1 || shelf > 10) {
    // Επιστροφή μιας προεπιλεγμένης τιμής ή χειρισμός σφάλματος
    // Είναι σημαντικό αυτή η τιμή να μην ταιριάζει με κάποιο πραγματικό label
    return 'ΑΓΝΩΣΤΟΣ ΔΙΑΔΡΟΜΟΣ';
  } else {
    // Απλή αντιστοίχιση 2 ραφιών ανά διάδρομο
    int corridorNumber =
        ((shelf - 1) ~/ 2) + 1; // (1,2->1), (3,4->2), (5,6->3), ...
    return '$corridorBase $corridorNumber'; // π.χ., "ΔΙΑΔΡΟΜΟΣ 1"
  }
}

// --- Αρχικά δεδομένα βιβλίων (raw data) ---

// !!! ΠΡΟΣΟΧΗ: ΑΝΤΙΚΑΤΑΣΤΗΣΕ ΤΟΥΣ LOC ΜΕ ΤΟΥΣ ΣΩΣΤΟΥΣ!!!
final List<Map<String, String>> _initialBookData = [
  // Λογοτεχνία (Χρειάζονται πραγματικοί LOC)
  {
    'title': 'The Lord of the Rings',
    'author': 'J.R.R. Tolkien',
    'isbn': '978-0547928227',
    'loc': 'PR6039.O32 L6 1994', // Πραγματικός LOC
  },
  {
    'title': 'Pride and Prejudice',
    'author': 'Jane Austen',
    'isbn': '978-0141439518',
    'loc': 'PR4034 .P7 2002', // Πραγματικός LOC
  },
  {
    'title': '1984',
    'author': 'George Orwell',
    'isbn': '978-0451524935',
    'loc': 'PR6029.R8 N49 1961a', // Πραγματικός LOC
  },
  // Πληροφορική
  {
    'title': 'Clean Code: A Handbook of Agile Software Craftsmanship',
    'author': 'Robert C. Martin',
    'isbn': '978-0132350881',
    'loc': 'QA76.76.C65 M37 2008', // Υποθετικός LOC
  },
  {
    'title': 'Introduction to Algorithms',
    'author': 'Thomas H. Cormen et al.',
    'isbn': '978-0262033848',
    'loc': 'QA76 .I585 2009', // Υποθετικός LOC
  },
  {
    'title': 'Effective Java',
    'author': 'Joshua Bloch',
    'isbn': '978-0134685991',
    'loc': 'QA76.73.J38 B56 2018', // Υποθετικός LOC
  },
  {
    'title': 'Cracking the Coding Interview',
    'author': 'Gayle Laakmann McDowell',
    'isbn': '978-0984782857',
    'loc': 'QA76.76.I58 M33 2015', // Υποθετικός LOC
  },
  {
    'title': 'The Pragmatic Programmer',
    'author': 'Andrew Hunt & David Thomas',
    'isbn': '978-0201633859',
    'loc': 'QA76.76.D47 H86 2019', // Υποθετικός LOC
  },
  {
    'title': 'Design Patterns: Elements of Reusable Object-Oriented Software',
    'author': 'Erich Gamma et al.',
    'isbn': '978-0201633613',
    'loc': 'QA76.64.D47 1995', // Υποθετικός LOC
  },
  {
    'title': 'Python Crash Course',
    'author': 'Eric Matthes',
    'isbn': '978-1593276034',
    'loc': 'QA76.73.P98 M38 2019', // Υποθετικός LOC
  },
  {
    'title': 'Automate the Boring Stuff with Python',
    'author': 'Al Sweigart',
    'isbn': '978-1593279929',
    'loc': 'QA76.73.P98 S94 2019', // Υποθετικός LOC
  },
  {
    'title': 'Fluent Python',
    'author': 'Luciano Ramalho',
    'isbn': '978-1491952689',
    'loc': 'QA76.73.P98 R36 2015', // Υποθετικός LOC
  },
  // Μαθηματικά (Βάλε LOC στα αντίστοιχα QA)
  {
    'title': 'Calculus',
    'author': 'James Stewart',
    'isbn': '978-1285740621',
    'loc': 'QA303.2 .S74 2016', // Πραγματικός LOC
  },
  {
    'title': 'Linear Algebra and Its Applications',
    'author': 'David C. Lay',
    'isbn': '978-0321982384',
    'loc': 'QA184.2 .L39 2016', // Πραγματικός LOC
  },
  {
    'title': 'Probability and Statistics for Engineers and Scientists',
    'author': 'Sheldon M. Ross',
    'isbn': '978-0123861591',
    'loc': 'TA340 .R67 2014', // Υποθετικός LOC
  },
  // Φυσική (Βάλε LOC στα αντίστοιχα QC)
  {
    'title': 'Physics for Scientists and Engineers',
    'author': 'Paul A. Tipler & Gene P. Mosca',
    'isbn': '978-1429201247',
    'loc': 'QC21.3 .T56 2008', // Πραγματικός LOC
  },
  {
    'title': 'Modern Physics',
    'author': 'Kenneth S. Krane',
    'isbn': '978-0471859177',
    'loc': 'QC173 .K73 2012', // Πραγματικός LOC
  },
  // Χημεία (Βάλε LOC στα αντίστοιχα QD)
  {
    'title': 'Chemistry: The Central Science',
    'author': 'Theodore L. Brown et al.',
    'isbn': '978-0321910424',
    'loc': 'QD31.3 .B76 2018', // Πραγματικός LOC
  },
  {
    'title': 'Organic Chemistry',
    'author': 'Paula Yurkanis Bruice',
    'isbn': '978-0321809087',
    'loc': 'QD251.3 .B78 2017', // Πραγματικός LOC
  },
  // Ιστορία (Χρειάζονται πραγματικοί LOC)
  {
    'title': 'Sapiens: A Brief History of Humankind',
    'author': 'Yuval Noah Harari',
    'isbn': '978-0062464165',
    'loc': 'CB113.H4 H37 2015', // Πραγματικός LOC
  },
  {
    'title': 'The History of the Peloponnesian War',
    'author': 'Thucydides',
    'isbn': '978-0140440391',
    'loc': 'DF229.T5 L38 1998', // Πραγματικός LOC
  },
];

// --- Συνάρτηση που επιστρέφει την επεξεργασμένη λίστα βιβλίων ---
List<Book> getDummyBooks() {
  return _initialBookData.map((bookData) {
    final title = bookData['title'] ?? 'Άγνωστος Τίτλος';
    final author = bookData['author'] ?? 'Άγνωστος Συγγραφέας';
    final isbn = bookData['isbn'] ?? 'Άγνωστο ISBN';

    final loc = bookData['loc'] ?? '';

    // Υπολόγισε το ράφι καλώντας τη συνάρτηση που είναι τώρα σε αυτό το αρχείο
    final shelf = calculateShelfForLOC(loc);

    final corridor = calculateCorridor(shelf);

    return Book(
      title: title,
      author: author,
      isbn: isbn,
      loc: loc,
      corridor: corridor,
      shelf: shelf,
    );
  }).toList();
}
