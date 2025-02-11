# InLib Navigation

A Flutter application for library navigation and book management using optical character recognition (OCR) for shelf location detection.

## Features

- Book search by title, author, or ISBN
- DDC (Dewey Decimal Classification) based navigation
- Real-time text recognition using Google ML Kit
- Camera integration for shelf label scanning
- Support for both gallery images and live camera feed
- Multi-language text recognition support

## Technical Details

The application is built using:
- Flutter framework
- Google ML Kit for text recognition
- Camera plugin for Flutter
- Material Design 3

## Project Structure

```
lib/
├── Model/
│   └── book.dart         # Book data model
├── View/
│   ├── home_view.dart    # Main search interface
│   ├── camera_view.dart  # Camera handling
│   ├── gallery_view.dart # Image gallery
│   └── detector_view.dart # Text detection view
└── main.dart            # Application entry point
```

## Setup Instructions

1. Prerequisites:
   - Flutter SDK (latest stable version)
   - Android Studio or VS Code with Flutter plugins
   - iOS/Android development environment

2. Dependencies:
   ```yaml
   dependencies:
     flutter:
       sdk: flutter
     camera: ^latest_version
     google_mlkit_text_recognition: ^latest_version
     image_picker: ^latest_version
     path_provider: ^latest_version
   ```

3. Clone and Run:
   ```bash
   git clone [repository-url]
   cd in_lib_nav
   flutter pub get
   flutter run
   ```

## License

MIT License

Copyright (c) 2024

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Contributing

[Contribution guidelines to be added]

