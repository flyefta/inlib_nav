// lib/View/home_view.dart
import 'package:flutter/material.dart';
import 'package:inlib_nav/Model/book.dart';
import 'package:inlib_nav/Services/dummy_books_service.dart';
import 'package:inlib_nav/View/book_details_screen.dart';
import 'package:inlib_nav/constants.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  late List<Book> _allBooks;
  List<Book> _searchResults = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _allBooks = getDummyBooks();
    _searchResults = [];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterBooks(String query) {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _searchResults =
          _allBooks.where((book) {
            final lowerCaseQuery = query.toLowerCase();
            return book.title.toLowerCase().contains(lowerCaseQuery) ||
                book.author.toLowerCase().contains(lowerCaseQuery) ||
                book.isbn.contains(query) ||
                book.loc.toLowerCase().contains(lowerCaseQuery);
          }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: scaffoldBackroundColor,
      appBar: myAppBar,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _filterBooks,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Εισάγετε Τίτλο, Συγγραφέα, ISBN ή LOC',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: _filterBooks,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child:
                _searchResults.isEmpty && _searchController.text.isNotEmpty
                    ? const Center(child: Text('Δεν βρέθηκαν αποτελέσματα.'))
                    : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final book = _searchResults[index];
                        return ListTile(
                          title: Text(book.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(book.author),
                              Text('LOC: ${book.loc}'),
                              Text(
                                'Ράφι: ${book.shelf}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue[800],
                                ),
                              ),
                            ],
                          ),
                          onTap: () {
                            FocusScope.of(context).unfocus();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (context) => BookDetailsScreen(book: book),
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
