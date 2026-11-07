# LibReady

A private, offline library and reader for **PDF** and **EPUB** books, built with Flutter for **Android and iOS**.

Books live on a wooden shelf, spines out, with the date you last read them written above each cover. Open a book and the page peels over with a real page-curl animation. Nothing leaves your device — there is no account, no server and no network access.

---

## Features

### Library

- Dark wood shelves with standing book covers, plank shadows and a warm header.
- Covers are generated from the **first page of the book** (PDF page 1 or the EPUB cover image), with a typographic fallback when a book has no artwork.
- Date labels above each cover — last opened, or the date added if unread.
- Automatic shelf layout that adapts to phone and tablet widths.
- Import several files at once with a progress dialog and failure counts.
- Duplicate detection by file fingerprint, so the same book is never imported twice.
- Search across title, author, description and language.
- Filters for **All / Reading / Finished / Favourites**.
- Sort by **Recently read, Title A–Z, Author A–Z, Recently added, Largest first**.
- Long-press a book for actions: details, change cover from photos, rebuild cover from the book, mark as finished, remove.
- Empty state, error state, storage statistics and reading statistics.

### Reader

- Full-screen reader; tap the centre of the page to show or hide the toolbar.
- **Page-turn effects**: page curl (default), book flip, slide, fade and instant. The current page is snapshot and animated over the incoming page, so the next page is already rendered underneath.
- Swipe or tap the edges to turn pages; tap the middle to show the toolbar.
- Progress saving with debounce, plus a guaranteed save when you leave the reader.
- Table of contents, bookmarks with optional notes, in-book search with result snippets, and jump-to-page (search and contents are EPUB features; PDFs are rendered page images).
- Four reader themes: **Paper, Sepia, Night, Black**.
- Adjustable font size, line height, page margins, justified text and serif/sans-serif typography.
- EPUB re-paginates after typography changes while keeping your place through character offsets.
- PDF zoom controls with neighbour-page prefetching and an LRU page cache.
- Dimming overlay (brightness slider) and optional page numbers.

### Reading dashboard

- Continue-reading card with cover, progress and a one-tap resume.
- Reading and finished shelves, plus summary statistics.

### Settings

- App light / dark / system appearance.
- Toggle shelf dates and set the default reader preferences used for every new book.
- Storage usage, missing-file check, prune database entries and delete-everything controls.
- Offline-by-design notice and open-source licence viewer.

---

## Requirements

| Tool | Version used |
| --- | --- |
| Flutter | 3.47.9 (stable) |
| Dart | 3.13.7 |
| Android | Android Studio with JDK 17, Android SDK 24+ |
| iOS | macOS with Xcode 15+ |

The project targets Android and iOS only. No web, desktop or server components are included.

---

## Getting started in Android Studio

1. Install **Android Studio** (latest), including an Android SDK (API 24 or newer), then accept the SDK licences.
2. Install the **Flutter SDK** (stable; tested with 3.47.9) and add its `bin` folder to `PATH`.
3. In Android Studio, install the **Flutter** and **Dart** plugins and point the Flutter plugin at your SDK folder.
4. Open this folder as a project: `File → Open… → C:\Users\ranve\Desktop\personal\myLibready`.
5. Let the IDE run `flutter pub get`. If it doesn't, open a terminal in the project root and run:

   ```bash
   flutter pub get
   ```

6. Select an emulator or a USB device in the device dropdown.
7. Press **Run** (▶), or from the terminal:

   ```bash
   flutter run
   ```

### Command line

```bash
flutter pub get          # fetch packages
flutter analyze          # static analysis (kept at zero issues)
flutter test             # widget smoke tests
flutter run              # debug run on the selected device
```

### Build an installable APK

```bash
flutter build apk --debug     # debug build
flutter build apk --release   # optimized build
```

The APK is written to `build/app/outputs/flutter-apk/`.

> **Signing:** the release build currently uses the debug signing config so `flutter run --release` works out of the box. Before publishing, create a keystore and replace the `signingConfig` in `android/app/build.gradle.kts`. See Flutter's “Build and release an Android app” guide.

### Build for iOS

On macOS with Xcode installed:

```bash
flutter build ios
# or open the workspace and archive:
open ios/Runner.xcworkspace
```

