import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'space_core.dart';
import 'space_models.dart';
import 'space_service.dart';

class SettingsPage extends StatefulWidget {
  final User currentUser;
  final UserProfile profile;
  final ValueChanged<UserProfile> onProfileChanged;

  const SettingsPage({
    super.key,
    required this.currentUser,
    required this.profile,
    required this.onProfileChanged,
  });

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  late UserProfile _profile;
  int _cacheBytes = 0;
  List<FolderItem> _folders = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    reloadProfile();
  }

  Future<void> reloadProfile() async {
    setState(() => _loading = true);
    try {
      final profile = await SpaceService.fetchProfile(widget.currentUser.uid) ?? _profile;
      final cache = await SpaceLocalPrefs.cacheSizeBytes();
      final folders = await SpaceService.getFolders(widget.currentUser.uid);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _cacheBytes = cache;
        _folders = folders;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openEditProfile() async {
    final updated = await Navigator.push<UserProfile>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(currentUser: widget.currentUser, profile: _profile),
      ),
    );
    if (updated != null) {
      setState(() => _profile = updated);
      widget.onProfileChanged(updated);
      reloadProfile();
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _toggleNotifications(bool value) async {
    await SpaceLocalPrefs.setNotificationsEnabled(value);
    if (mounted) setState(() {});
  }

  Future<void> _clearCache() async {
    await SpaceLocalPrefs.clearCache();
    _cacheBytes = await SpaceLocalPrefs.cacheSizeBytes();
    if (mounted) {
      setState(() {});
      showSpaceSnack(context, 'Кеш очищен.');
    }
  }

  Future<void> _openFolders() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FoldersSettingsSheet(ownerId: widget.currentUser.uid, onChanged: reloadProfile),
    );
  }

  Future<void> _openAppearance() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _AppearanceSheet(),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: reloadProfile,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Профиль', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  ),
                  IconButton.filledTonal(onPressed: _openEditProfile, icon: const Icon(Icons.edit_rounded)),
                ],
              ),
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  children: [
                    SpaceAvatar(title: _profile.fullName, imageUrl: _profile.avatarUrl, radius: 40),
                    const SizedBox(height: 12),
                    Text(_profile.fullName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('@${_profile.username}', style: TextStyle(color: SpacePalette.sub(context), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(_profile.email, style: TextStyle(color: SpacePalette.sub(context))),
                    if (_profile.bio.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_profile.bio, textAlign: TextAlign.center, style: TextStyle(color: SpacePalette.sub(context), height: 1.4)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: 'Уведомления',
                subtitle: 'Включить или выключить уведомления в приложении.',
                child: ValueListenableBuilder<bool>(
                  valueListenable: SpaceLocalPrefs.notificationsEnabledNotifier,
                  builder: (context, value, _) {
                    return SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: value,
                      onChanged: _toggleNotifications,
                      title: const Text('Уведомления'),
                      subtitle: Text(value ? 'Уведомления включены' : 'Уведомления выключены'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'Папки',
                subtitle: 'Вверху чатов отображаются «Все» и пользовательские папки.',
                child: Column(
                  children: [
                    for (final folder in _folders.take(4))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.folder_rounded),
                        title: Text(folder.title),
                      ),
                    if (_folders.isEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Папок пока нет', style: TextStyle(color: SpacePalette.sub(context))),
                      ),
                    const SizedBox(height: 6),
                    SpaceGhostButton(text: 'Открыть управление папками', onPressed: _openFolders, icon: Icons.folder_open_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'Память',
                subtitle: 'Очистка кеша приложения.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Текущий кеш: ${formatBytes(_cacheBytes)}', style: TextStyle(color: SpacePalette.sub(context))),
                    const SizedBox(height: 12),
                    SpaceGhostButton(text: 'Очистить кеш', onPressed: _clearCache, icon: Icons.cleaning_services_rounded),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'Оформление',
                subtitle: 'Тёмная/светлая тема и размер текста сообщений.',
                child: SpaceGhostButton(text: 'Настроить оформление', onPressed: _openAppearance, icon: Icons.palette_rounded),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'О приложении',
                subtitle: 'Space chat • версия starter 5.0',
                child: Text('Космический мессенджер на Flutter. Стиль, чаты, профили и журнал звонков уже настроены.', style: TextStyle(color: SpacePalette.sub(context), height: 1.4)),
              ),
              const SizedBox(height: 12),
              SpaceGhostButton(text: 'Выйти из профиля', onPressed: _logout, icon: Icons.logout_rounded),
              if (_loading) const SizedBox(height: 12),
              if (_loading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }
}

class EditProfilePage extends StatefulWidget {
  final User currentUser;
  final UserProfile profile;

  const EditProfilePage({super.key, required this.currentUser, required this.profile});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  final _picker = ImagePicker();
  Timer? _debounce;
  bool _saving = false;
  bool _checking = false;
  bool? _available = true;
  String? _usernameError;
  XFile? _avatar;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.fullName);
    _usernameController = TextEditingController(text: widget.profile.username);
    _bioController = TextEditingController(text: widget.profile.bio);
    _usernameController.addListener(_checkUsername);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  bool get _changed {
    return _nameController.text.trim() != widget.profile.fullName ||
        _usernameController.text.trim().toLowerCase() != widget.profile.username ||
        _bioController.text.trim() != widget.profile.bio ||
        _avatar != null;
  }

  void _checkUsername() {
    _debounce?.cancel();
    final localError = SpaceService.localUsernameError(_usernameController.text);
    setState(() {
      _usernameError = localError;
      _available = localError == null ? null : false;
    });
    if (localError != null) return;
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _checking = true);
      final available = await SpaceService.isUsernameAvailable(
        _usernameController.text,
        excludingUserId: widget.currentUser.uid,
      );
      if (!mounted) return;
      setState(() {
        _checking = false;
        _available = available;
        _usernameError = available ? null : 'Этот username уже занят.';
      });
    });
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 86, maxWidth: 1400);
    if (file == null) return;
    setState(() => _avatar = file);
  }

  Future<void> _showPickSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
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
      ),
    );
  }

  Future<void> _save() async {
    if (!_changed) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final profile = await SpaceService.createOrUpdateProfile(
        firebaseUser: widget.currentUser,
        fullName: _nameController.text,
        username: _usernameController.text,
        bio: _bioController.text,
        avatarFile: _avatar,
      );
      if (!mounted) return;
      showSpaceSnack(context, 'Профиль сохранён.');
      Navigator.pop(context, profile);
    } catch (e) {
      showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final suffix = _checking
        ? const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        : (_available == true
            ? const Icon(Icons.check_circle_rounded, color: SpacePalette.emerald)
            : (_usernameError != null ? const Icon(Icons.cancel_rounded, color: SpacePalette.red) : null));

    return SpaceScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Row(
              children: [
                IconButton.filledTonal(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18)),
                const SizedBox(width: 8),
                Text('Изменить профиль', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 18),
            GlassCard(
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Stack(
                      children: [
                        _avatar != null
                            ? CircleAvatar(radius: 42, backgroundImage: FileImage(File(_avatar!.path)))
                            : SpaceAvatar(title: widget.profile.fullName, imageUrl: widget.profile.avatarUrl, radius: 42),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: InkWell(
                            onTap: _showPickSheet,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: SpacePalette.isDark(context) ? SpacePalette.cyan : Theme.of(context).colorScheme.primary,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Icon(Icons.edit_rounded, size: 16, color: SpacePalette.isDark(context) ? Colors.black : Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Имя'),
                      validator: (value) => value == null || value.trim().isEmpty ? 'Имя обязательно.' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _usernameController,
                      decoration: InputDecoration(labelText: 'Username', prefixText: '@', suffixIcon: suffix, errorText: _usernameError),
                      validator: (value) {
                        final err = SpaceService.localUsernameError(value ?? '');
                        if (err != null) return err;
                        if (_available == false) return 'Этот username уже занят.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bioController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 200,
                      decoration: const InputDecoration(labelText: 'О себе'),
                    ),
                    const SizedBox(height: 10),
                    if (_changed)
                      SpacePrimaryButton(text: _saving ? 'Сохраняем...' : 'Сохранить', onPressed: _saving ? null : _save)
                    else
                      SpaceGhostButton(text: 'Выйти из профиля', onPressed: _save, icon: Icons.logout_rounded),
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

class _SettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SettingsCard({required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: SpacePalette.sub(context), height: 1.4)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _FoldersSettingsSheet extends StatefulWidget {
  final String ownerId;
  final Future<void> Function() onChanged;

  const _FoldersSettingsSheet({required this.ownerId, required this.onChanged});

  @override
  State<_FoldersSettingsSheet> createState() => _FoldersSettingsSheetState();
}

class _FoldersSettingsSheetState extends State<_FoldersSettingsSheet> {
  final _controller = TextEditingController();
  List<FolderItem> _folders = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await SpaceService.getFolders(widget.ownerId);
    if (!mounted) return;
    setState(() {
      _folders = rows;
      _loading = false;
    });
  }

  Future<void> _create() async {
    try {
      await SpaceService.createFolder(ownerId: widget.ownerId, title: _controller.text);
      _controller.clear();
      await _load();
      await widget.onChanged();
    } catch (e) {
      showSpaceSnack(context, '$e');
    }
  }

  Future<void> _delete(FolderItem folder) async {
    await SpaceService.deleteFolder(ownerId: widget.ownerId, folderId: folder.id);
    await _load();
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 14, right: 14, top: 14, bottom: MediaQuery.of(context).viewInsets.bottom + 14),
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Папки', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextField(controller: _controller, decoration: const InputDecoration(labelText: 'Создать новую папку')),
            const SizedBox(height: 12),
            SpacePrimaryButton(text: 'Создать папку', onPressed: _create),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else ...[
              const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.folder_special_rounded), title: Text('Все'), subtitle: Text('Эту папку удалить нельзя')),
              for (final folder in _folders)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(folder.title),
                  trailing: IconButton(onPressed: () => _delete(folder), icon: const Icon(Icons.delete_outline_rounded)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppearanceSheet extends StatelessWidget {
  const _AppearanceSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Оформление', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: SpaceLocalPrefs.themeModeNotifier,
              builder: (context, mode, _) {
                return Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      value: ThemeMode.dark,
                      groupValue: mode,
                      title: const Text('Тёмная тема'),
                      onChanged: (value) => SpaceLocalPrefs.setThemeMode(value!),
                    ),
                    RadioListTile<ThemeMode>(
                      contentPadding: EdgeInsets.zero,
                      value: ThemeMode.light,
                      groupValue: mode,
                      title: const Text('Светлая тема'),
                      onChanged: (value) => SpaceLocalPrefs.setThemeMode(value!),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<double>(
              valueListenable: SpaceLocalPrefs.messageScaleNotifier,
              builder: (context, scale, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Размер текста сообщений: ${scale.toStringAsFixed(1)}x', style: TextStyle(color: SpacePalette.sub(context))),
                    Slider(
                      value: scale,
                      min: 0.9,
                      max: 1.35,
                      divisions: 9,
                      onChanged: (value) => SpaceLocalPrefs.setMessageScale(value),
                    ),
                    const SizedBox(height: 8),
                    GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: SpacePalette.cardStrong(context),
                              border: Border.all(color: SpacePalette.stroke(context)),
                            ),
                            child: Text('Пример входящего сообщения', style: TextStyle(fontSize: 15 * scale)),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                gradient: const LinearGradient(colors: [SpacePalette.indigo, SpacePalette.cyan]),
                              ),
                              child: Text('Пример исходящего сообщения', style: TextStyle(fontSize: 15 * scale, color: Colors.white)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
