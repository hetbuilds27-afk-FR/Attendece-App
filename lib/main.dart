import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _widgetChannel = MethodChannel('attendance_tracker/widget');

Future<void> _refreshHomeWidgets() async {
  try {
    await _widgetChannel.invokeMethod<void>('refresh');
  } on PlatformException {
    // Home widgets are Android-only; ignore refresh failures elsewhere.
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AttendanceApp());
}

/// Drop-in replacement for [showDialog] that pops the dialog in with a
/// blurred backdrop and a springy overshoot, instead of the stock fade.
/// Same signature as showDialog so every call site can just swap the name.
Future<T?> showFunDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  HapticFeedback.mediumImpact();
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 480),
    pageBuilder: (ctx, animation, secondaryAnimation) => builder(ctx),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: const Interval(0, 0.4, curve: Curves.easeOut),
      );
      final bounce = CurvedAnimation(parent: animation, curve: Curves.elasticOut);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6 * fade.value, sigmaY: 6 * fade.value),
        child: FadeTransition(
          opacity: fade,
          child: Transform.scale(
            scale: bounce.value.clamp(0.0, 1.35),
            child: child,
          ),
        ),
      );
    },
  );
}

/// A gradient icon badge that pops in with a little overshoot + spin,
/// meant to sit half-overlapping the top edge of a dialog card.
class _BounceBadge extends StatelessWidget {
  const _BounceBadge({required this.icon, required this.colors});

  final IconData icon;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 650),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.rotate(
          angle: (1 - value) * -0.5,
          child: Transform.scale(scale: value.clamp(0.0, 1.3), child: child),
        );
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Theme.of(context).scaffoldBackgroundColor,
            width: 4,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

/// Shared shell for the "fun" style dialogs: a rounded card with a
/// bouncy gradient badge poking out of the top edge.
class _FunDialogCard extends StatelessWidget {
  const _FunDialogCard({
    required this.icon,
    required this.iconColors,
    required this.title,
    required this.content,
    this.actionLabel = 'Got it',
  });

  final IconData icon;
  final List<Color> iconColors;
  final String title;
  final Widget content;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 32),
            padding: const EdgeInsets.fromLTRB(24, 44, 24, 20),
            constraints: const BoxConstraints(maxHeight: 520),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF15201D) : Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 30,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(child: content),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: iconColors.last,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          _BounceBadge(icon: icon, colors: iconColors),
        ],
      ),
    );
  }
}

/// A tappable pill showing a date with a calendar icon, used inside
/// the "Log a Past Class" and "Mark a Day" dialogs.
class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: _tealSeed.withValues(alpha: isDark ? 0.16 : 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 17, color: _tealSeed),
              const SizedBox(width: 10),
              Text(
                '${date.day}/${date.month}/${date.year}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: theme.colorScheme.onSurface),
              ),
              const Spacer(),
              Icon(Icons.expand_more_rounded, size: 18, color: _tealSeed.withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rounded, color-coded choice chip for Present/Absent style toggles.
/// Used both as a full-width chip (Log a Past Class) and a compact P/A
/// chip (Mark a Day's per-subject rows).
class _PAChip extends StatelessWidget {
  const _PAChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
    this.icon,
    this.compact = false,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = compact ? 10.0 : 14.0;
    return Material(
      color: selected ? color.withValues(alpha: theme.brightness == Brightness.dark ? 0.2 : 0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 13, vertical: 8)
              : const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: selected ? color.withValues(alpha: 0.6) : theme.dividerColor,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? color : theme.colorScheme.onSurface.withValues(alpha: 0.45)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 13 : 14.5,
                  color: selected ? color : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keys + helpers for reading/writing app state to disk via
/// shared_preferences. Kept in one place so storage format changes
/// don't have to be hunted down across the widget tree.
class _Store {
  static const _kThemeMode = 'theme_mode';
  static const _kTargetPercentage = 'target_percentage';
  static const _kSubjects = 'subjects';

  static Future<ThemeMode> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kThemeMode);
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  static Future<double> loadTargetPercentage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_kTargetPercentage) ?? 75;
  }

  static Future<void> saveTargetPercentage(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kTargetPercentage, value);
    await _refreshHomeWidgets();
  }

  static Future<List<Subject>> loadSubjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSubjects);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Subject.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupt or outdated data shouldn't crash the app on launch.
      return [];
    }
  }

  static Future<void> saveSubjects(List<Subject> subjects) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(subjects.map((s) => s.toJson()).toList());
    await prefs.setString(_kSubjects, raw);
    await _refreshHomeWidgets();
  }

  static const _kBackupFolderPath = 'backup_folder_path';
  static const _kBackupSetupDone = 'backup_setup_done';
  static const _kLastBackupAt = 'last_backup_at';

  static Future<String?> loadBackupFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kBackupFolderPath);
  }

  static Future<void> saveBackupFolderPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_kBackupFolderPath);
    } else {
      await prefs.setString(_kBackupFolderPath, path);
    }
  }

  static Future<bool> loadBackupSetupDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBackupSetupDone) ?? false;
  }

  static Future<void> saveBackupSetupDone(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBackupSetupDone, value);
  }

  static Future<DateTime?> loadLastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastBackupAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<void> saveLastBackupAt(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastBackupAt, time.toIso8601String());
  }
}

const _backupFileName = 'attendance_backup.json';

/// Talks to a small hand-written native handler in `MainActivity.kt`
/// (channel `attendance_tracker/saf`) that performs Storage Access
/// Framework operations directly via Android's own APIs.
///
/// This deliberately avoids third-party SAF plugins: at the time this
/// was written, the popular ones (e.g. `shared_storage`) ship an Android
/// `build.gradle` written for a much older Android Gradle Plugin (their
/// own `buildscript` block, `jcenter()`, no `namespace`), which fails to
/// build under AGP 9's new build DSL. A ~15-line native MethodChannel
/// living in your own `android/app` module sidesteps that entirely,
/// since that module already builds fine with your current toolchain.
class _Saf {
  static const _channel = MethodChannel('attendance_tracker/saf');

  /// Shows the system folder picker and requests a persistable
  /// read/write grant. Returns the picked folder's tree URI as a
  /// string, or null if the user cancelled or something went wrong.
  static Future<String?> openTree() async {
    try {
      return await _channel.invokeMethod<String>('openTree');
    } on PlatformException {
      return null;
    }
  }

