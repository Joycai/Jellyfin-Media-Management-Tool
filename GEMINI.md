# GEMINI.md - Jellyfin Media Management Tool

This document provides context and guidelines for interacting with the Jellyfin Media Management Tool codebase.

## Project Overview

The **Jellyfin Media Management Tool** is a cross-platform desktop application built with Flutter. Its primary purpose is to help users organize and manage their media libraries (movies, TV shows, music, etc.) according to [Jellyfin's naming standards](https://jellyfin.org/docs/general/server/media/naming/).

### Core Technologies
- **Framework:** [Flutter](https://flutter.dev/) (Material 3)
- **Language:** [Dart](https://dart.dev/)
- **State Management:** [Provider](https://pub.dev/packages/provider)
- **Media Engine:** [Media Kit](https://media-kit.github.io/) (based on libmpv) for metadata extraction and media handling.
- **Localization:** Flutter `intl` and ARB files for multi-language support (English & Chinese).
- **Storage:** Local JSON configuration for settings and user preferences.

### Key Features
- **File Browser:** Advanced navigation with smart sorting and real-time directory monitoring.
- **Media Preview:** Rich previews for video (metadata), images, and text (subtitles/NFO).
- **Renaming Engine:** Automated renaming rules for Jellyfin compliance (extras, TV episodes, multi-part movies, standardized subtitles).
- **Web Search:** Integrated search to find media information from online databases.

## Project Structure

```text
lib/
├── main.dart                 # Application entry point, theme configuration, and main navigation.
├── l10n/                     # Localization resources (app_en.arb, app_zh.arb) and generated files.
├── screens/                  # Top-level UI screens (MediaManagerScreen, etc.).
├── services/                 # Business logic and state management.
│   ├── settings_service.dart # Manages app configuration, theme, and localization.
│   ├── rename_service.dart   # Core logic for Jellyfin-compliant renaming rules.
│   └── file_label_service.dart# Utilities for file type identification and icon mapping.
└── widgets/                  # Reusable UI components.
    └── file_preview.dart     # Detailed preview and operation panel for selected files.
```

## Building and Running

### Prerequisites
- Flutter SDK (>= 3.10.4)
- **libmpv** must be installed on the system for media metadata extraction.

### Common Commands
- **Install Dependencies:** `flutter pub get`
- **Run Application:** `flutter run -d <windows|macos|linux>`
- **Generate L10n:** `flutter gen-l10n` (usually handled automatically by `flutter run`)
- **Build Release:**
  - Windows: `flutter build windows`
  - macOS: `flutter build macos`
  - Linux: `flutter build linux`

## Development Conventions

### UI & Styling
- Strictly adhere to **Material 3** design principles.
- Use `ColorScheme` from seed colors for consistent branding.
- Support both **Light** and **Dark** themes.
- Ensure the layout is responsive for desktop window resizing.

### State Management
- Use `ChangeNotifier` and `Provider` for reactive state updates.
- Keep UI components (widgets) as lean as possible, delegating logic to services.

### Localization
- All user-facing strings MUST be localized using `AppLocalizations.of(context)`.
- When adding new strings, update both `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb`.

### Renaming Rules
- Any new renaming logic should be added to `lib/services/rename_service.dart` and follow the `RenameRule` enum pattern.
- Renaming operations should be atomic and provide user feedback via `ScaffoldMessenger` on failure.

### File Handling
- Use the `path` package for all path manipulations to ensure cross-platform compatibility.
- Prefer `FileSystemEntity` for generic file/directory operations.
