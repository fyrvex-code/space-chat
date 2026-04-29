import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SpacePalette {
  static const Color darkBg = Color(0xFF050816);
  static const Color darkBg2 = Color(0xFF0E1730);
  static const Color darkCard = Color(0xCC121A31);
  static const Color darkCardStrong = Color(0xFF141E3A);
  static const Color darkStroke = Color(0x22FFFFFF);
  static const Color darkText = Color(0xFFF8FBFF);
  static const Color darkSub = Color(0xFF9FB0D6);

  static const Color lightBg = Color(0xFFF7FAFF);
  static const Color lightBg2 = Color(0xFFDCE7FF);
  static const Color lightCard = Color(0xF5FFFFFF);
  static const Color lightCardStrong = Color(0xFFFFFFFF);
  static const Color lightStroke = Color(0x150F1729);
  static const Color lightText = Color(0xFF0B1220);
  static const Color lightSub = Color(0xFF64748B);

  static const Color cyan = Color(0xFF57E8FF);
  static const Color indigo = Color(0xFF7C78FF);
  static const Color violet = Color(0xFFBC7BFF);
  static const Color emerald = Color(0xFF4FF5B3);
  static const Color red = Color(0xFFFF6B85);
  static const Color yellow = Color(0xFFFFCE58);

  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color text(BuildContext context) => isDark(context) ? darkText : lightText;
  static Color sub(BuildContext context) => isDark(context) ? darkSub : lightSub;
  static Color card(BuildContext context) => isDark(context) ? darkCard : lightCard;
  static Color cardStrong(BuildContext context) => isDark(context) ? darkCardStrong : lightCardStrong;
  static Color stroke(BuildContext context) => isDark(context) ? darkStroke : lightStroke;
}

class SpaceTheme {
  static ThemeData light(double messageScale) => _build(Brightness.light, messageScale);
  static ThemeData dark(double messageScale) => _build(Brightness.dark, messageScale);

  static ThemeData _build(Brightness brightness, double messageScale) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Roboto',
    );
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: SpacePalette.indigo,
      brightness: brightness,
      primary: dark ? SpacePalette.cyan : const Color(0xFF365DFF),
      secondary: dark ? SpacePalette.violet : const Color(0xFF7C78FF),
      surface: dark ? SpacePalette.darkCardStrong : Colors.white,
    );

    TextStyle scale(TextStyle? style) {
      final current = style ?? const TextStyle(fontSize: 14);
      return current.copyWith(
        color: dark ? SpacePalette.darkText : SpacePalette.lightText,
        fontSize: (current.fontSize ?? 14) * messageScale,
      );
    }

    final textTheme = base.textTheme.copyWith(
      displayLarge: scale(base.textTheme.displayLarge),
      displayMedium: scale(base.textTheme.displayMedium),
      displaySmall: scale(base.textTheme.displaySmall),
      headlineLarge: scale(base.textTheme.headlineLarge),
      headlineMedium: scale(base.textTheme.headlineMedium),
      headlineSmall: scale(base.textTheme.headlineSmall),
      titleLarge: scale(base.textTheme.titleLarge),
      titleMedium: scale(base.textTheme.titleMedium),
      titleSmall: scale(base.textTheme.titleSmall),
      bodyLarge: scale(base.textTheme.bodyLarge),
      bodyMedium: scale(base.textTheme.bodyMedium),
      bodySmall: scale(base.textTheme.bodySmall),
      labelLarge: scale(base.textTheme.labelLarge),
      labelMedium: scale(base.textTheme.labelMedium),
      labelSmall: scale(base.textTheme.labelSmall),
    );

    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: dark ? SpacePalette.darkStroke : SpacePalette.lightStroke),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: dark ? Colors.white : SpacePalette.lightText,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.8),
        hintStyle: TextStyle(color: dark ? SpacePalette.darkSub : SpacePalette.lightSub),
        labelStyle: TextStyle(color: dark ? SpacePalette.darkSub : SpacePalette.lightSub),
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: dark ? SpacePalette.cyan : scheme.primary, width: 1.4),
        ),
        errorBorder: border.copyWith(
          borderSide: const BorderSide(color: SpacePalette.red, width: 1.1),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: const BorderSide(color: SpacePalette.red, width: 1.4),
        ),
        border: border,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF0F1730) : Colors.white,
        contentTextStyle: TextStyle(color: dark ? Colors.white : SpacePalette.lightText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dividerColor: dark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
      iconTheme: IconThemeData(color: dark ? Colors.white : SpacePalette.lightText),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
    );
  }
}

