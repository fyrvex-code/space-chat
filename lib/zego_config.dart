import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

import 'space_core.dart';
import 'space_service.dart';

final GlobalKey<NavigatorState> spaceNavigatorKey = GlobalKey<NavigatorState>();

class ZegoCallSecrets {
  /// Get these in ZEGOCLOUD Console -> Project Details.
  static const int appId = 1284551503;
  static const String appSign =
      '40eb6a2908ef7d54cdcd9ff132a2290c4c0f55e13f31e519c96ff926d2cdbc49';

  /// Optional. Needed only for offline push invitations.
  static const String resourceId = 'space_chat_call';

  static bool get isConfigured => appId > 0 && appSign.trim().isNotEmpty;
}

class SpaceCallInvitee {
  final String userId;
  final String userName;

  const SpaceCallInvitee({required this.userId, required this.userName});
}

class SpaceCallKit {
  static final _service = ZegoUIKitPrebuiltCallInvitationService();
  static bool _systemUiReady = false;
  static String? _activeUserId;
  static String? _activeUserName;
  static bool _enterOfflineOnce = false;

  static void attachNavigator() {
    _service.setNavigatorKey(spaceNavigatorKey);
  }

  static void enableSystemCallingUI() {
    if (_systemUiReady) return;
    _systemUiReady = true;
    _service.useSystemCallingUI([ZegoUIKitSignalingPlugin()]);
  }

  static String sanitizeUserId(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final squashed = cleaned
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safe = squashed.isEmpty ? 'space_user' : squashed;
    return safe.substring(0, min(32, safe.length));
  }

  static String sanitizeCallId(String value) =>
      SpaceService.sanitizeCallRoomId(value);

  static ZegoUIKitPrebuiltCallConfig configFor(
      {required bool isVideo, required bool isGroup, String? title}) {
    final config = isGroup
        ? (isVideo
            ? ZegoUIKitPrebuiltCallConfig.groupVideoCall()
            : ZegoUIKitPrebuiltCallConfig.groupVoiceCall())
        : (isVideo
            ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
            : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall());

    config.turnOnCameraWhenJoining = isVideo;
    config.turnOnMicrophoneWhenJoining = true;
    config.useSpeakerWhenJoining = isVideo || isGroup;
    config.background = const _SpaceCallBackground();
    config.topMenuBar.isVisible = true;
    config.bottomMenuBar.hideAutomatically = false;
    config.bottomMenuBar.buttons = isVideo
        ? [
            ZegoCallMenuBarButtonName.toggleMicrophoneButton,
            ZegoCallMenuBarButtonName.switchCameraButton,
            ZegoCallMenuBarButtonName.toggleCameraButton,
            ZegoCallMenuBarButtonName.switchAudioOutputButton,
            ZegoCallMenuBarButtonName.hangUpButton,
            ZegoCallMenuBarButtonName.minimizingButton,
          ]
        : [
            ZegoCallMenuBarButtonName.toggleMicrophoneButton,
            ZegoCallMenuBarButtonName.switchAudioOutputButton,
            ZegoCallMenuBarButtonName.hangUpButton,
            ZegoCallMenuBarButtonName.minimizingButton,
          ];
    config.topMenuBar.title = title ?? 'Space chat';
    config.audioVideoView.showUserNameOnView = true;
    config.audioVideoView.showSoundWavesInAudioMode = true;
    return config;
  }

