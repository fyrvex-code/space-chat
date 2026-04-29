import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';

import 'calls_module.dart';
import 'chat_module.dart';
import 'firebase_options.dart';
import 'settings_module.dart';
import 'space_core.dart';
import 'space_models.dart';
import 'space_service.dart';
import 'zego_config.dart';

const String kSupabaseUrl = 'https://tdcxrycsyptvylnijxff.supabase.co';
const String kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRkY3hyeWNzeXB0dnlsbmlqeGZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY1NzEyOTIsImV4cCI6MjA5MjE0NzI5Mn0.MnQ34BduLPdvKaQIcl1EjKrXLmb7HPcog7VzeqA2RN0';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SpaceCallKit.attachNavigator();
  SpaceCallKit.enableSystemCallingUI();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  await SpaceLocalPrefs.init();
  runApp(const SpaceChatApp());
}

class SpaceChatApp extends StatelessWidget {
  const SpaceChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SpaceLocalPrefs.themeModeNotifier,
      builder: (context, mode, _) {
        return ValueListenableBuilder<double>(
          valueListenable: SpaceLocalPrefs.messageScaleNotifier,
          builder: (context, scale, __) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorKey: spaceNavigatorKey,
              title: 'Space chat',
              themeMode: mode,
              theme: SpaceTheme.light(scale),
              darkTheme: SpaceTheme.dark(scale),
              builder: (context, child) {
                return Stack(
                  children: [
                    if (child != null) child,
                    if (spaceNavigatorKey.currentState != null)
                      ZegoUIKitPrebuiltCallMiniOverlayPage(
                        contextQuery: () =>
                            spaceNavigatorKey.currentState!.context,
                      ),
                  ],
                );
              },
              home: const AuthGate(),
            );
          },
        );
      },
    );
  }
}

enum AuthStep { unauthorized, needEmailVerification, needProfile, authorized }

class AuthGateState {
  final AuthStep step;
  final User? user;
  final UserProfile? profile;

  const AuthGateState._({required this.step, this.user, this.profile});