class SpaceLocalPrefs {
  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.dark);
  static final ValueNotifier<double> messageScaleNotifier = ValueNotifier(1.0);
  static final ValueNotifier<bool> notificationsEnabledNotifier = ValueNotifier(true);

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    themeModeNotifier.value = (_prefs?.getBool('space_theme_dark') ?? true) ? ThemeMode.dark : ThemeMode.light;
    messageScaleNotifier.value = _prefs?.getDouble('space_message_scale') ?? 1.0;
    notificationsEnabledNotifier.value = _prefs?.getBool('space_notifications_enabled') ?? true;
  }

  static Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    await _prefs?.setBool('space_theme_dark', mode == ThemeMode.dark);
  }

  static Future<void> setMessageScale(double value) async {
    messageScaleNotifier.value = value;
    await _prefs?.setDouble('space_message_scale', value);
  }

  static Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabledNotifier.value = value;
    await _prefs?.setBool('space_notifications_enabled', value);
  }

  static Future<int> cacheSizeBytes() async {
    try {
      final dir = await getTemporaryDirectory();
      if (!dir.existsSync()) return 0;
      var sum = 0;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File) {
          sum += await entity.length();
        }
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearCache() async {
    try {
      final dir = await getTemporaryDirectory();
      if (dir.existsSync()) {
        for (final entity in dir.listSync(recursive: false)) {
          await entity.delete(recursive: true);
        }
      }
    } catch (_) {}
  }


  static const String _favoriteChatsKey = 'space_favorite_chats';
  static const String _archivedChatsKey = 'space_archived_chats';
  static const String _mutedChatsKey = 'space_muted_chats';
  static const String _draftPrefix = 'space_draft_';

  static Set<String> _readStringSet(String key) {
    final values = _prefs?.getStringList(key) ?? const <String>[];
    return values.toSet();
  }

  static Future<void> _writeStringSet(String key, Set<String> values) async {
    final sorted = values.toList()..sort();
    await _prefs?.setStringList(key, sorted);
  }

  static Future<Set<String>> favoriteChats() async => _readStringSet(_favoriteChatsKey);

  static Future<Set<String>> archivedChats() async => _readStringSet(_archivedChatsKey);

  static Future<Set<String>> mutedChats() async => _readStringSet(_mutedChatsKey);

  static String draftFor(String conversationId) {
    return _prefs?.getString('$_draftPrefix$conversationId') ?? '';
  }

  static Future<void> setDraft(String conversationId, String text) async {
    await _prefs?.setString('$_draftPrefix$conversationId', text);
  }

  static Future<void> clearDraft(String conversationId) async {
    await _prefs?.remove('$_draftPrefix$conversationId');
  }

  static Future<void> toggleFavoriteChat(String conversationId) async {
    final values = _readStringSet(_favoriteChatsKey);
    if (values.contains(conversationId)) {
      values.remove(conversationId);
    } else {
      values.add(conversationId);
    }
    await _writeStringSet(_favoriteChatsKey, values);
  }

  static Future<void> toggleArchivedChat(String conversationId) async {
    final values = _readStringSet(_archivedChatsKey);
    if (values.contains(conversationId)) {
      values.remove(conversationId);
    } else {
      values.add(conversationId);
    }
    await _writeStringSet(_archivedChatsKey, values);
  }

  static Future<void> toggleMutedChat(String conversationId) async {
    final values = _readStringSet(_mutedChatsKey);
    if (values.contains(conversationId)) {
      values.remove(conversationId);
    } else {
      values.add(conversationId);
    }
    await _writeStringSet(_mutedChatsKey, values);
  }

}

void showSpaceSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class SpaceScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  const SpaceScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: NebulaBackground()),
        Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          appBar: appBar,
          body: body,
          bottomNavigationBar: bottomNavigationBar,
          floatingActionButton: floatingActionButton,
        ),
      ],
    );
  }
}

