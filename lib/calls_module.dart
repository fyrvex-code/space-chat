import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

import 'space_core.dart';
import 'space_models.dart';
import 'space_service.dart';
import 'zego_config.dart';


Future<void> startSpaceChatInvitation({
  required BuildContext context,
  required User currentUser,
  required UserProfile currentProfile,
  required String title,
  required String? conversationId,
  required bool isVideo,
  required List<SpaceCallInvitee> invitees,
}) async {
  final ok = await SpaceCallKit.startInvitation(
    callerId: currentUser.uid,
    callerName: currentProfile.fullName,
    invitees: invitees,
    isVideoCall: isVideo,
    title: title,
    conversationId: conversationId,
  );
  if (!context.mounted) return;
  if (!ok) {
    showSpaceSnack(context, 'Не удалось отправить звонок. Проверь ключи ZEGO и вход второго пользователя в приложение.');
  }
}

class CallsPage extends StatefulWidget {
  final User currentUser;
  final UserProfile profile;

  const CallsPage({
    super.key,
    required this.currentUser,
    required this.profile,
  });

  @override
  State<CallsPage> createState() => CallsPageState();
}

class CallsPageState extends State<CallsPage> {
  bool _loading = true;
  int _tab = 0;
  List<CallLogItem> _calls = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await SpaceService.getCallLogs(widget.currentUser.uid);
      if (!mounted) return;
      setState(() => _calls = rows);
    } catch (e) {
      if (mounted) showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openQuickCall({required bool video, required bool group}) async {
    if (group) {
      await _showRoomCodeSheet();
      return;
    }
    final contacts = await SpaceService.getContacts(widget.currentUser.uid);
    if (!mounted) return;
    if (contacts.isEmpty) {
      showSpaceSnack(context, 'Сначала добавь хотя бы один контакт.');
      return;
    }
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(14),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(video ? 'Кому позвонить по видео' : 'Кому позвонить', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              SizedBox(
                height: 320,
                child: ListView.separated(
                  itemCount: contacts.length,
                  separatorBuilder: (_, __) => Divider(color: SpacePalette.stroke(context)),
                  itemBuilder: (context, index) {
                    final item = contacts[index];
                    return ListTile(
                      leading: SpaceAvatar(title: item.title, imageUrl: item.profile.avatarUrl, radius: 22),
                      title: Text(item.title),
                      subtitle: Text(item.profile.displayHandle),
                      trailing: Icon(video ? Icons.videocam_rounded : Icons.call_rounded),
                      onTap: () async {
                        Navigator.pop(context);
                        await startSpaceChatInvitation(
                          context: this.context,
                          currentUser: widget.currentUser,
                          currentProfile: widget.profile,
                          title: item.title,
                          conversationId: null,
                          isVideo: video,
                          invitees: [
                            SpaceCallInvitee(userId: item.profile.id, userName: item.title),
                          ],
                        );
                        await _load();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRoomCodeSheet() async {
    final controller = TextEditingController();
    bool video = false;
    bool group = true;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 14,
                right: 14,
                top: 14,
                bottom: MediaQuery.of(context).viewInsets.bottom + 14,
              ),
              child: GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Войти в комнату', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('Это запасной ручной режим по коду комнаты. Основные звонки теперь идут как в мессенджерах — с входящим окном ответить или сбросить.', style: TextStyle(color: SpacePalette.sub(context))),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(labelText: 'Код комнаты', hintText: 'например: direct_abc123'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: SpacePill(label: 'Голос', selected: !video, onTap: () => setSheet(() => video = false))),
                        const SizedBox(width: 8),
                        Expanded(child: SpacePill(label: 'Видео', selected: video, onTap: () => setSheet(() => video = true))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: SpacePill(label: '1 на 1', selected: !group, onTap: () => setSheet(() => group = false))),
                        const SizedBox(width: 8),
                        Expanded(child: SpacePill(label: 'Группа', selected: group, onTap: () => setSheet(() => group = true))),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SpacePrimaryButton(
                      text: 'Открыть комнату',
                      onPressed: () async {
                        final raw = controller.text.trim();
                        if (raw.isEmpty) {
                          showSpaceSnack(context, 'Введи код комнаты.');
                          return;
                        }
                        final callId = SpaceService.sanitizeCallRoomId(raw);
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CallSessionPage(
                              ownerId: widget.currentUser.uid,
                              ownerName: widget.profile.fullName,
                              title: video ? 'Видеокомната' : 'Голосовая комната',
                              callType: video ? 'video' : 'voice',
                              avatarUrl: widget.profile.avatarUrl,
                              accentLabel: 'Комната: $callId',
                              callId: callId,
                              groupMode: group,
                            ),
                          ),
                        );
                        await _load();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _tab == 0 ? _calls : _calls.where((e) => e.isMissed).toList();

    return SpaceScaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
            children: [
              SpaceSectionTitle(
                title: 'Звонки',
                subtitle: 'Реальные звонки через ZEGO: у второго пользователя появится окно ответить или сбросить. Для работы вставь appID и appSign в zego_config.dart.',
                trailing: IconButton.filledTonal(
                  onPressed: _showRoomCodeSheet,
                  icon: const Icon(Icons.dialpad_rounded),
                ),
              ),
              const SizedBox(height: 14),
              if (!ZegoCallSecrets.isConfigured)
                GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: SpacePalette.yellow.withOpacity(0.16),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.vpn_key_rounded, color: SpacePalette.yellow),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('Чтобы реальные входящие звонки заработали, вставь appId и appSign из ZEGOCLOUD в lib/zego_config.dart.', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('После этого пересобери APK и обязательно войди в приложение на двух телефонах. Тогда у второго пользователя появится входящий экран со сбросом и ответом.', style: TextStyle(color: SpacePalette.sub(context))),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    Expanded(child: SpacePill(label: 'Все', selected: _tab == 0, onTap: () => setState(() => _tab = 0))),
                    Expanded(child: SpacePill(label: 'Пропущенные', selected: _tab == 1, onTap: () => setState(() => _tab = 1))),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              GlassCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _CallHeroButton(
                            icon: Icons.call_rounded,
                            title: 'Голосовой',
                            subtitle: '1 на 1',
                            onTap: () => _openQuickCall(video: false, group: false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CallHeroButton(
                            icon: Icons.videocam_rounded,
                            title: 'Видео',
                            subtitle: '1 на 1',
                            onTap: () => _openQuickCall(video: true, group: false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CallHeroButton(
                            icon: Icons.groups_rounded,
                            title: 'Группа',
                            subtitle: 'Комната',
                            onTap: () => _openQuickCall(video: false, group: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CallHeroButton(
                            icon: Icons.meeting_room_rounded,
                            title: 'По коду',
                            subtitle: 'Войти',
                            onTap: _showRoomCodeSheet,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visible.isEmpty)
                GlassCard(
                  child: Column(
                    children: [
                      const Icon(Icons.ring_volume_rounded, size: 42),
                      const SizedBox(height: 12),
                      Text('Журнал пока пустой', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('После завершения голосовых и видеозвонков они появятся здесь.', textAlign: TextAlign.center, style: TextStyle(color: SpacePalette.sub(context))),
                    ],
                  ),
                )
              else
                ...visible.map(
                  (call) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _CallLogTile(
                      item: call,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CallSessionPage(
                            ownerId: widget.currentUser.uid,
                            ownerName: widget.profile.fullName,
                            title: call.title,
                            callType: call.isVideo ? 'video' : 'voice',
                            avatarUrl: widget.profile.avatarUrl,
                            accentLabel: 'Повторный звонок',
                            callId: SpaceService.sanitizeCallRoomId('history_${call.id}'),
                            groupMode: call.isGroup,
                          ),
                        ),
                      ).then((_) => _load()),
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

class CallSessionPage extends StatelessWidget {
  final String ownerId;
  final String ownerName;
  final String title;
  final String callType;
  final String? avatarUrl;
  final String? accentLabel;
  final String? callId;
  final bool groupMode;

  const CallSessionPage({
    super.key,
    required this.ownerId,
    required this.ownerName,
    required this.title,
    required this.callType,
    required this.avatarUrl,
    required this.accentLabel,
    this.callId,
    this.groupMode = false,
  });

  bool get _isVideo => callType == 'video';

  @override
  Widget build(BuildContext context) {
    final roomId = SpaceService.sanitizeCallRoomId(callId ?? title);
    if (!ZegoCallSecrets.isConfigured) {
      return _MissingCallConfigPage(roomId: roomId);
    }

    final config = SpaceCallKit.configFor(
      isVideo: _isVideo,
      isGroup: groupMode,
      title: title,
    );

    return ZegoUIKitPrebuiltCall(
      appID: ZegoCallSecrets.appId,
      appSign: ZegoCallSecrets.appSign,
      userID: SpaceService.sanitizeCallRoomId(ownerId),
      userName: ownerName,
      callID: roomId,
      config: config,
      plugins: [ZegoUIKitSignalingPlugin()],
      events: ZegoUIKitPrebuiltCallEvents(
        onCallEnd: (event, defaultAction) async {
          try {
            await SpaceService.addCallLog(
              ownerId: ownerId,
              title: title,
              callType: groupMode ? 'group' : (_isVideo ? 'video' : 'voice'),
              status: event.reason == ZegoCallEndReason.kickOut ? 'missed' : 'done',
            );
          } catch (_) {}
          defaultAction.call();
        },
      ),
    );
  }
}

class _MissingCallConfigPage extends StatelessWidget {
  final String roomId;

  const _MissingCallConfigPage({required this.roomId});

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _BackOnly(onTap: () => Navigator.pop(context)),
            const SizedBox(height: 18),
            GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: SpacePalette.red.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.wifi_calling_3_rounded, color: SpacePalette.red, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('Звонок ещё не подключён к облаку', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('Я уже подготовил живой экран звонка. Осталось вставить appID и appSign в lib/zego_config.dart, затем пересобрать APK.', style: TextStyle(color: SpacePalette.sub(context), height: 1.4)),
                  const SizedBox(height: 14),
                  _CodeBox(label: 'Комната', value: roomId),
                  const SizedBox(height: 10),
                  _CodeBox(label: 'Файл', value: 'lib/zego_config.dart'),
                  const SizedBox(height: 16),
                  SpacePrimaryButton(
                    text: 'Скопировать код комнаты',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: roomId));
                      if (!context.mounted) return;
                      showSpaceSnack(context, 'Код комнаты скопирован.');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  final String label;
  final String value;

  const _CodeBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(SpacePalette.isDark(context) ? 0.18 : 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SpacePalette.stroke(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: SpacePalette.sub(context), fontSize: 12)),
          const SizedBox(height: 4),
          SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CallNebulaBackground extends StatelessWidget {
  const _CallNebulaBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF040714), Color(0xFF0C1532), Color(0xFF081B28)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -40,
            left: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x3357E8FF),
              ),
            ),
          ),
          Positioned(
            right: -20,
            bottom: -10,
            child: Container(
              width: 190,
              height: 190,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0x337C78FF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallHeroButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CallHeroButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0x2235D9FF), Color(0x227C78FF), Color(0x2235F3B3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: SpacePalette.stroke(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: SpacePalette.cardStrong(context).withOpacity(0.92),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon),
            ),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(color: SpacePalette.sub(context))),
          ],
        ),
      ),
    );
  }
}

class _CallLogTile extends StatelessWidget {
  final CallLogItem item;
  final VoidCallback onTap;

  const _CallLogTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final icon = item.isVideo
        ? Icons.videocam_rounded
        : item.isGroup
            ? Icons.groups_rounded
            : Icons.call_rounded;
    final color = item.isMissed ? SpacePalette.red : (_statusColor(item.callType));
    final statusText = item.isMissed ? 'Пропущенный' : 'Завершён';

    return GlassCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    '$statusText • ${_formatTime(item.createdAt)}',
                    style: TextStyle(color: SpacePalette.sub(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: SpacePalette.sub(context)),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }

  static Color _statusColor(String type) {
    switch (type) {
      case 'video':
        return SpacePalette.cyan;
      case 'group':
        return SpacePalette.violet;
      default:
        return SpacePalette.emerald;
    }
  }
}

class _BackOnly extends StatelessWidget {
  final VoidCallback onTap;

  const _BackOnly({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton.filledTonal(
        onPressed: onTap,
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
      ),
    );
  }
}