  const AuthGateState.unauthorized() : this._(step: AuthStep.unauthorized);
  const AuthGateState.needEmailVerification({required User user})
      : this._(step: AuthStep.needEmailVerification, user: user);
  const AuthGateState.needProfile({required User user})
      : this._(step: AuthStep.needProfile, user: user);
  const AuthGateState.authorized(
      {required User user, required UserProfile profile})
      : this._(step: AuthStep.authorized, user: user, profile: profile);
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Future<AuthGateState>? _future;
  StreamSubscription<User?>? _sub;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
    _sub = FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) {
        setState(() => _future = _resolve());
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<AuthGateState> _resolve() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return const AuthGateState.unauthorized();

      await user.reload();
      final fresh = FirebaseAuth.instance.currentUser;
      if (fresh == null) return const AuthGateState.unauthorized();

      if (!fresh.emailVerified) {
        return AuthGateState.needEmailVerification(user: fresh);
      }

      final profile = await SpaceService.fetchProfile(fresh.uid);
      if (profile == null || !profile.isComplete) {
        return AuthGateState.needProfile(user: fresh);
      }

      return AuthGateState.authorized(user: fresh, profile: profile);
    } catch (e) {
      throw Exception('Ошибка запуска приложения: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthGateState>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SpaceLoadingScreen(
            title: 'Запускаем Space chat',
            subtitle: 'Собираем космическую станцию и подключаем профиль...',
          );
        }
        if (snapshot.hasError) {
          return SpaceScaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 32),
                    GlassCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: SpacePalette.red.withOpacity(0.16),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.error_outline_rounded,
                                    color: SpacePalette.red),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Ошибка запуска',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text('${snapshot.error}',
                              style: TextStyle(
                                  color: SpacePalette.sub(context),
                                  height: 1.45)),
                          const SizedBox(height: 20),
                          SpacePrimaryButton(
                            text: 'Повторить',
                            onPressed: () =>
                                setState(() => _future = _resolve()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final state = snapshot.data ?? const AuthGateState.unauthorized();
        switch (state.step) {
          case AuthStep.unauthorized:
            return const WelcomePage();
          case AuthStep.needEmailVerification:
            return EmailVerificationPage(user: state.user!);
          case AuthStep.needProfile:
            return CompleteProfilePage(user: state.user!);
          case AuthStep.authorized:
            return HomeRoot(user: state.user!, profile: state.profile!);
        }
      },
    );
  }
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 900),
                tween: Tween(begin: 0.94, end: 1),
                curve: Curves.easeOutBack,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: GlassCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 62,
                            height: 62,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                SpacePalette.cyan,
                                SpacePalette.indigo
                              ]),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: SpacePalette.cyan.withOpacity(0.32),
                                  blurRadius: 22,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.rocket_launch_rounded,
                                color: Colors.white, size: 32),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Space chat',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Космический мессенджер с профилями, чатами, группами, каналами и звонками.',
                                  style: TextStyle(
                                      color: SpacePalette.sub(context),
                                      height: 1.45),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _WelcomeFeature(
                          icon: Icons.mail_outline_rounded,
                          text:
                              'Вход и регистрация через Firebase Email/Password'),
                      _WelcomeFeature(
                          icon: Icons.badge_outlined,
                          text: 'Уникальный username и оформление профиля'),
                      _WelcomeFeature(
                          icon: Icons.forum_outlined,
                          text:
                              'Чаты, папки, контакты, группы и приватные каналы'),
                      _WelcomeFeature(
                          icon: Icons.call_outlined,
                          text: 'Красивый центр звонков и журнал вызовов'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SpacePrimaryButton(
                text: 'Зарегистрироваться',
                icon: const Icon(Icons.person_add_alt_1_rounded,
                    color: Colors.white),
                onPressed: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const RegisterPage()));
                },
              ),
              const SizedBox(height: 12),
              SpaceGhostButton(
                text: 'Войти',
                icon: Icons.login_rounded,
                onPressed: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LoginPage()));
                },
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Dark mode включён по умолчанию. В настройках можно сменить тему и размер текста сообщений.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: SpacePalette.sub(context), height: 1.4),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeFeature extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WelcomeFeature({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white.withOpacity(0.05),
            ),
            child: Icon(icon, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, height: 1.35))),
        ],
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final result = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = result.user;
      if (user == null) return;

      if (!user.emailVerified) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => EmailVerificationPage(user: user)),
        );
        return;
      }

      final profile = await SpaceService.fetchProfile(user.uid);
      if (!mounted) return;
      if (profile == null || !profile.isComplete) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => CompleteProfilePage(user: user)),
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
              builder: (_) => HomeRoot(user: user, profile: profile)),
          (_) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      showSpaceSnack(context, SpaceService.firebaseErrorToText(e));
    } catch (e) {
      showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            _TopBack(onPressed: () => Navigator.pop(context), title: 'Войти'),
            const SizedBox(height: 24),
            GlassCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Рад снова видеть тебя на орбите',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                        'Войди по почте и паролю. Если профиль ещё не заполнен, приложение само отправит тебя на экран создания профиля.',
                        style: TextStyle(
                            color: SpacePalette.sub(context), height: 1.45)),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Введите почту.'
                              : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Введите пароль.'
                          : null,
                    ),
                    const SizedBox(height: 22),
                    SpacePrimaryButton(
                        text: _loading ? 'Входим...' : 'Войти',
                        onPressed: _loading ? null : _login),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repeatController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _repeatController.dispose();
    super.dispose();
  }

  int get _passwordStage {
    final value = _passwordController.text;
    var score = 0;
    if (value.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(value) && RegExp(r'[a-z]').hasMatch(value))
      score++;
    if (RegExp(r'[0-9]').hasMatch(value)) score++;
    if (RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]').hasMatch(value)) score++;
    return score;
  }

  String get _passwordLabel {
    switch (_passwordStage) {
      case 0:
      case 1:
        return 'Слабый';
      case 2:
        return 'Нормальный';
      case 3:
        return 'Хороший';
      case 4:
        return 'Сильный';
      default:
        return 'Слабый';
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final user = result.user;
      if (user == null) return;
      await user.sendEmailVerification();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => EmailVerificationPage(user: user)),
      );
    } on FirebaseAuthException catch (e) {
      showSpaceSnack(context, SpaceService.firebaseErrorToText(e));
    } catch (e) {
      showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            _TopBack(
                onPressed: () => Navigator.pop(context), title: 'Регистрация'),
            const SizedBox(height: 24),
            GlassCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Создай аккаунт',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                        'После регистрации придёт письмо подтверждения. Потом ты вернёшься в приложение и войдёшь в аккаунт.',
                        style: TextStyle(
                            color: SpacePalette.sub(context), height: 1.45)),
                    const SizedBox(height: 22),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty)
                          return 'Введите почту.';
                        if (!value.contains('@')) return 'Неверный email.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscure1,
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscure1 = !_obscure1),
                          icon: Icon(_obscure1
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'Введите пароль.';
                        if (value.length < 8) return 'Минимум 8 символов.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _PasswordMeter(
                        stage: _passwordStage, label: _passwordLabel),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _repeatController,
                      obscureText: _obscure2,
                      decoration: InputDecoration(
                        labelText: 'Повтори пароль',
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _obscure2 = !_obscure2),
                          icon: Icon(_obscure2
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty)
                          return 'Повтори пароль.';
                        if (value != _passwordController.text)
                          return 'Пароли не совпадают.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 22),
                    SpacePrimaryButton(
                        text: _loading ? 'Создаём...' : 'Создать аккаунт',
                        onPressed: _loading ? null : _register),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmailVerificationPage extends StatefulWidget {
  final User user;

  const EmailVerificationPage({super.key, required this.user});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  bool _loading = false;
  bool _resending = false;

  Future<void> _check() async {
    setState(() => _loading = true);
    try {
      await widget.user.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Пользователь не найден.');
      if (!user.emailVerified) {
        showSpaceSnack(context,
            'Почта ещё не подтверждена. Проверь письмо и нажми ссылку.');
        return;
      }
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
      showSpaceSnack(context, 'Почта подтверждена. Теперь войди в аккаунт.');
    } catch (e) {
      showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await widget.user.sendEmailVerification();
      showSpaceSnack(context, 'Ссылка отправлена ещё раз.');
    } catch (e) {
      showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            _TopBack(
                onPressed: () =>
                    Navigator.popUntil(context, (route) => route.isFirst),
                title: 'Подтверждение почты'),
            const SizedBox(height: 24),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                          colors: [SpacePalette.indigo, SpacePalette.cyan]),
                    ),
                    child: const Icon(Icons.mark_email_read_rounded,
                        size: 34, color: Colors.white),
                  ),
                  const SizedBox(height: 18),
                  Text('Подтверди почту',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(
                    'Мы отправили письмо на ${widget.user.email ?? 'твой email'}. Нажми ссылку в письме, потом возвращайся в приложение и жми кнопку ниже.',
                    style: TextStyle(
                        color: SpacePalette.sub(context), height: 1.45),
                  ),
                  const SizedBox(height: 22),
                  SpacePrimaryButton(
                      text: _loading ? 'Проверяем...' : 'Я подтвердил',
                      onPressed: _loading ? null : _check),
                  const SizedBox(height: 12),
                  SpaceGhostButton(
                      text: _resending
                          ? 'Отправляем...'
                          : 'Отправить ссылку ещё раз',
                      onPressed: _resending ? null : _resend,
                      icon: Icons.refresh_rounded),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CompleteProfilePage extends StatefulWidget {
  final User user;

  const CompleteProfilePage({super.key, required this.user});

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  Timer? _usernameDebounce;
  bool _saving = false;
  bool _checking = false;
  bool? _usernameAvailable;
  String? _usernameError;
  XFile? _avatar;
  UserProfile? _existing;

  @override
  void initState() {
    super.initState();
    _loadExisting();
    _usernameController.addListener(_onUsernameChanged);
  }

  Future<void> _loadExisting() async {
    final profile = await SpaceService.fetchProfile(widget.user.uid);
    if (!mounted) return;
    if (profile != null) {
      _existing = profile;
      _nameController.text = profile.fullName;
      _usernameController.text = profile.username;
      _bioController.text = profile.bio;
      _usernameAvailable = true;
    }
    setState(() {});
  }

  void _onUsernameChanged() {
    _usernameDebounce?.cancel();
    final value = _usernameController.text.trim();
    final localError = SpaceService.localUsernameError(value);
    setState(() {
      _usernameError = localError;
      _usernameAvailable =
          localError == null && value.isNotEmpty ? null : false;
    });
    if (localError != null || value.isEmpty) return;
    _usernameDebounce = Timer(const Duration(milliseconds: 450), () async {
      setState(() => _checking = true);
      final available = await SpaceService.isUsernameAvailable(
        value,
        excludingUserId: widget.user.uid,
      );
      if (!mounted) return;
      setState(() {
        _checking = false;
        _usernameAvailable = available;
        _usernameError = available ? null : 'Этот username уже занят.';
      });
    });
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final file = await _picker.pickImage(
        source: source, imageQuality: 86, maxWidth: 1400);
    if (file == null) return;
    setState(() => _avatar = file);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_usernameError != null || _usernameAvailable == false) {
      showSpaceSnack(context, _usernameError ?? 'Username занят.');
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = await SpaceService.createOrUpdateProfile(
        firebaseUser: widget.user,
        fullName: _nameController.text,
        username: _usernameController.text,
        bio: _bioController.text,
        avatarFile: _avatar,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (_) => HomeRoot(user: widget.user, profile: profile)),
        (_) => false,
      );
    } catch (e) {
      showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = _existing?.avatarUrl;
    final suffix = _checking
        ? const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)),
          )
        : (_usernameAvailable == true
            ? const Icon(Icons.check_circle_rounded,
                color: SpacePalette.emerald)
            : (_usernameError != null
                ? const Icon(Icons.cancel_rounded, color: SpacePalette.red)
                : null));

    return SpaceScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            _TopBack(onPressed: () {}, title: 'Создать профиль', locked: true),
            const SizedBox(height: 24),
            GlassCard(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              _avatar != null
                                  ? CircleAvatar(
                                      radius: 46,
                                      backgroundImage:
                                          FileImage(File(_avatar!.path)))
                                  : SpaceAvatar(
                                      title: _nameController.text.isEmpty
                                          ? 'Space chat'
                                          : _nameController.text,
                                      imageUrl: previewUrl,
                                      radius: 46),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: InkWell(
                                  onTap: () => _showAvatarSheet(context),
                                  child: Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: SpacePalette.isDark(context)
                                          ? SpacePalette.cyan
                                          : Theme.of(context)
                                              .colorScheme
                                              .primary,
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                    ),
                                    child: Icon(Icons.camera_alt_rounded,
                                        color: SpacePalette.isDark(context)
                                            ? Colors.black
                                            : Colors.white,
                                        size: 18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text('Добавь аватарку, имя и username',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Имя'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Имя обязательно.'
                              : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: 'Username',
                        prefixText: '@',
                        suffixIcon: suffix,
                        helperText: 'Только английские буквы и символы _ - .',
                        errorText: _usernameError,
                      ),
                      validator: (value) {
                        final error =
                            SpaceService.localUsernameError(value ?? '');
                        if (error != null) return error;
                        if (_usernameAvailable == false)
                          return 'Этот username уже занят.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _bioController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 200,
                      decoration: const InputDecoration(
                          labelText: 'О себе (до 200 символов)'),
                    ),
                    const SizedBox(height: 8),
                    SpacePrimaryButton(
                        text: _saving ? 'Сохраняем...' : 'Сохранить профиль',
                        onPressed: _saving ? null : _save),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAvatarSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(14),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Выбрать из галереи'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAvatar(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_rounded),
                  title: const Text('Сфотографировать'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAvatar(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class HomeRoot extends StatefulWidget {
  final User user;
  final UserProfile profile;

  const HomeRoot({super.key, required this.user, required this.profile});

  @override
  State<HomeRoot> createState() => _HomeRootState();
}

class _HomeRootState extends State<HomeRoot> {
  late UserProfile _profile;
  int _index = 2;
  final _chatHubKey = GlobalKey<ChatsHubPageState>();
  final _contactsKey = GlobalKey<ContactsPageState>();
  final _callsKey = GlobalKey<CallsPageState>();
  final _settingsKey = GlobalKey<SettingsPageState>();

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _syncCallKit();
  }

  @override
  void dispose() {
    SpaceCallKit.uninit();
    super.dispose();
  }

  Future<void> _syncCallKit() async {
    await SpaceCallKit.initForUser(
      userId: widget.user.uid,
      userName: _profile.fullName.trim().isNotEmpty
          ? _profile.fullName.trim()
          : (_profile.username.trim().isNotEmpty
              ? _profile.username
              : (widget.user.email ?? 'Space user')),
    );
    SpaceCallKit.enterAcceptedOfflineCall();
  }

  void _refreshProfile(UserProfile value) {
    setState(() => _profile = value);
    _syncCallKit();
    _chatHubKey.currentState?.reload();
    _contactsKey.currentState?.reload();
    _callsKey.currentState?.reload();
    _settingsKey.currentState?.reloadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      CallsPage(key: _callsKey, currentUser: widget.user, profile: _profile),
      ContactsPage(
        key: _contactsKey,
        currentUser: widget.user,
        currentProfile: _profile,
        onConversationChanged: () => _chatHubKey.currentState?.reload(),
      ),
      ChatsHubPage(
        key: _chatHubKey,
        currentUser: widget.user,
        currentProfile: _profile,
        onProfileUpdated: _refreshProfile,
      ),
      SettingsPage(
        key: _settingsKey,
        currentUser: widget.user,
        profile: _profile,
        onProfileChanged: _refreshProfile,
      ),
    ];

    return SpaceScaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: SpaceBottomBar(
          currentIndex: _index,
          onTap: (value) => setState(() => _index = value)),
    );
  }
}

class _PasswordMeter extends StatelessWidget {
  final int stage;
  final String label;

  const _PasswordMeter({required this.stage, required this.label});

  @override
  Widget build(BuildContext context) {
    Color colorFor(int i) {
      if (i >= stage) return SpacePalette.stroke(context);
      if (stage <= 1) return SpacePalette.red;
      if (stage == 2) return SpacePalette.yellow;
      if (stage == 3) return SpacePalette.cyan;
      return SpacePalette.emerald;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Container(
                  height: 8,
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: colorFor(i),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Сложность пароля: $label',
            style: TextStyle(
                color: SpacePalette.sub(context), fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _TopBack extends StatelessWidget {
  final VoidCallback onPressed;
  final String title;
  final bool locked;

  const _TopBack(
      {required this.onPressed, required this.title, this.locked = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: locked ? null : onPressed,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
