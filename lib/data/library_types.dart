enum SortMode { recent, title, author, added, size }

enum LibraryFilter { all, reading, finished, favorites }

/// How the books are presented on the shelves.
enum ShelfDisplay { covers, spines }

extension SortModeLabels on SortMode {
  String get label {
    switch (this) {
      case SortMode.recent:
        return 'Recently read';
      case SortMode.title:
        return 'Title A–Z';
      case SortMode.author:
        return 'Author A–Z';
      case SortMode.added:
        return 'Recently added';
      case SortMode.size:
        return 'Largest first';
    }
  }
}

extension LibraryFilterLabels on LibraryFilter {
  String get label {
    switch (this) {
      case LibraryFilter.all:
        return 'All';
      case LibraryFilter.reading:
        return 'Reading';
      case LibraryFilter.finished:
        return 'Finished';
      case LibraryFilter.favorites:
        return 'Favourites';
    }
  }
}

extension ShelfDisplayLabels on ShelfDisplay {
  String get label {
    switch (this) {
      case ShelfDisplay.covers:
        return 'Covers facing forward';
      case ShelfDisplay.spines:
        return 'Spines facing out';
    }
  }

  String get description {
    switch (this) {
      case ShelfDisplay.covers:
        return 'See the artwork of every book.';
      case ShelfDisplay.spines:
        return 'A classic bookcase packed with colourful spines.';
    }
  }
}
