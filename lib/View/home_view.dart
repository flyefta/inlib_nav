import 'package:flutter/material.dart';
import 'package:in_lib_nav/Model/book.dart';
import 'package:in_lib_nav/View/book_details_screen.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  List<Book> _searchResults = [];

  void _filterBooks(String query) {
    setState(() {
      _searchResults = _books
          .where((book) =>
              book.title.toLowerCase().contains(query.toLowerCase()) ||
              book.isbn.contains(query) ||
              book.ddc.contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Row(
          children: [
            Image.asset(
              'assets/images/inlib_logo_trsp.png',
              height: 50.0,
            ),
            const SizedBox(
              width: 15.0,
            ),
            const Text(
              'InLib Navigation',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            child: TextField(
              onChanged: (value) {
                _filterBooks(value);
              },
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Εισάγετε Τίτλο ή ISBN',
              ),
            ),
          ),
          ElevatedButton(onPressed: () {}, child: Text("Αναζήτηση")),
          Expanded(
            child: ListView.builder(
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final book = _searchResults[index];
                return ListTile(
                  title: Text(book.title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.author),
                      Text('Θέση: ${book.ddc}'),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BookDetailsScreen(book: book),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

//dummy data
final List<Book> _books = [
  //Λογοτεχνία
  Book(
      title: 'The Lord of the Rings',
      author: 'J.R.R. Tolkien',
      isbn: '978-0547928227',
      ddc: '823.912'),
  Book(
      title: 'Pride and Prejudice',
      author: 'Jane Austen',
      isbn: '978-0141439518',
      ddc: '823.7'),
  Book(
      title: '1984',
      author: 'George Orwell',
      isbn: '978-0451524935',
      ddc: '823.914'),
  //Πληροφορική
  Book(
      title: 'Clean Code: A Handbook of Agile Software Craftsmanship',
      author: 'Robert C. Martin',
      isbn: '978-0132350881',
      ddc: '005.1'),
  Book(
      title: 'Cracking the Coding Interview',
      author: 'Gayle Laakmann McDowell',
      isbn: '978-0984782857',
      ddc: '005.1'),
  Book(
      title: 'The Pragmatic Programmer',
      author: 'Andrew Hunt & David Thomas',
      isbn: '978-0201633859',
      ddc: '005.1'),
  Book(
      title: 'Introduction to Algorithms',
      author: 'Thomas H. Cormen et al.',
      isbn: '978-0262033848',
      ddc: '005.13'),
  Book(
      title: 'Design Patterns: Elements of Reusable Object-Oriented Software',
      author: 'Erich Gamma et al.',
      isbn: '978-0201633613',
      ddc: '005.1'),
  Book(
      title: 'Effective Java',
      author: 'Joshua Bloch',
      isbn: '978-0134685991',
      ddc: '005.133'),
  Book(
      title: 'Python Crash Course',
      author: 'Eric Matthes',
      isbn: '978-1593276034',
      ddc: '005.133'),
  Book(
      title: 'Automate the Boring Stuff with Python',
      author: 'Al Sweigart',
      isbn: '978-1593279929',
      ddc: '005.133'),
  Book(
      title: 'Fluent Python',
      author: 'Luciano Ramalho',
      isbn: '978-1491952689',
      ddc: '005.133'),
  // Μαθηματικά
  Book(
      title: 'Calculus',
      author: 'James Stewart',
      isbn: '978-1285740621',
      ddc: '515'),
  Book(
      title: 'Linear Algebra and Its Applications',
      author: 'David C. Lay',
      isbn: '978-0321982384',
      ddc: '512.5'),
  Book(
      title: 'Probability and Statistics for Engineers and Scientists',
      author: 'Sheldon M. Ross',
      isbn: '978-0123861591',
      ddc: '519.2'),

  // Φυσική
  Book(
      title: 'Physics for Scientists and Engineers',
      author: 'Paul A. Tipler & Gene P. Mosca',
      isbn: '978-1429201247',
      ddc: '530'),
  Book(
      title: 'Modern Physics',
      author: 'Kenneth S. Krane',
      isbn: '978-0471859177',
      ddc: '539'),

  // Χημεία
  Book(
      title: 'Chemistry: The Central Science',
      author: 'Theodore L. Brown et al.',
      isbn: '978-0321910424',
      ddc: '540'),
  Book(
      title: 'Organic Chemistry',
      author: 'Paula Yurkanis Bruice',
      isbn: '978-0321809087',
      ddc: '547'),

  // Ιστορία
  Book(
      title: 'Sapiens: A Brief History of Humankind',
      author: 'Yuval Noah Harari',
      isbn: '978-0062464165',
      ddc: '909'),
  Book(
      title: 'The History of the Peloponnesian War',
      author: 'Thucydides',
      isbn: '978-0140440391',
      ddc: '938.05'),
];