Then set your development team under **Signing & Capabilities** and run on a device or simulator.

---

## Using the app

1. On the **Library** tab, tap **Add book** and select one or more `.pdf` or `.epub` files.
2. Each file is copied into the app's private storage, fingerprinted, parsed and given a cover from its first page.
3. Tap a cover to read. Swipe or tap the edges to turn pages; tap the centre for the toolbar.
4. Use the toolbar for contents, bookmarks, search, page jump, reader appearance and page-turn style.
5. Long-press a cover for details, cover replacement, or removal.

Supported file types:

- **PDF** — rendered natively with `pdfx`.
- **EPUB 2 / EPUB 3** — custom container/OPF/spine/nav/NCX parser; reflowable text is paginated on-device.

---

## Privacy and offline behaviour

- All books, covers, bookmarks and progress are stored **locally** in the app's Documents directory.
- No analytics, accounts, advertising, cloud sync or network requests.
- Deleting a book removes its copied file, cover, bookmarks and reading progress.
- The release build declares no network permission on Android.

Data locations (inside the app sandbox):

```
Documents/
  libready.db          # metadata, bookmarks, progress
  LibReady/
    books/             # imported copies of PDF/EPUB files
    covers/            # generated / user-chosen cover images
```

On Android the sandbox is the app's private storage. On iOS the app's Documents container is visible in the Files app because document sharing is enabled, so you can back it up or copy books out; nothing is uploaded anywhere.

---

## Architecture

```
lib/
  main.dart                     app entry point
  app.dart                      MaterialApp, providers, theming
  core/                         theme, formatting and id helpers
  data/                         models, sqflite database, repositories, storage
  epub/                         EPUB archive, OPF parser, HTML→blocks, paginator
  reader/                       engine abstraction, PDF/EPUB engines, page views,
                                curl painter and the shared BookPager
  services/                     cover generation
  features/
    home/                       bottom-navigation shell
    library/                    wooden shelf library and book actions
    reading/                    continue-reading dashboard
    reader/                     reader screen, sheets and dialogs
    settings/                   app and default-reader settings
    common/                     shared sheets, toasts and confirm dialogs
tool/
  generate_icons.dart           regenerates Android/iOS launcher icons
```

Key design points:

- **Engines** expose a uniform `ReaderEngine` interface (`pageCount`, render a page, search, map positions), implemented by `PdfReaderEngine` and `EpubReaderEngine`.
- **BookPager** captures the outgoing page with a `RepaintBoundary`, then animates it over the incoming page using `PageCurlPainter`. PDF pages are `ui.Image` bitmaps; EPUB pages are Flutter widgets.
- **EPUB pagination** lays out parsed HTML blocks with `TextPainter` against the available page size and stores character offsets so positions survive font and layout changes.
- **Persistence** uses `sqflite` for books and bookmarks, `shared_preferences` for app and reader settings, and the filesystem for book/cover blobs.
- **State** is provided with `provider`; repositories are created once in `main.dart` and shared through the widget tree.

---

## Tests

```bash
flutter test
flutter analyze
```

`test/ui_smoke_test.dart` exercises the library shelf, reading dashboard and settings screen with an in-memory fake repository, so the tests run without a device, database or file plugins. `test/epub_test.dart` builds a small EPUB in a temporary folder and checks metadata, chapters, TOC, cover extraction, formatted runs, error handling and multi-page pagination.

To redraw the launcher icon, run:

```bash
dart run tool/generate_icons.dart
```

---

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `flutter` not recognised | Add the Flutter SDK `bin` folder to `PATH`, or run `flutter.bat` with its full path. |
| Gradle/JDK errors on first Android build | Install JDK 17 via Android Studio (`Settings → Build Tools → Gradle → Gradle JDK`) and accept the Android SDK licences. |
| A PDF shows blank pages | Try rebuilding the cover from the book details, or confirm the file opens in another reader. Very large scanned PDFs may render slowly on low-memory devices. |
| An EPUB has no cover | LibReady falls back to a generated typographic cover; you can also choose one from your photo library. |
| Wrong duplicate discarded on import | Duplicates are detected by a content fingerprint. Renaming a file does not create a new book. |

---

## Licence

Personal project. Third-party package licences are available in the app under **Settings → Open source licences**.