  static Future<void> initForUser(
      {required String userId, required String userName}) async {
    if (!ZegoCallSecrets.isConfigured) return;

    final safeUserId = sanitizeUserId(userId);
    final safeUserName =
        userName.trim().isEmpty ? 'Space user' : userName.trim();

    if (_service.isInit &&
        _activeUserId == safeUserId &&
        _activeUserName == safeUserName) {
      return;
    }

    if (_service.isInit) {
      await _service.uninit();
    }

    _activeUserId = safeUserId;
    _activeUserName = safeUserName;
    _enterOfflineOnce = false;

    await _service.init(
      appID: ZegoCallSecrets.appId,
      appSign: ZegoCallSecrets.appSign,
      userID: safeUserId,
      userName: safeUserName,
      plugins: [ZegoUIKitSignalingPlugin()],
      invitationEvents: ZegoUIKitPrebuiltCallInvitationEvents(
        onIncomingCallReceived:
            (callID, caller, callType, callees, customData) {
          _showSnack(
              'Входящий звонок от ${caller.name ?? caller.id ?? 'пользователя'}');
        },
        onIncomingCallCanceled: (callID, caller, customData) {
          _showSnack('${caller.name ?? 'Пользователь'} отменил звонок');
        },
        onIncomingCallTimeout: (callID, caller) async {
          await _safeLog(
            ownerId: safeUserId,
            title: caller.name ?? caller.id ?? 'Звонок',
            callType: 'voice',
            status: 'missed',
          );
          _showSnack('Пропущенный звонок от ${caller.name ?? 'пользователя'}');
        },
        onOutgoingCallAccepted: (callID, callee) {
          _showSnack('${callee.name ?? 'Пользователь'} ответил');
        },
        onOutgoingCallDeclined: (callID, callee, customData) async {
          final meta = _decode(customData);
          await _safeLog(
            ownerId: safeUserId,
            title: meta['title'] ?? callee.name ?? 'Звонок',
            callType: meta['callType'] ?? 'voice',
            status: 'missed',
          );
          _showSnack('${callee.name ?? 'Пользователь'} отклонил звонок');
        },
        onOutgoingCallRejectedCauseBusy: (callID, callee, customData) async {
          final meta = _decode(customData);
          await _safeLog(
            ownerId: safeUserId,
            title: meta['title'] ?? callee.name ?? 'Звонок',
            callType: meta['callType'] ?? 'voice',
            status: 'missed',
          );
          _showSnack('${callee.name ?? 'Пользователь'} сейчас занят');
        },
        onOutgoingCallTimeout: (callID, callees, isVideoCall) async {
          final title = callees.isNotEmpty
              ? (callees.first.name ?? callees.first.id ?? 'Звонок')
              : 'Звонок';
          await _safeLog(
            ownerId: safeUserId,
            title: title,
            callType: isVideoCall ? 'video' : 'voice',
            status: 'missed',
          );
          _showSnack('Нет ответа');
        },
        onOutgoingCallCancelButtonPressed: () {
          _showSnack('Звонок отменён');
        },
      ),
    );
  }

  static void enterAcceptedOfflineCall() {
    if (!ZegoCallSecrets.isConfigured || !_service.isInit || _enterOfflineOnce)
      return;
    _enterOfflineOnce = true;
    scheduleMicrotask(_service.enterAcceptedOfflineCall);
  }

  static Future<void> uninit() async {
    if (_service.isInit) {
      await _service.uninit();
    }
    _activeUserId = null;
    _activeUserName = null;
    _enterOfflineOnce = false;
  }

  static Future<bool> startInvitation({
    required String callerId,
    required String callerName,
    required List<SpaceCallInvitee> invitees,
    required bool isVideoCall,
    required String title,
    String? conversationId,
    int timeoutSeconds = 45,
  }) async {
    if (!ZegoCallSecrets.isConfigured) {
      _showSnack('Сначала вставь appId и appSign в lib/zego_config.dart.');
      return false;
    }

    if (invitees.isEmpty) {
      _showSnack('Нет пользователей для звонка.');
      return false;
    }

    await initForUser(userId: callerId, userName: callerName);

    final payload = jsonEncode({
      'title': title,
      'callType': isVideoCall ? 'video' : 'voice',
      'conversationId': conversationId ?? '',
    });

    return _service.send(
      invitees: invitees
          .map((e) => ZegoCallUser(sanitizeUserId(e.userId),
              e.userName.trim().isEmpty ? 'Space user' : e.userName.trim()))
          .toList(),
      isVideoCall: isVideoCall,
      callID: sanitizeCallId(
          'call_${conversationId ?? title}_${DateTime.now().millisecondsSinceEpoch}'),
      customData: payload,
      resourceID: ZegoCallSecrets.resourceId.isEmpty
          ? null
          : ZegoCallSecrets.resourceId,
      notificationTitle: isVideoCall
          ? 'Видеозвонок Space chat'
          : 'Голосовой звонок Space chat',
      notificationMessage: '$callerName звонит тебе',
      timeoutSeconds: timeoutSeconds,
    );
  }

  static Map<String, dynamic> _decode(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    } catch (_) {}
    return const {};
  }

  static Future<void> _safeLog(
      {required String ownerId,
      required String title,
      required String callType,
      required String status}) async {
    try {
      await SpaceService.addCallLog(
        ownerId: ownerId,
        title: title,
        callType: callType,
        status: status,
      );
    } catch (_) {}
  }

  static void _showSnack(String message) {
    final context = spaceNavigatorKey.currentContext;
    if (context != null) {
      showSpaceSnack(context, message);
    }
  }
}

class _SpaceCallBackground extends StatelessWidget {
  const _SpaceCallBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF040714), Color(0xFF0D1536), Color(0xFF071B27)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -30,
            left: -40,
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
            bottom: -20,
            right: -20,
            child: Container(
              width: 200,
              height: 200,
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
