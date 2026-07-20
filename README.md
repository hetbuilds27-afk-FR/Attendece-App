<div align="center">

# 📊 My Attendance

**Never get caught below your attendance target again.**

Track subjects, know exactly how many classes you can skip, and keep it all safely backed up — all in one clean Flutter app.

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)

</div>

---

## ✨ Why this exists

Attendance rules are simple in theory — hit 75%, or whatever your target is — and a nightmare to track in your head across five subjects with different schedules. **My Attendance** does the math for you, in real time, so you always know exactly where you stand.

## 🚀 Features

| | |
|---|---|
| 🎯 **Target-based projections** | See exactly how many classes you can safely skip — or must attend — to hit your target percentage |
| 📅 **Weekly schedules** | Set which weekdays each subject meets so the app knows what's actually expected |
| 📈 **Per-subject insights** | Live attendance percentage for every subject, updated as you log classes |
| 🧩 **Home screen widget** | Check your stats without even opening the app |
| ☁️ **Auto-backup** | Pick a folder once — your data quietly backs itself up there, automatically, from then on |
| ♻️ **Easy restore** | Reinstalling or switching devices? Point it at your backup folder and you're back in seconds |
| 🌗 **Light & dark themes** | Matches your system, or set it yourself |

## 🛠️ Built with

- **[Flutter](https://flutter.dev)** — cross-platform UI toolkit
- **`shared_preferences`** — lightweight local settings storage
- **`file_picker`** — native folder/file selection
- **Android Storage Access Framework** (via a small native `MethodChannel`) — reliable, permission-safe backup folder access

## 📦 Getting started

```bash
# Clone the repo
git clone https://github.com/hetbuilds27-afk-FR/Attendece-App.git
cd Attendece-App

# Install dependencies
flutter pub get

# Run it
flutter run
```

### Requirements

- Flutter SDK (`^3.12.0` or newer)
- Android Studio / a connected Android device or emulator

## 📥 Building a release APK

```bash
flutter build apk --release
```

Once the build finishes **successfully** (check the terminal for `✓ Built build\app\outputs\flutter-apk\app-release.apk`), the file will be at:

```
build\app\outputs\flutter-apk\app-release.apk
```

relative to your project root — e.g. `C:\Users\Hetkumar\Programs\attendece_tracker\build\app\outputs\flutter-apk\app-release.apk`.

Install it directly on a connected device with:

```bash
flutter install
```

or copy the APK file to your phone and install it manually.

> **Don't see the file?** The `build\` folder is only created after a *successful* release build — `flutter run` (debug mode) won't create it, and neither will a build that errored out partway through. Re-run `flutter build apk --release` and check the terminal output for the actual save path it prints at the end; that's always the source of truth over any path written here.

## 🤝 Contributing

Found a bug or have an idea? Open an issue or send a pull request — contributions are welcome.

---

<div align="center">

Made with ☕ and a healthy fear of falling below 75%.

</div>