  /// True if we still hold a valid persisted read/write grant for
  /// [treeUri].
  static Future<bool> hasPermission(String treeUri) async {
    try {
      return await _channel.invokeMethod<bool>(
            'hasPermission',
            {'treeUri': treeUri},
          ) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Writes [content] to a file named [fileName] inside [treeUri],
  /// creating it if it doesn't already exist, overwriting it if it does.
  static Future<bool> writeFile(String treeUri, String fileName, String content) async {
    try {
      return await _channel.invokeMethod<bool>('writeFile', {
            'treeUri': treeUri,
            'fileName': fileName,
            'content': content,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  /// Reads the content of [fileName] inside [treeUri], or null if it
  /// doesn't exist or can't be read.
  static Future<String?> readFile(String treeUri, String fileName) async {
    try {
      return await _channel.invokeMethod<String>('readFile', {
        'treeUri': treeUri,
        'fileName': fileName,
      });
    } on PlatformException {
      return null;
    }
  }
}

ThemeMode _themeModeFromName(String? name) => switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

/// Opens the OS folder picker for the backup folder.
///
/// On Android this uses the Storage Access Framework (SAF) directly and
/// asks for a *persistable* permission grant, returning a `content://`
/// tree URI. Unlike `file_picker`'s `getDirectoryPath()`, this URI can
/// actually be used to read/write files reliably later (including after
/// the app restarts), because we talk to it through SAF APIs instead of
/// `dart:io`'s `File`, which does not understand SAF-granted folders.
///
/// Note: reinstalling the app still invalidates the grant (Android ties
/// SAF permissions to the app's UID, which changes on reinstall) — the
/// user will need to re-pick the folder once after a reinstall, but the
/// picked backup file inside it will now actually be found.
Future<String?> _pickBackupFolder({required String dialogTitle}) async {
  if (Platform.isAndroid) {
    return _Saf.openTree();
  }
  return FilePicker.getDirectoryPath(dialogTitle: dialogTitle);
}

/// Reads and writes the single JSON backup file that mirrors the app's
/// full state (subjects + settings) inside a user-chosen folder.
///
/// [location] is either a plain filesystem path (iOS/desktop) or an
/// Android `content://` tree URI string (Android, via SAF).
class _BackupFile {
  static bool _isAndroidTreeUri(String location) =>
      Platform.isAndroid && location.startsWith('content://');

  static File _fileIn(String folderPath) =>
      File('$folderPath${Platform.pathSeparator}$_backupFileName');

  /// Human-friendly label for the folder, for display in Settings.
  static String displayLabel(String location) {
    if (_isAndroidTreeUri(location)) {
      // content://.../tree/primary%3ADownload%2FBackups -> "Backups"
      final decoded = Uri.decodeComponent(location);
      final segments = decoded.split(RegExp(r'[:/]')).where((s) => s.isNotEmpty).toList();
      return segments.isEmpty ? decoded : segments.last;
    }
    final normalized = location.replaceAll('\\', '/');
    final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? location : segments.last;
  }

  static Map<String, dynamic> buildJson({
    required List<Subject> subjects,
    required ThemeMode themeMode,
    required double targetPercentage,
  }) {
    return {
      'app': 'My Attendance',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'themeMode': themeMode.name,
      'targetPercentage': targetPercentage,
      'subjects': subjects.map((s) => s.toJson()).toList(),
    };
  }

  /// Parses a decoded backup JSON map back into app state.
  static ({List<Subject> subjects, ThemeMode themeMode, double targetPercentage})
      parse(Map<String, dynamic> data) {
    final subjectsRaw = (data['subjects'] as List?) ?? const [];
    final subjects = subjectsRaw
        .map((e) => Subject.fromJson(e as Map<String, dynamic>))
        .toList();
    return (
      subjects: subjects,
      themeMode: _themeModeFromName(data['themeMode'] as String?),
      targetPercentage: (data['targetPercentage'] as num?)?.toDouble() ?? 75,
    );
  }

  /// Writes [json] to the backup file inside [location]. Returns true on success.
  static Future<bool> write(String location, Map<String, dynamic> json) async {
    final content = const JsonEncoder.withIndent('  ').convert(json);
    try {
      if (_isAndroidTreeUri(location)) {
        return await _Saf.writeFile(location, _backupFileName, content);
      }
      final file = _fileIn(location);
      await file.create(recursive: true);
      await file.writeAsString(content);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reads and decodes the backup file from [location], or null if
  /// it doesn't exist or can't be parsed.
  static Future<Map<String, dynamic>?> read(String location) async {
    try {
      if (_isAndroidTreeUri(location)) {
        final raw = await _Saf.readFile(location, _backupFileName);
        if (raw == null) return null;
        final decoded = jsonDecode(raw);
        return decoded is Map<String, dynamic> ? decoded : null;
      }
      final file = _fileIn(location);
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// True if we still hold a valid, persisted permission grant for
  /// [location]. Only meaningful for Android tree URIs; always true
  /// otherwise. Use this to detect a grant that's gone stale (e.g. the
  /// user revoked it, or — most commonly — the app was reinstalled).
  static Future<bool> hasValidAccess(String location) async {
    if (!_isAndroidTreeUri(location)) return true;
    try {
      return await _Saf.hasPermission(location);
    } catch (_) {
      return false;
    }
  }
}

/// A reusable two-button confirmation dialog, styled to match the rest
/// of the app's "fun" dialogs. Returns true/false for confirm/cancel,
/// or null if dismissed.
Future<bool?> showChoiceDialog({
  required BuildContext context,
  required IconData icon,
  required Color iconColor,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
  bool barrierDismissible = true,
}) {
  return showFunDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
      final colorScheme = Theme.of(dialogContext).colorScheme;
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: isDark ? const Color(0xFF1C1F2A) : Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        cancelLabel,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.75),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: destructive ? Colors.red : iconColor,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

const _tealSeed = Color(0xFF0D9488);

ThemeData _buildTheme(Brightness brightness) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: _tealSeed,
    brightness: brightness,
  );
  final isDark = brightness == Brightness.dark;
  final outlineColor = isDark
      ? _tealSeed.withValues(alpha: 0.35)
      : _tealSeed.withValues(alpha: 0.25);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: isDark ? const Color(0xFF0E1513) : const Color(0xFFF7FAF9),
    // Remove the spreading web-style ripple; give an instant, subtle
    // highlight instead so taps feel native rather than like a webpage.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: _tealSeed.withValues(alpha: 0.06),
    cardTheme: CardThemeData(
      elevation: 0,
      color: isDark ? const Color(0xFF15201D) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: outlineColor, width: 1.2),
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      centerTitle: false,
      backgroundColor: isDark ? const Color(0xFF0E1513) : const Color(0xFFF7FAF9),
      foregroundColor: colorScheme.onSurface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: _tealSeed,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _tealSeed,
        side: BorderSide(color: outlineColor, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _tealSeed,
      foregroundColor: Colors.white,
    ),
  );
}

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({super.key});

  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  ThemeMode _themeMode = ThemeMode.system;
  double _targetPercentage = 75;
  bool _loaded = false;
  bool _backupSetupDone = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final mode = await _Store.loadThemeMode();
    final target = await _Store.loadTargetPercentage();
    final setupDone = await _Store.loadBackupSetupDone();
    if (!mounted) return;
    setState(() {
      _themeMode = mode;
      _targetPercentage = target;
      _backupSetupDone = setupDone;
      _loaded = true;
    });
  }

  void _setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    _Store.saveThemeMode(mode);
    _syncBackupAfterSettingsChange();
  }

  void _setTargetPercentage(double value) {
    setState(() => _targetPercentage = value);
    _Store.saveTargetPercentage(value);
    _syncBackupAfterSettingsChange();
  }

  /// Re-writes the backup JSON whenever a setting (not a subject) changes,
  /// so the file on disk always mirrors the app's current state.
  Future<void> _syncBackupAfterSettingsChange() async {
    final folderPath = await _Store.loadBackupFolderPath();
    if (folderPath == null) return;
    final subjects = await _Store.loadSubjects();
    final json = _BackupFile.buildJson(
      subjects: subjects,
      themeMode: _themeMode,
      targetPercentage: _targetPercentage,
    );
    if (await _BackupFile.write(folderPath, json)) {
      await _Store.saveLastBackupAt(DateTime.now());
    }
  }

  void _completeBackupSetup() {
    setState(() => _backupSetupDone = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return MaterialApp(
      title: 'My Attendance',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: _backupSetupDone
          ? AttendanceHomePage(
              themeMode: _themeMode,
              targetPercentage: _targetPercentage,
              onThemeModeChanged: _setThemeMode,
              onTargetPercentageChanged: _setTargetPercentage,
            )
          : BackupSetupPage(
              onThemeModeChanged: _setThemeMode,
              onTargetPercentageChanged: _setTargetPercentage,
              onDone: _completeBackupSetup,
            ),
    );
  }
}

/// Shown on first launch (before the app has a backup folder set up).
/// Lets the user pick a specific folder for the auto-updating backup
/// file, and offers to import an existing backup if one is found there.
class BackupSetupPage extends StatefulWidget {
  const BackupSetupPage({
    super.key,
    required this.onThemeModeChanged,
    required this.onTargetPercentageChanged,
    required this.onDone,
  });

  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<double> onTargetPercentageChanged;
  final VoidCallback onDone;

  @override
  State<BackupSetupPage> createState() => _BackupSetupPageState();
}

class _BackupSetupPageState extends State<BackupSetupPage> {
  bool _working = false;
  String? _error;

  Future<void> _chooseFolder() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final path = await _pickBackupFolder(dialogTitle: 'Choose a backup folder');
      if (path == null) return; // user cancelled the picker

      await _Store.saveBackupFolderPath(path);
      final existing = await _BackupFile.read(path);

      if (!mounted) return;

      if (existing != null) {
        final subjectCount = (existing['subjects'] as List?)?.length ?? 0;
        final wantsImport = await showChoiceDialog(
          context: context,
          icon: Icons.history_rounded,
          iconColor: const Color(0xFFD97706),
          title: 'Backup Found',
          message: 'This folder already has a backup with $subjectCount '
              'subject(s). Import it, or start fresh and overwrite it?',
          confirmLabel: 'Import',
          cancelLabel: 'Start fresh',
          barrierDismissible: false,
        );
        if (!mounted) return;
        if (wantsImport == true) {
          final parsed = _BackupFile.parse(existing);
          await _Store.saveSubjects(parsed.subjects);
          widget.onThemeModeChanged(parsed.themeMode);
          widget.onTargetPercentageChanged(parsed.targetPercentage);
        } else {
          await _BackupFile.write(
            path,
            _BackupFile.buildJson(subjects: const [], themeMode: ThemeMode.system, targetPercentage: 75),
          );
        }
      } else {
        await _BackupFile.write(
          path,
          _BackupFile.buildJson(subjects: const [], themeMode: ThemeMode.system, targetPercentage: 75),
        );
      }

      await _Store.saveBackupSetupDone(true);
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't access that folder. Please try a different one.");
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _skip() async {
    await _Store.saveBackupSetupDone(true);
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [_tealSeed.withValues(alpha: 0.85), _tealSeed],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(color: _tealSeed.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 12)),
                  ],
                ),
                child: const Icon(Icons.folder_special_outlined, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 28),
              Text(
                'Choose a backup folder',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Pick a single folder on your device — not full storage access. '
                'My Attendance will keep a JSON backup there and update it '
                'automatically whenever your subjects or settings change.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: Colors.red),
                ),
              ],
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _working ? null : _chooseFolder,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _working
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text(_working ? 'Waiting for folder…' : 'Choose folder'),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _working ? null : _skip,
                child: Text(
                  'Skip for now',
                  style: TextStyle(color: colorScheme.onSurface.withValues(alpha: 0.55)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single subject and its attendance counters.
class Subject {
  Subject({
    required this.name,
    this.attended = 0,
    this.total = 0,
    List<AttendanceRecord>? history,
    List<int>? scheduledDays,
  })  : history = history ?? [],
        scheduledDays = scheduledDays ?? [];

  String name;
  int attended;
  int total;
  List<AttendanceRecord> history;

  /// Weekdays this subject meets. 1 = Monday .. 7 = Sunday (DateTime convention).
  /// Empty means "no fixed schedule set".
  List<int> scheduledDays;

  static const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String get scheduleLabel {
    if (scheduledDays.isEmpty) return 'No schedule set';
    final sorted = [...scheduledDays]..sort();
    return 'Meets ${sorted.map((d) => weekdayLabels[d - 1]).join(', ')}';
  }

  double get percentage => total == 0 ? 0 : (attended / total) * 100;

  /// How many classes in a row you can safely skip / must attend
  /// to reach [target]% (defaults to 75%).
  String projection({double target = 75}) {
    if (total == 0) return 'No classes yet';

    if (percentage >= target) {
      // How many more can be skipped and stay >= target
      int skip = 0;
      while (true) {
        final newTotal = total + skip + 1;
        final newPct = (attended / newTotal) * 100;
        if (newPct < target) break;
        skip++;
        if (skip > 1000) break;
      }
      return skip > 0
          ? 'You can miss $skip more class${skip == 1 ? '' : 'es'} and stay above ${target.toStringAsFixed(0)}%'
          : 'Right at the edge of ${target.toStringAsFixed(0)}%';
    } else {
      int need = 0;
      while (true) {
        need++;
        final newAttended = attended + need;
        final newTotal = total + need;
        final newPct = (newAttended / newTotal) * 100;
        if (newPct >= target) break;
        if (need > 2000) break;
      }
      return 'Attend $need more class${need == 1 ? '' : 'es'} in a row to reach ${target.toStringAsFixed(0)}%';
    }
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'attended': attended,
        'total': total,
        'history': history.map((h) => h.toJson()).toList(),
        'scheduledDays': scheduledDays,
      };

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        name: json['name'] as String,
        attended: json['attended'] as int,
        total: json['total'] as int,
        history: (json['history'] as List)
            .map((e) => AttendanceRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        scheduledDays: (json['scheduledDays'] as List?)
                ?.map((e) => e as int)
                .toList() ??
            [],
      );
}

class AttendanceRecord {
  AttendanceRecord({required this.date, required this.present});
  final DateTime date;
  final bool present;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'present': present,
      };

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) =>
      AttendanceRecord(
        date: DateTime.parse(json['date'] as String),
        present: json['present'] as bool,
      );
}

class AttendanceHomePage extends StatefulWidget {
  const AttendanceHomePage({
    super.key,
    required this.themeMode,
    required this.targetPercentage,
    required this.onThemeModeChanged,
    required this.onTargetPercentageChanged,
  });

  final ThemeMode themeMode;
  final double targetPercentage;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<double> onTargetPercentageChanged;

  @override
  State<AttendanceHomePage> createState() => _AttendanceHomePageState();
}

class _AttendanceHomePageState extends State<AttendanceHomePage>
    with WidgetsBindingObserver {
  final List<Subject> _subjects = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSubjects();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSubjects();
    }
  }

  Future<void> _loadSubjects() async {
    final subjects = await _Store.loadSubjects();
    if (!mounted) return;
    setState(() {
      _subjects
        ..clear()
        ..addAll(subjects);
      _loaded = true;
    });
  }

  void _persist() {
    _Store.saveSubjects(_subjects);
    _syncBackup();
  }

  /// Re-writes the backup JSON to the chosen folder (if any) so it stays
  /// in sync with every subject/attendance change.
  Future<void> _syncBackup() async {
    final folderPath = await _Store.loadBackupFolderPath();
    if (folderPath == null) return;
    final json = _BackupFile.buildJson(
      subjects: _subjects,
      themeMode: widget.themeMode,
      targetPercentage: widget.targetPercentage,
    );
    if (await _BackupFile.write(folderPath, json)) {
      await _Store.saveLastBackupAt(DateTime.now());
    }
  }

  double get _overallPercentage {
    final totalAttended = _subjects.fold<int>(0, (a, s) => a + s.attended);
    final totalClasses = _subjects.fold<int>(0, (a, s) => a + s.total);
    if (totalClasses == 0) return 0;
    return (totalAttended / totalClasses) * 100;
  }

  void _addSubject() async {
    final result = await Navigator.push<_NewSubjectData>(
      context,
      MaterialPageRoute(builder: (context) => const AddSubjectPage()),
    );

    if (result != null && result.name.trim().isNotEmpty) {
      setState(() {
        _subjects.add(Subject(
          name: result.name.trim(),
          scheduledDays: result.scheduledDays,
        ));
      });
      _persist();
    }
  }

  void _markAttendance(Subject subject, bool present, {DateTime? date}) {
    setState(() {
      subject.total += 1;
      if (present) subject.attended += 1;
      subject.history.insert(
        0,
        AttendanceRecord(date: date ?? DateTime.now(), present: present),
      );
      subject.history.sort((a, b) => b.date.compareTo(a.date));
    });
    _persist();
  }

  /// Marks attendance for every subject at once for a given date —
  /// e.g. logging a whole day you forgot, or a holiday.
  void _markAllSubjects(DateTime date, Map<Subject, bool> attendance) {
    setState(() {
      for (final entry in attendance.entries) {
        entry.key.total += 1;
        if (entry.value) entry.key.attended += 1;
        entry.key.history.insert(
          0,
          AttendanceRecord(date: date, present: entry.value),
        );
        entry.key.history.sort((a, b) => b.date.compareTo(a.date));
      }
    });
    _persist();
  }

  void _undoLast(Subject subject) {
    if (subject.history.isEmpty) return;
    setState(() {
      final last = subject.history.removeAt(0);
      subject.total -= 1;
      if (last.present) subject.attended -= 1;
    });
    _persist();
  }

  void _deleteSubject(Subject subject) {
    setState(() => _subjects.remove(subject));
    _persist();
  }

  void _renameSubject(Subject subject) async {
    final result = await Navigator.push<_NewSubjectData>(
      context,
      MaterialPageRoute(builder: (context) => AddSubjectPage(subject: subject)),
    );
    if (result != null) {
      setState(() {
        subject.name = result.name;
        subject.scheduledDays = result.scheduledDays;
      });
      _persist();
    }
  }

  /// Opens a dialog to log attendance for every subject on a chosen date
  /// in one go — for backfilling a missed day or marking a holiday.
  void _bulkMarkDay() async {
    if (_subjects.isEmpty) return;
    DateTime selectedDate = DateTime.now();
    final Map<Subject, bool?> choices = {for (final s in _subjects) s: null};

    final confirmed = await showFunDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            actionsPadding: const EdgeInsets.fromLTRB(16, 4, 20, 16),
            title: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _tealSeed.withValues(alpha: theme.brightness == Brightness.dark ? 0.2 : 0.12),
                  ),
                  child: Icon(Icons.event_note_rounded, size: 18, color: _tealSeed),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Mark a Day', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DatePickerField(
                      date: selectedDate,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    ..._subjects.map((s) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _PAChip(
                                label: 'P',
                                compact: true,
                                selected: choices[s] == true,
                                color: const Color(0xFF22C55E),
                                onTap: () => setDialogState(() => choices[s] = true),
                              ),
                              const SizedBox(width: 8),
                              _PAChip(
                                label: 'A',
                                compact: true,
                                selected: choices[s] == false,
                                color: const Color(0xFFEF4444),
                                onTap: () => setDialogState(() => choices[s] = false),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: _tealSeed,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      final attendance = <Subject, bool>{
        for (final entry in choices.entries)
          if (entry.value != null) entry.key: entry.value!,
      };
      if (attendance.isNotEmpty) {
        _markAllSubjects(selectedDate, attendance);
      }
    }
  }

  void _openSubjectDetail(Subject subject) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SubjectDetailPage(
          subject: subject,
          targetPercentage: widget.targetPercentage,
          onMark: (present) => _markAttendance(subject, present),
          onMarkDated: (present, date) =>
              _markAttendance(subject, present, date: date),
          onUndo: () => _undoLast(subject),
        ),
      ),
    ).then((_) => setState(() {}));
  }

  Color _colorForPercentage(double pct) {
    if (pct >= widget.targetPercentage) return Colors.green;
    if (pct >= widget.targetPercentage - 15) return Colors.orange;
    return Colors.red;
  }

  void _resetAllData() {
    setState(() => _subjects.clear());
    _persist();
  }

  void _importSubjects(List<Subject> subjects) {
    setState(() {
      _subjects
        ..clear()
        ..addAll(subjects);
    });
    _persist();
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(
          themeMode: widget.themeMode,
          targetPercentage: widget.targetPercentage,
          onThemeModeChanged: widget.onThemeModeChanged,
          onTargetPercentageChanged: widget.onTargetPercentageChanged,
          onResetAllData: _resetAllData,
          subjects: _subjects,
          onImportData: _importSubjects,
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _todayLabel() {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
    ];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final now = DateTime.now();
    return '${weekdays[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting().toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: _tealSeed,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'My Attendance',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _todayLabel(),
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _HeaderIconButton(icon: Icons.school_rounded, decorative: true),
          const SizedBox(width: 8),
          _HeaderIconButton(
            icon: Icons.event_available_outlined,
            tooltip: 'Mark a day',
            onPressed: _subjects.isEmpty ? null : _bulkMarkDay,
          ),
          const SizedBox(width: 8),
          _HeaderIconButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : _subjects.isEmpty
                  ? _EmptyState(onAdd: _addSubject)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      children: [
                        _OverallCard(
                          percentage: _overallPercentage,
                          subjectCount: _subjects.length,
                          color: _colorForPercentage(_overallPercentage),
                        ),
                        const SizedBox(height: 16),
                        ..._subjects.map(
                          (s) => Dismissible(
                    key: ValueKey(s),
                    direction: DismissDirection.horizontal,
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.edit, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Edit', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    secondaryBackground: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          SizedBox(width: 8),
                          Icon(Icons.delete, color: Colors.white),
                        ],
                      ),
                    ),
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.startToEnd) {
                        // Swipe right -> edit, never actually dismiss the card.
                        _renameSubject(s);
                        return false;
                      } else {
                        // Swipe left -> delete, ask for confirmation first.
                        final confirmed = await showFunDialog<bool>(
                          context: context,
                          builder: (dialogContext) {
                            final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
                            final colorScheme = Theme.of(dialogContext).colorScheme;
                            return Dialog(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                              backgroundColor: isDark ? const Color(0xFF1C1F2A) : Colors.white,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.delete_rounded, color: Colors.red, size: 28),
                                    ),
                                    const SizedBox(height: 18),
                                    Text(
                                      'Delete Subject?',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurface,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // Subject preview pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF252836) : const Color(0xFFF4F5FA),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 18,
                                            backgroundColor: _colorForPercentage(s.percentage).withValues(alpha: 0.15),
                                            child: Icon(Icons.menu_book_rounded, color: _colorForPercentage(s.percentage), size: 16),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  s.name,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: colorScheme.onSurface,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                Text(
                                                  '${s.attended}/${s.total} classes • ${s.percentage.toStringAsFixed(1)}%',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'This action cannot be undone.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                                      ),
                                    ),
                                    const SizedBox(height: 22),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: () => Navigator.pop(dialogContext, false),
                                            style: OutlinedButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(vertical: 13),
                                              side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                            child: Text(
                                              'Cancel',
                                              style: TextStyle(
                                                color: colorScheme.onSurface.withValues(alpha: 0.75),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: () => Navigator.pop(dialogContext, true),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              padding: const EdgeInsets.symmetric(vertical: 13),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            ),
                                            child: const Text(
                                              'Delete',
                                              style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                        return confirmed ?? false;
                      }
                    },
                    onDismissed: (direction) => _deleteSubject(s),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      child: _SubjectCard(
                        subject: s,
                        color: _colorForPercentage(s.percentage),
                        onTap: () => _openSubjectDetail(s),
                        onPresent: () => _markAttendance(s, true),
                        onAbsent: () => _markAttendance(s, false),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSubject,
        icon: const Icon(Icons.add),
        label: const Text('Add Subject'),
      ),
    );
  }
}

/// A rounded-square icon button used in the home header, matching the
/// look of the decorative school-icon badge next to it. When
/// [decorative] is true it renders as a static, non-interactive badge.
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.decorative = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool decorative;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final disabled = !decorative && onPressed == null;
    final content = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: _tealSeed.withValues(alpha: disabled ? (isDark ? 0.05 : 0.04) : (isDark ? 0.16 : 0.12)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        icon,
        color: disabled ? _tealSeed.withValues(alpha: 0.35) : _tealSeed,
        size: 22,
      ),
    );

    if (decorative) return content;

    final button = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: content,
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.school_outlined,
              size: 72, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text(
            'No subjects yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Add your first subject to start tracking attendance.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Subject'),
          ),
        ],
      ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({
    required this.percentage,
    required this.subjectCount,
    required this.color,
  });

  final double percentage;
  final int subjectCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      color: _tealSeed.withValues(alpha: isDark ? 0.14 : 0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _tealSeed.withValues(alpha: isDark ? 0.35 : 0.25), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              height: 70,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: percentage / 100,
                    strokeWidth: 6,
                    backgroundColor: scheme.outline.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                  Center(
                    child: Text(
                      '${percentage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Overall Attendance',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  Text('$subjectCount subject${subjectCount == 1 ? '' : 's'} tracked'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({
    required this.subject,
    required this.color,
    required this.onTap,
    required this.onPresent,
    required this.onAbsent,
  });

  final Subject subject;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onPresent;
  final VoidCallback onAbsent;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: _tealSeed.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${subject.attended}/${subject.total} classes attended',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        Text(
                          subject.scheduleLabel,
                          style: TextStyle(
                            color: Colors.grey.withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${subject.percentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (subject.percentage / 100).clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: Colors.grey.withValues(alpha: 0.2),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPresent,
                      icon: const Icon(Icons.check, size: 18, color: Colors.green),
                      label: const Text('Present'),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.center,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onAbsent,
                      icon: const Icon(Icons.close, size: 18, color: Colors.red),
                      label: const Text('Absent'),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.center,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The result handed back from [AddSubjectPage] when the user saves.
class _NewSubjectData {
  _NewSubjectData({required this.name, required this.scheduledDays});
  final String name;
  final List<int> scheduledDays;
}

/// A dedicated full-screen form for creating OR editing a subject. Pops
/// itself with the entered data as soon as the user taps Save — the caller
/// is responsible for actually applying it (adding a new subject, or
/// updating an existing one).
///
/// Pass [subject] to open this in edit mode: the form is pre-filled with
/// the subject's current name and schedule, and the title/button read
/// "Edit Subject" instead of "Add Subject".
class AddSubjectPage extends StatefulWidget {
  const AddSubjectPage({super.key, this.subject});

  final Subject? subject;

  @override
  State<AddSubjectPage> createState() => _AddSubjectPageState();
}

class _AddSubjectPageState extends State<AddSubjectPage> {
  late final _controller = TextEditingController(text: widget.subject?.name ?? '');
  late final Set<int> _selectedDays = {...?widget.subject?.scheduledDays};

  bool get _isEditing => widget.subject != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(
      context,
      _NewSubjectData(name: name, scheduledDays: _selectedDays.toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Subject' : 'Add Subject')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Subject name', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'e.g. Data Structures',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 24),
              const Text('Meets on (optional)', style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(7, (i) {
                  final day = i + 1;
                  final label = Subject.weekdayLabels[i];
                  final selected = _selectedDays.contains(day);
                  return FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _selectedDays.add(day);
                      } else {
                        _selectedDays.remove(day);
                      }
                    }),
                  );
                }),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_isEditing ? 'Save Changes' : 'Add Subject'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SubjectDetailPage extends StatefulWidget {
  const SubjectDetailPage({
    super.key,
    required this.subject,
    required this.targetPercentage,
    required this.onMark,
    required this.onMarkDated,
    required this.onUndo,
  });

  final Subject subject;
  final double targetPercentage;
  final void Function(bool present) onMark;
  final void Function(bool present, DateTime date) onMarkDated;
  final VoidCallback onUndo;

  @override
  State<SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends State<SubjectDetailPage> {
  void _logPastClass(BuildContext context) async {
    DateTime selectedDate = DateTime.now();
    bool present = true;
    final confirmed = await showFunDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
            actionsPadding: const EdgeInsets.fromLTRB(16, 4, 20, 16),
            title: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _tealSeed.withValues(alpha: theme.brightness == Brightness.dark ? 0.2 : 0.12),
                  ),
                  child: Icon(Icons.history_rounded, size: 18, color: _tealSeed),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Log a Past Class', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DatePickerField(
                  date: selectedDate,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _PAChip(
                        label: 'Present',
                        icon: Icons.check_rounded,
                        selected: present,
                        color: const Color(0xFF22C55E),
                        onTap: () => setDialogState(() => present = true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PAChip(
                        label: 'Absent',
                        icon: Icons.close_rounded,
                        selected: !present,
                        color: const Color(0xFFEF4444),
                        onTap: () => setDialogState(() => present = false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: _tealSeed,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed == true) {
      widget.onMarkDated(present, selectedDate);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final subject = widget.subject;
    final theme = Theme.of(context);
    final onTrack = subject.percentage >= widget.targetPercentage || subject.total == 0;
    final accent = onTrack ? const Color(0xFF22C55E) : const Color(0xFFF59A3C);

    return Scaffold(
      appBar: AppBar(
        title: Text(subject.name),
        bottom: subject.scheduledDays.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(30),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    subject.scheduleLabel,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          _AttendanceRingCard(
            percentage: subject.percentage,
            attended: subject.attended,
            total: subject.total,
            accent: accent,
            projection: subject.projection(target: widget.targetPercentage),
            onTrack: onTrack,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _MarkButton(
                  label: 'Present',
                  icon: Icons.check_rounded,
                  color: const Color(0xFF22C55E),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    widget.onMark(true);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MarkButton(
                  label: 'Absent',
                  icon: Icons.close_rounded,
                  color: const Color(0xFFEF4444),
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    widget.onMark(false);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _GhostAction(
                icon: Icons.undo_rounded,
                label: 'Undo',
                onTap: subject.history.isEmpty
                    ? null
                    : () {
                        widget.onUndo();
                        setState(() {});
                      },
              ),
              const SizedBox(width: 8),
              _GhostAction(
                icon: Icons.history_rounded,
                label: 'Log past class',
                onTap: () => _logPastClass(context),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Text(
                'History',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17, color: theme.colorScheme.onSurface),
              ),
              const SizedBox(width: 8),
              if (subject.history.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${subject.history.length}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (subject.history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 40, color: theme.colorScheme.onSurface.withValues(alpha: 0.25)),
                    const SizedBox(height: 8),
                    Text('No records yet', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                  ],
                ),
              ),
            )
          else
            ...subject.history.map((r) => _HistoryRow(record: r)),
        ],
      ),
    );
  }
}

class _AttendanceRingCard extends StatelessWidget {
  const _AttendanceRingCard({
    required this.percentage,
    required this.attended,
    required this.total,
    required this.accent,
    required this.projection,
    required this.onTrack,
  });

  final double percentage;
  final int attended;
  final int total;
  final Color accent;
  final String projection;
  final bool onTrack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        color: _tealSeed.withValues(alpha: isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _tealSeed.withValues(alpha: isDark ? 0.3 : 0.2), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 104,
                height: 104,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: (percentage / 100).clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => SizedBox(
                        width: 104,
                        height: 104,
                        child: CircularProgressIndicator(
                          value: value == 0 ? 0.001 : value,
                          strokeWidth: 11,
                          strokeCap: StrokeCap.round,
                          backgroundColor: accent.withValues(alpha: isDark ? 0.16 : 0.14),
                          valueColor: AlwaysStoppedAnimation(accent),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${percentage.toStringAsFixed(0)}%',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                        ),
                        Text(
                          'attendance',
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$attended / $total',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'classes attended',
                      style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(onTrack ? Icons.auto_awesome_rounded : Icons.warning_amber_rounded, size: 18, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    projection,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkButton extends StatelessWidget {
  const _MarkButton({required this.label, required this.icon, required this.color, required this.onTap});

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: color.withValues(alpha: isDark ? 0.18 : 0.1),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.35), width: 1.2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 8),
              Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GhostAction extends StatelessWidget {
  const _GhostAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onTap == null;
    final color = disabled ? theme.colorScheme.onSurface.withValues(alpha: 0.35) : theme.colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: disabled ? theme.dividerColor : color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = record.present ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final weekday = Subject.weekdayLabels[record.date.weekday - 1];
    final time =
        '${record.date.hour.toString().padLeft(2, '0')}:${record.date.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: theme.brightness == Brightness.dark ? 0.04 : 0.035),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.15)),
            child: Icon(record.present ? Icons.check_rounded : Icons.close_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.present ? 'Present' : 'Absent',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  '$weekday, ${record.date.day}/${record.date.month}/${record.date.year} • $time',
                  style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurface.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.themeMode,
    required this.targetPercentage,
    required this.onThemeModeChanged,
    required this.onTargetPercentageChanged,
    required this.onResetAllData,
    required this.subjects,
    required this.onImportData,
  });

  final ThemeMode themeMode;
  final double targetPercentage;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ValueChanged<double> onTargetPercentageChanged;
  final VoidCallback onResetAllData;
  final List<Subject> subjects;
  final void Function(List<Subject> subjects) onImportData;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late double _targetPercentage = widget.targetPercentage;
  String? _backupFolderPath;
  DateTime? _lastBackupAt;
  bool _backupBusy = false;
  bool _backupAccessStale = false;

  @override
  void initState() {
    super.initState();
    _loadBackupInfo();
  }

  Future<void> _loadBackupInfo() async {
    final path = await _Store.loadBackupFolderPath();
    final lastAt = await _Store.loadLastBackupAt();
    final stale = path != null && !await _BackupFile.hasValidAccess(path);
    if (!mounted) return;
    setState(() {
      _backupFolderPath = path;
      _lastBackupAt = lastAt;
      _backupAccessStale = stale;
    });
  }

  String get _backupFolderLabel {
    final path = _backupFolderPath;
    if (path == null) return 'Not set';
    return _BackupFile.displayLabel(path);
  }

  String get _lastBackupLabel {
    final at = _lastBackupAt;
    if (at == null) return 'Never backed up yet';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Backed up just now';
    if (diff.inMinutes < 60) return 'Backed up ${diff.inMinutes}m ago';
    if (diff.inHours < 24) return 'Backed up ${diff.inHours}h ago';
    return 'Backed up ${diff.inDays}d ago';
  }

  Future<void> _chooseOrChangeBackupFolder() async {
    final isChange = _backupFolderPath != null;
    setState(() => _backupBusy = true);
    try {
      final path = await _pickBackupFolder(
        dialogTitle: isChange ? 'Choose a new backup folder' : 'Choose a backup folder',
      );
      if (path == null) return;

      final existing = await _BackupFile.read(path);
      if (!mounted) return;

      if (existing != null) {
        final subjectCount = (existing['subjects'] as List?)?.length ?? 0;
        final wantsImport = await showChoiceDialog(
          context: context,
          icon: Icons.history_rounded,
          iconColor: const Color(0xFFD97706),
          title: 'Backup Found',
          message: 'This folder already has a backup with $subjectCount '
              'subject(s). Import it, or keep your current data and overwrite it?',
          confirmLabel: 'Import',
          cancelLabel: 'Keep current',
        );
        if (!mounted) return;
        if (wantsImport == true) {
          final parsed = _BackupFile.parse(existing);
          widget.onImportData(parsed.subjects);
          widget.onThemeModeChanged(parsed.themeMode);
          widget.onTargetPercentageChanged(parsed.targetPercentage);
          setState(() => _targetPercentage = parsed.targetPercentage);
        }
      }

      await _Store.saveBackupFolderPath(path);
      await _Store.saveBackupSetupDone(true);
      await _backupNow(showFeedback: false);
      if (mounted) {
        setState(() {
          _backupFolderPath = path;
          _backupAccessStale = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup folder set')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't access that folder")),
        );
      }
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _backupNow({bool showFeedback = true}) async {
    final folderPath = _backupFolderPath;
    if (folderPath == null) return;
    if (showFeedback) setState(() => _backupBusy = true);
    final json = _BackupFile.buildJson(
      subjects: widget.subjects,
      themeMode: widget.themeMode,
      targetPercentage: _targetPercentage,
    );
    final success = await _BackupFile.write(folderPath, json);
    if (success) await _Store.saveLastBackupAt(DateTime.now());
    if (!mounted) return;
    if (showFeedback) {
      setState(() {
        _backupBusy = false;
        if (success) _lastBackupAt = DateTime.now();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Backup saved' : "Couldn't write to that folder")),
      );
    } else if (success) {
      setState(() => _lastBackupAt = DateTime.now());
    }
  }

  Future<void> _restoreFromBackup() async {
    final folderPath = _backupFolderPath;
    if (folderPath == null) return;
    final data = await _BackupFile.read(folderPath);
    if (!mounted) return;
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No backup file found in that folder')),
      );
      return;
    }
    final parsed = _BackupFile.parse(data);
    final confirmed = await showChoiceDialog(
      context: context,
      icon: Icons.restore_rounded,
      iconColor: const Color(0xFFD97706),
      title: 'Restore backup?',
      message: 'This will replace your current ${widget.subjects.length} '
          'subject(s) with ${parsed.subjects.length} from the backup file. '
          'This cannot be undone.',
      confirmLabel: 'Restore',
      cancelLabel: 'Cancel',
      destructive: true,
    );
    if (confirmed != true) return;
    widget.onImportData(parsed.subjects);
    widget.onThemeModeChanged(parsed.themeMode);
    widget.onTargetPercentageChanged(parsed.targetPercentage);
    setState(() => _targetPercentage = parsed.targetPercentage);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored')),
      );
    }
  }

  void _showAboutDialog() {
    showFunDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return _FunDialogCard(
          icon: Icons.school_outlined,
          iconColors: const [Color(0xFF2DD4BF), Color(0xFF0D9488)],
          title: 'My Attendance',
          actionLabel: 'Nice',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(
                  child: Text(
                    'Version 1.0.0',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'My Attendance helps you track class attendance, stay above your target percentage, and see how many classes you can safely miss or need to attend.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: colorScheme.onSurface.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: 18),
                Text(
                  'Contact',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.3,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: 'Hetbuilds27@gmail.com'));
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Email copied to clipboard')),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.email_outlined, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Hetbuilds27@gmail.com',
                            style: TextStyle(fontSize: 13.5),
                          ),
                        ),
                        Icon(Icons.copy, size: 15, color: colorScheme.onSurface.withValues(alpha: 0.4)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showHowToUseDialog() {
    showFunDialog<void>(
      context: context,
      builder: (dialogContext) {
        final colorScheme = Theme.of(dialogContext).colorScheme;
        const steps = [
          (
            Icons.add_circle_outline,
            'Add a subject',
            'Tap the + button on the home screen and enter a subject name to start tracking it.',
          ),
          (
            Icons.check_circle_outline,
            'Mark attendance',
            'For each class, mark yourself present or absent. Your attended and total class counts update automatically.',
          ),
          (
            Icons.calendar_today_outlined,
            'Set a schedule',
            'Choose which weekdays a subject meets so the app knows when classes are expected.',
          ),
          (
            Icons.percent_outlined,
            'Set your target',
            'Go to Settings > Attendance Goal and set the minimum percentage you need to maintain.',
          ),
          (
            Icons.insights_outlined,
            'Check your projection',
            'Each subject shows how many classes you can safely skip, or must attend, to hit your target.',
          ),
          (
            Icons.backup_outlined,
            'Back up your data',
            'Use Export data in Settings to copy a backup, and Import data to restore it later.',
          ),
        ];
        return _FunDialogCard(
          icon: Icons.auto_awesome,
          iconColors: const [Color(0xFF818CF8), Color(0xFF4F46E5)],
          title: 'How to Use',
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(steps[i].$1, size: 16, color: colorScheme.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                steps[i].$2,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                steps[i].$3,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: colorScheme.onSurface.withValues(alpha: 0.65),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmReset() async {
    final confirmed = await showFunDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final colorScheme = Theme.of(dialogContext).colorScheme;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDark ? const Color(0xFF1C1F2A) : Colors.white,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_rounded, color: Colors.red, size: 28),
                ),
                const SizedBox(height: 18),
                Text(
                  'Reset All Data?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'This will permanently delete every subject and all attendance history. This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(
                          'Reset',
                          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      widget.onResetAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All data has been reset')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SettingsSection(
            title: 'Appearance',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Theme'),
                subtitle: Text(switch (widget.themeMode) {
                  ThemeMode.system => 'Follow system',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                }),
              ),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.brightness_auto, size: 18),
                      label: Text('Auto'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode, size: 18),
                      label: Text('Light'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode, size: 18),
                      label: Text('Dark'),
                    ),
                  ],
                  selected: {widget.themeMode},
                  onSelectionChanged: (selection) =>
                      widget.onThemeModeChanged(selection.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SettingsSection(
            title: 'Attendance Goal',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Target attendance'),
              ),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _targetPercentage,
                      min: 50,
                      max: 100,
                      divisions: 50,
                      label: '${_targetPercentage.toStringAsFixed(0)}%',
                      onChanged: (v) => setState(() => _targetPercentage = v),
                      onChangeEnd: widget.onTargetPercentageChanged,
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${_targetPercentage.toStringAsFixed(0)}%',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SettingsSection(
            title: 'Backup',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _backupAccessStale ? Icons.folder_off_outlined : Icons.folder_outlined,
                  color: _backupAccessStale ? Colors.orange : Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Backup folder'),
                subtitle: Text(_backupFolderPath == null
                    ? 'Not set — tap to choose a folder'
                    : _backupAccessStale
                        ? 'Access lost — tap to reconnect "$_backupFolderLabel"'
                        : _backupFolderLabel),
                trailing: _backupBusy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chevron_right, size: 20),
                onTap: _backupBusy ? null : _chooseOrChangeBackupFolder,
              ),
              if (_backupFolderPath != null && !_backupAccessStale) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Back up now'),
                  subtitle: Text(_lastBackupLabel),
                  onTap: _backupBusy ? null : () => _backupNow(),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restore_outlined),
                  title: const Text('Restore from backup'),
                  subtitle: const Text('Replace current data with the file in your backup folder'),
                  onTap: _restoreFromBackup,
                ),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Reset all data', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Delete all subjects and attendance history'),
                onTap: _confirmReset,
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SettingsSection(
            title: 'About',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.help_outline),
                title: const Text('How to use'),
                subtitle: const Text('Learn how to get the most out of the app'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: _showHowToUseDialog,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.school_outlined),
                title: const Text('My Attendance'),
                subtitle: const Text('Version 1.0.0 • Track your college attendance'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: _showAboutDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.3,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}