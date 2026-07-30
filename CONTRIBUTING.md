# Contributing to BlueDebug

First off, thank you for considering contributing to BlueDebug! 🎉

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/your-username/BlueDebug.git`
3. Create a feature branch: `git checkout -b feature/amazing-feature`
4. Make your changes
5. Push to your fork: `git push origin feature/amazing-feature`
6. Open a Pull Request

## Development Setup

### Prerequisites
- Flutter 3.x
- Dart 3.x
- Android Studio / Xcode
- A BLE device for testing

### Install Dependencies
```bash
flutter pub get
```

### Run the App
```bash
flutter run
```

## Project Structure

```
lib/
├── ui/           # All UI pages
├── core/         # Business logic layer
├── adapter/      # Bluetooth abstraction layer
└── plugins/      # Vendor chip plugins
```

## Adding a New Chip Plugin

1. Create a new file in `lib/plugins/` (e.g. `my_chip_plugin.dart`)
2. Extend `BaseChipPlugin` and implement all required methods
3. Register your plugin in `PluginRegistry`
4. Add a JSON config file in `assets/plugin_config/`
5. Add register maps in `assets/register_map/` if applicable

## Coding Standards

- Follow [Dart Style Guide](https://dart.dev/guides/language/effective-dart/style)
- Use `flutter analyze` before committing
- Write tests for new features
- Add doc comments to public APIs

## Commit Convention

We use conventional commits:

```
feat: add new feature
fix: fix a bug
docs: documentation only
refactor: code refactoring
test: add tests
chore: build/tooling changes
```

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
