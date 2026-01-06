# Jellyfin Media Management Tool

[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev/)
[![Material 3](https://img.shields.io/badge/Material--3-%236750A4.svg?style=for-the-badge&logo=material-design&logoColor=white)](https://m3.material.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-blue?style=for-the-badge)](https://flutter.dev/desktop)

A powerful, cross-platform desktop application built with Flutter to help you organize and manage your media library according to Jellyfin's naming standards.

## 🚀 Features

### 📂 Advanced File Browser
- **Multi-format Support**: Visual icons for Video, Audio, Images, Subtitles, and Metadata.
- **Smart Sorting**: Sort by Name, Type, Date Modified, or Size (Ascending/Descending).
- **Directory Monitoring**: Automatically detects changes in the file system and refreshes the view.
- **Context Menu**: Right-click or long-press to quickly rename files and folders.
- **Navigation**: Easy "Go to Parent" and "Create Folder" operations.

### 🔍 Rich Media Preview
- **Video Metadata**: View duration and resolution for MKV, MP4, and other common formats.
- **Interactive Image Viewer**: Zoom and pan previews for posters and backdrops.
- **Text Preview**: Monospaced view for subtitle files and NFO metadata.
- **System Integration**: One-click to open files in your system's default player or editor.

### 🏷️ Jellyfin Naming Operations
Automate tedious renaming tasks with built-in rules:
- **Match Folder**: Instantly rename a file to match its parent directory.
- **Extras Support**: Quickly tag files as `-featurette` or `-interview`.
- **Part Sequencing**: Easy dialog to handle multi-part movies (`-part1`, `-part2`, etc.).
- **TV Show Naming**: Smart `SxxExx` formatting that remembers your last episode number for batch processing.
- **Subtitle Standardization**: Link subtitles to video files with language codes (e.g., `.chi.default.ass`).

### 🎨 Modern UI & UX
- **Material 3 Design**: Clean, responsive interface designed for desktop use.
- **Theme Support**: Light, Dark, and System-adaptive themes.
- **Localization**: Full support for English and Chinese (中文).
- **Persistent Settings**: Your preferences and last-used directory are saved locally in a `config.json` file.

## 🛠️ Tech Stack
- **Framework**: Flutter (Material 3)
- **State Management**: Provider
- **Media Engine**: Media Kit (libmpv)
- **Storage**: Local JSON configuration

## 📦 Getting Started

### Prerequisites
- Flutter SDK (>= 3.10.4)
- libmpv (required for video metadata extraction)

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/Jellyfin-Media-Management-Tool.git
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   ```bash
   flutter run -d windows # or macos / linux
   ```

## 📄 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