class NebulaBackground extends StatelessWidget {
  const NebulaBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = SpacePalette.isDark(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [SpacePalette.darkBg, SpacePalette.darkBg2, Color(0xFF070C1D)]
              : const [SpacePalette.lightBg, SpacePalette.lightBg2, Color(0xFFF6FBFF)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _Orb(top: -110, left: -60, size: 240, color: SpacePalette.indigo),
          const _Orb(top: 90, right: -40, size: 220, color: SpacePalette.cyan),
          const _Orb(bottom: -80, left: 30, size: 210, color: SpacePalette.violet),
          const _Orb(bottom: 100, right: 20, size: 150, color: SpacePalette.emerald),
          IgnorePointer(
            child: CustomPaint(
              painter: _StarsPainter(dark: dark),
            ),
          ),
        ],
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  final double? top;
  final double? right;
  final double? bottom;
  final double? left;
  final double size;
  final Color color;

  const _Orb({
    this.top,
    this.right,
    this.bottom,
    this.left,
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withOpacity(0.25), color.withOpacity(0.02), Colors.transparent],
            ),
          ),
        ),
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  final bool dark;

  const _StarsPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(7);
    final starPaint = Paint()..color = (dark ? Colors.white : Colors.black).withOpacity(dark ? 0.18 : 0.08);
    for (var i = 0; i < 90; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final r = random.nextDouble() * 1.4 + 0.4;
      canvas.drawCircle(Offset(x, y), r, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double blur;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blur = 18,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: SpacePalette.card(context),
            borderRadius: borderRadius,
            border: Border.all(color: SpacePalette.stroke(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(SpacePalette.isDark(context) ? 0.2 : 0.05),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class SpacePrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Widget? icon;

  const SpacePrimaryButton({super.key, required this.text, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.55,
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: SpacePalette.isDark(context) ? SpacePalette.cyan : Theme.of(context).colorScheme.primary,
            foregroundColor: SpacePalette.isDark(context) ? Colors.black : Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(width: 10),
              ],
              Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}

class SpaceGhostButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;

  const SpaceGhostButton({super.key, required this.text, this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: SpacePalette.stroke(context)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 10),
            ],
            Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class SpaceSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SpaceSectionTitle({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: SpacePalette.sub(context)),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class SpaceAvatar extends StatelessWidget {
  final String title;
  final String? imageUrl;
  final double radius;

  const SpaceAvatar({super.key, required this.title, this.imageUrl, this.radius = 24});

  @override
  Widget build(BuildContext context) {
    final initials = title.trim().isEmpty
        ? 'S'
        : title.trim().split(RegExp(r'\s+')).take(2).map((e) => e.characters.first.toUpperCase()).join();
    final colors = [SpacePalette.cyan, SpacePalette.indigo, SpacePalette.violet, SpacePalette.emerald];
    final color = colors[title.hashCode.abs() % colors.length];
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.16),
          boxShadow: [BoxShadow(color: color.withOpacity(0.18), blurRadius: 14, offset: const Offset(0, 8))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.network(
          imageUrl!,
          key: ValueKey(imageUrl),
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color.withOpacity(0.9), color.withOpacity(0.45)]),
              ),
              child: Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: radius * 0.55,
                ),
              ),
            );
          },
        ),
      );
    }
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [color.withOpacity(0.9), color.withOpacity(0.45)]),
        boxShadow: [BoxShadow(color: color.withOpacity(0.26), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.55,
        ),
      ),
    );
  }
}

class SpacePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SpacePill({super.key, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = SpacePalette.isDark(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(right: 10),
      child: Material(
        color: selected
            ? (dark ? SpacePalette.cyan.withOpacity(0.14) : Theme.of(context).colorScheme.primary.withOpacity(0.12))
            : SpacePalette.card(context),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? (dark ? SpacePalette.cyan.withOpacity(0.4) : Theme.of(context).colorScheme.primary.withOpacity(0.35))
                    : SpacePalette.stroke(context),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected
                    ? (dark ? Colors.white : Theme.of(context).colorScheme.primary)
                    : SpacePalette.sub(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SpaceLoadingScreen extends StatelessWidget {
  final String title;
  final String subtitle;

  const SpaceLoadingScreen({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 18),
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: SpacePalette.sub(context))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SpaceBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const SpaceBottomBar({super.key, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.call_rounded, 'Звонки'),
      (Icons.people_alt_rounded, 'Контакты'),
      (Icons.forum_rounded, 'Чаты'),
      (Icons.person_rounded, 'Профиль'),
    ];
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        borderRadius: BorderRadius.circular(28),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: currentIndex == i
                          ? (SpacePalette.isDark(context)
                              ? Colors.white.withOpacity(0.08)
                              : Theme.of(context).colorScheme.primary.withOpacity(0.10))
                          : Colors.transparent,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(items[i].$1, size: 22),
                        const SizedBox(height: 4),
                        Text(
                          items[i].$2,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: currentIndex == i ? FontWeight.w800 : FontWeight.w600,
                            color: currentIndex == i ? SpacePalette.text(context) : SpacePalette.sub(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
