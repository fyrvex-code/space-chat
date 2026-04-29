import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'space_models.dart';

class SpaceService {
  static SupabaseClient get supabase => Supabase.instance.client;
  static FirebaseAuth get auth => FirebaseAuth.instance;

static const Duration _listCacheTtl = Duration(seconds: 8);
static final Map<String, _CacheEntry<List<ContactItem>>> _contactsCache = {};
static final Map<String, _CacheEntry<List<FolderItem>>> _foldersCache = {};
static final Map<String, _CacheEntry<List<ConversationItem>>> _conversationsCache = {};
static final Map<String, _CacheEntry<List<CallLogItem>>> _callLogsCache = {};

static String sanitizeCallRoomId(String value) {
  final cleaned = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
  final squashed = cleaned.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return squashed.isEmpty ? 'space_room' : squashed.substring(0, min(64, squashed.length));
}

static T? _getCached<T>(Map<String, _CacheEntry<T>> store, String key) {
  final current = store[key];
  if (current == null) return null;
  if (DateTime.now().difference(current.createdAt) > _listCacheTtl) {
    store.remove(key);
    return null;
  }
  return current.value;
}

static void _setCached<T>(Map<String, _CacheEntry<T>> store, String key, T value) {
  store[key] = _CacheEntry(value, DateTime.now());
}

static void _clearChatLists({String? ownerId}) {
  if (ownerId == null) {
    _contactsCache.clear();
    _foldersCache.clear();
    _conversationsCache.clear();
    _callLogsCache.clear();
    return;
  }
  _contactsCache.remove(ownerId);
  _foldersCache.remove(ownerId);
  _callLogsCache.remove(ownerId);
  _conversationsCache.removeWhere((key, value) => key.startsWith('$ownerId|'));
}

  static const Set<String> bannedUsernames = {
    'admin',
    'support',
    'creator',
    'spacechat',
    'space_chat',
    'space-chat',
    'moderator',
    'system',
    'official',
    'root',
    'owner',
    'help',
    'security',
    'team',
    'staff',
    'space',
    'chat',
  };

  static String firebaseErrorToText(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Эта почта уже используется.';
      case 'invalid-email':
        return 'Неверная почта.';
      case 'weak-password':
        return 'Слишком слабый пароль.';
      case 'user-not-found':
        return 'Пользователь не найден.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Неверная почта или пароль.';
      case 'too-many-requests':
        return 'Слишком много попыток. Попробуй позже.';
      default:
        return e.message ?? 'Неизвестная ошибка Firebase.';
    }
  }

  static String normalizeUsername(String value) => value.trim().toLowerCase();

  static String _banKey(String value) => normalizeUsername(value).replaceAll(RegExp(r'[_\-.]'), '');

  static String? localUsernameError(String value) {
    final raw = value.trim();
    final username = normalizeUsername(value);
    if (raw.isEmpty) return 'Username обязателен.';
    if (username.length < 3) return 'Минимум 3 символа.';
    if (username.length > 30) return 'Максимум 30 символов.';
    if (raw.contains(' ')) return 'Пробелы запрещены.';
    if (RegExp(r'[а-яА-ЯёЁ]').hasMatch(raw)) return 'Русские буквы нельзя использовать.';
    if (!RegExp(r'^[a-zA-Z._-]+$').hasMatch(raw)) {
      return 'Можно использовать только английские буквы и символы _ - .';
    }
    if (username.startsWith('.') || username.startsWith('_') || username.startsWith('-')) {
      return 'Username не может начинаться с точки, _ или -.';
    }
    if (username.endsWith('.') || username.endsWith('_') || username.endsWith('-')) {
      return 'Username не может заканчиваться точкой, _ или -.';
    }
    if (bannedUsernames.contains(username) || bannedUsernames.contains(_banKey(username))) {
      return 'Этот username использовать нельзя.';
    }
    return null;
  }

  static Future<bool> isUsernameAvailable(String username, {String? excludingUserId}) async {
    final error = localUsernameError(username);
    if (error != null) return false;
    final rows = await supabase.from('profiles').select('id').eq('username', normalizeUsername(username));
    if (rows is! List || rows.isEmpty) return true;
    if (excludingUserId != null) {
      return rows.every((row) => '${row['id']}' == excludingUserId);
    }
    return false;
  }

  static Future<UserProfile?> fetchProfile(String userId) async {
    final row = await supabase.from('profiles').select().eq('id', userId).maybeSingle();
    if (row == null) return null;
    return UserProfile.fromMap(Map<String, dynamic>.from(row));
  }

  static Future<UserProfile> createOrUpdateProfile({
    required User firebaseUser,
    required String fullName,
    required String username,
    required String bio,
    XFile? avatarFile,
  }) async {
    if (fullName.trim().isEmpty) throw Exception('Имя обязательно.');
    final usernameError = localUsernameError(username);
    if (usernameError != null) throw Exception(usernameError);

    final existing = await fetchProfile(firebaseUser.uid);
    final normalized = normalizeUsername(username);
    final taken = await isUsernameAvailable(normalized, excludingUserId: firebaseUser.uid);
    if (!taken) throw Exception('Этот username уже занят.');

    String? avatarUrl = existing?.avatarUrl;
    if (avatarFile != null) {
      try {
        final bytes = await avatarFile.readAsBytes();
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final ext = avatarFile.path.split('.').last.toLowerCase();
        final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
        final contentType = switch (safeExt) {
          'png' => 'image/png',
          'webp' => 'image/webp',
          _ => 'image/jpeg',
        };
        final path = 'public/${firebaseUser.uid}/avatar_$stamp.$safeExt';
        await supabase.storage.from('avatars').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType, upsert: true, cacheControl: '3600'),
            );
        avatarUrl = '${supabase.storage.from('avatars').getPublicUrl(path)}?v=$stamp';
      } catch (e) {
        throw Exception('Не удалось загрузить аватар. Проверь bucket avatars и storage policy. $e');
      }
    }

    try {
      final row = await supabase
          .from('profiles')
          .upsert({
            'id': firebaseUser.uid,
            'email': firebaseUser.email ?? '',
            'full_name': fullName.trim(),
            'username': normalized,
            'avatar_url': avatarUrl,
            'bio': bio.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();
      final saved = UserProfile.fromMap(Map<String, dynamic>.from(row));
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        return saved.copyWith(avatarUrl: avatarUrl);
      }
      return saved;
    } catch (e) {
      throw Exception('Не удалось сохранить профиль. Проверь таблицу profiles и SQL schema. $e');
    }
  }

  static Future<List<UserProfile>> searchUsers(String query, {int limit = 20}) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    final rows = await supabase.from('profiles').select().ilike('username', '%$q%').limit(limit);
    return (rows as List).map((e) => UserProfile.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  static Future<UserProfile?> findUserByUsername(String username) async {
    final row = await supabase.from('profiles').select().eq('username', normalizeUsername(username)).maybeSingle();
    if (row == null) return null;
    return UserProfile.fromMap(Map<String, dynamic>.from(row));
  }

  static Future<void> addContact({
    required String ownerId,
    required String customName,
    required String username,
  }) async {
    final found = await findUserByUsername(username);
    if (found == null) throw Exception('Пользователь с таким username не найден.');
    if (found.id == ownerId) throw Exception('Себя добавить нельзя.');
    await supabase.from('contacts').upsert({
      'owner_id': ownerId,
      'contact_user_id': found.id,
      'custom_name': customName.trim(),
      'username_snapshot': found.username,
      'created_at': DateTime.now().toIso8601String(),
    }, onConflict: 'owner_id,contact_user_id');
    _clearChatLists(ownerId: ownerId);
  }


static Future<List<ContactItem>> getContacts(String ownerId) async {
  final cached = _getCached(_contactsCache, ownerId);
  if (cached != null) return cached;

  final rows = await supabase.from('contacts').select().eq('owner_id', ownerId).order('created_at');
  if (rows is! List || rows.isEmpty) {
    _setCached(_contactsCache, ownerId, const []);
    return const [];
  }
  final contactUserIds = rows.map((e) => '${e['contact_user_id']}').toSet().toList();
  final profileRows = await supabase.from('profiles').select().inFilter('id', contactUserIds);
  final profiles = {
    for (final row in profileRows as List)
      '${row['id']}': UserProfile.fromMap(Map<String, dynamic>.from(row)),
  };
  final items = rows
      .map((e) {
        final profile = profiles['${e['contact_user_id']}'];
        if (profile == null) return null;
        return ContactItem(
          id: '${e['id']}',
          customName: '${e['custom_name'] ?? ''}',
          profile: profile,
        );
      })
      .whereType<ContactItem>()
      .toList(growable: false);
  _setCached(_contactsCache, ownerId, items);
  return items;
}

static Future<List<FolderItem>> getFolders(String ownerId) async {
    final cached = _getCached(_foldersCache, ownerId);
    if (cached != null) return cached;

    final rows = await supabase.from('chat_folders').select().eq('owner_id', ownerId).order('created_at');
    final items = (rows as List)
        .map((e) => FolderItem(id: '${e['id']}', title: '${e['title'] ?? ''}'))
        .toList(growable: false);
    _setCached(_foldersCache, ownerId, items);
    return items;
  }

  static Future<void> createFolder({required String ownerId, required String title}) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw Exception('Название папки обязательно.');
    final current = await getFolders(ownerId);
    if (current.length >= 15) throw Exception('Можно создать максимум 15 папок.');
    await supabase.from('chat_folders').insert({'owner_id': ownerId, 'title': trimmed});
    _clearChatLists(ownerId: ownerId);
  }

  static Future<void> deleteFolder({required String ownerId, required String folderId}) async {
    await supabase.from('folder_items').delete().eq('owner_id', ownerId).eq('folder_id', folderId);
    await supabase.from('chat_folders').delete().eq('owner_id', ownerId).eq('id', folderId);
    _clearChatLists(ownerId: ownerId);
  }

  static String _directKey(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids.first}__${ids.last}';
  }

  static Future<String> getOrCreateDirectConversation({
    required String currentUserId,
    required String peerUserId,
  }) async {
    final directKey = _directKey(currentUserId, peerUserId);
    final existing = await supabase.from('conversations').select('id').eq('direct_key', directKey).maybeSingle();
    if (existing != null) return '${existing['id']}';

    final created = await supabase
        .from('conversations')
        .insert({
          'type': 'direct',
          'direct_key': directKey,
          'created_by': currentUserId,
        })
        .select('id')
        .single();

    final conversationId = '${created['id']}';
    await supabase.from('conversation_members').insert([
      {
        'conversation_id': conversationId,
        'user_id': currentUserId,
        'role': 'owner',
      },
      {
        'conversation_id': conversationId,
        'user_id': peerUserId,
        'role': 'member',
      },
    ]);
    _conversationsCache.clear();
    return conversationId;
  }


static Future<List<ConversationItem>> getConversations({required String ownerId, String? folderId}) async {
  final cacheKey = '$ownerId|${folderId ?? 'all'}';
  final cached = _getCached(_conversationsCache, cacheKey);
  if (cached != null) return cached;

  final memberRows = await supabase.from('conversation_members').select('conversation_id, role').eq('user_id', ownerId);
  if (memberRows is! List || memberRows.isEmpty) {
    _setCached(_conversationsCache, cacheKey, const []);
    return const [];
  }

  final memberships = memberRows
      .map((row) => {'conversation_id': '${row['conversation_id']}', 'role': '${row['role'] ?? 'member'}'})
      .toList(growable: false);
  final ids = memberships.map((e) => e['conversation_id']!).toList(growable: false);

  final hiddenRows = await supabase.from('hidden_chats').select('conversation_id').eq('owner_id', ownerId);
  final hiddenIds = (hiddenRows as List).map((e) => '${e['conversation_id']}').toSet();

  final pinnedRows = await supabase.from('conversation_pins').select('conversation_id').eq('owner_id', ownerId);
  final pinnedIds = (pinnedRows as List).map((e) => '${e['conversation_id']}').toSet();

  Set<String>? folderConversationIds;
  if (folderId != null) {
    final folderRows = await supabase.from('folder_items').select('conversation_id').eq('owner_id', ownerId).eq('folder_id', folderId);
    folderConversationIds = (folderRows as List).map((e) => '${e['conversation_id']}').toSet();
  }

  final convRows = await supabase.from('conversations').select('id, type, title, avatar_url, invite_link, created_at').inFilter('id', ids);
  final convMap = {
    for (final row in convRows as List) '${row['id']}': Map<String, dynamic>.from(row),
  };

  final peerRows = await supabase
      .from('conversation_members')
      .select('conversation_id, user_id')
      .inFilter('conversation_id', ids)
      .neq('user_id', ownerId);
  final directPeerByConversation = <String, String>{};
  final peerIds = <String>{};
  for (final row in peerRows as List) {
    final cId = '${row['conversation_id']}';
    final peerId = '${row['user_id']}';
    directPeerByConversation.putIfAbsent(cId, () => peerId);
    peerIds.add(peerId);
  }

  final profiles = <String, UserProfile>{};
  if (peerIds.isNotEmpty) {
    final rows = await supabase.from('profiles').select().inFilter('id', peerIds.toList());
    for (final row in rows as List) {
      final profile = UserProfile.fromMap(Map<String, dynamic>.from(row));
      profiles[profile.id] = profile;
    }
  }

  final previewLimit = max(60, min(ids.length * 4, 320));
  final messageRows = await supabase
      .from('messages')
      .select('conversation_id, body, created_at')
      .inFilter('conversation_id', ids)
      .order('created_at', ascending: false)
      .limit(previewLimit);
  final lastMessageByConversation = <String, Map<String, dynamic>>{};
  for (final row in messageRows as List) {
    lastMessageByConversation.putIfAbsent('${row['conversation_id']}', () => Map<String, dynamic>.from(row));
  }

  final result = <ConversationItem>[];
  for (final membership in memberships) {
    final cId = membership['conversation_id']!;
    if (hiddenIds.contains(cId)) continue;
    if (folderConversationIds != null && !folderConversationIds.contains(cId)) continue;
    final conv = convMap[cId];
    if (conv == null) continue;

    final type = '${conv['type'] ?? 'direct'}';
    String title = '${conv['title'] ?? ''}'.trim();
    String? avatarUrl = conv['avatar_url']?.toString();
    String? directUserId;
    String? subtitle;

    if (type == 'direct') {
      directUserId = directPeerByConversation[cId];
      final peer = profiles[directUserId];
      if (peer != null) {
        title = peer.fullName;
        avatarUrl = peer.avatarUrl;
        subtitle = '@${peer.username}';
      }
    }

    final lastMessage = lastMessageByConversation[cId];
    final lastMessageAt = lastMessage != null
        ? DateTime.tryParse('${lastMessage['created_at']}')
        : DateTime.tryParse('${conv['created_at']}');
    if (lastMessage != null) {
      subtitle = '${lastMessage['body'] ?? ''}'.trim();
    }

    result.add(
      ConversationItem(
        id: cId,
        type: type,
        title: title.isEmpty
            ? (type == 'group'
                ? 'Новая группа'
                : type == 'channel'
                    ? 'Новый канал'
                    : 'Новый чат')
            : title,
        avatarUrl: avatarUrl,
        subtitle: subtitle,
        inviteLink: conv['invite_link']?.toString(),
        pinned: pinnedIds.contains(cId),
        directUserId: directUserId,
        role: membership['role']!,
        lastMessageAt: lastMessageAt,
      ),
    );
  }

  result.sort((a, b) {
    if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
    final ad = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bd = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bd.compareTo(ad);
  });
  final frozen = List<ConversationItem>.unmodifiable(result);
  _setCached(_conversationsCache, cacheKey, frozen);
  return frozen;
}

static Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;
    await supabase.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'body': trimmed,
    });
    _conversationsCache.clear();
  }

  static Stream<List<MessageItem>> messagesStream(String conversationId) {
    return supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .map((rows) => rows.map((e) => MessageItem.fromMap(Map<String, dynamic>.from(e))).toList());
  }

  static Future<List<MessageItem>> searchMessages({required String conversationId, required String query}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final rows = await supabase
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .ilike('body', '%$q%')
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List).map((e) => MessageItem.fromMap(Map<String, dynamic>.from(e))).toList();
  }

  static Future<void> pinChat({required String ownerId, required String conversationId}) async {
    final existing = await supabase.from('conversation_pins').select('conversation_id').eq('owner_id', ownerId);
    final current = (existing as List).map((e) => '${e['conversation_id']}').toSet();
    if (!current.contains(conversationId) && current.length >= 5) {
      throw Exception('Можно закрепить максимум 5 чатов.');
    }
    await supabase.from('conversation_pins').upsert({
      'owner_id': ownerId,
      'conversation_id': conversationId,
    }, onConflict: 'owner_id,conversation_id');
    _conversationsCache.clear();
  }

  static Future<void> unpinChat({required String ownerId, required String conversationId}) async {
    await supabase.from('conversation_pins').delete().eq('owner_id', ownerId).eq('conversation_id', conversationId);
    _conversationsCache.clear();
  }

  static Future<void> addChatToFolder({required String ownerId, required String conversationId, required String folderId}) async {
    await supabase.from('folder_items').upsert({
      'owner_id': ownerId,
      'conversation_id': conversationId,
      'folder_id': folderId,
      'created_at': DateTime.now().toIso8601String(),
    }, onConflict: 'owner_id,folder_id,conversation_id');
    _conversationsCache.clear();
  }

  static Future<void> removeChatFromFolder({required String ownerId, required String conversationId, required String folderId}) async {
    await supabase.from('folder_items').delete().eq('owner_id', ownerId).eq('conversation_id', conversationId).eq('folder_id', folderId);
    _conversationsCache.clear();
  }

  static Future<List<String>> folderAssignments({required String ownerId, required String conversationId}) async {
    final rows = await supabase.from('folder_items').select('folder_id').eq('owner_id', ownerId).eq('conversation_id', conversationId);
    return (rows as List).map((e) => '${e['folder_id']}').toList();
  }

  static Future<void> hideChat({required String ownerId, required String conversationId}) async {
    await supabase.from('hidden_chats').upsert({
      'owner_id': ownerId,
      'conversation_id': conversationId,
    }, onConflict: 'owner_id,conversation_id');
    _conversationsCache.clear();
  }

  static Future<void> blockUser({required String ownerId, required String blockedUserId}) async {
    await supabase.from('blocked_users').upsert({
      'owner_id': ownerId,
      'blocked_user_id': blockedUserId,
    }, onConflict: 'owner_id,blocked_user_id');
    _clearChatLists(ownerId: ownerId);
  }

  static Future<String> createGroup({required String ownerId, required String title, required List<String> memberIds}) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw Exception('Название группы обязательно.');
    final created = await supabase
        .from('conversations')
        .insert({'type': 'group', 'title': trimmed, 'created_by': ownerId})
        .select('id')
        .single();
    final conversationId = '${created['id']}';
    final rows = <Map<String, dynamic>>[
      {'conversation_id': conversationId, 'user_id': ownerId, 'role': 'owner'},
    ];
    for (final id in memberIds.toSet()) {
      if (id == ownerId) continue;
      rows.add({'conversation_id': conversationId, 'user_id': id, 'role': 'member'});
    }
    await supabase.from('conversation_members').insert(rows);
    _conversationsCache.clear();
    return conversationId;
  }

  static Future<String> createPrivateChannel({
    required String ownerId,
    required String title,
    required List<String> memberIds,
    required List<String> adminIds,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw Exception('Название канала обязательно.');
    final link = 'spacechat://${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
    final created = await supabase
        .from('conversations')
        .insert({'type': 'channel', 'title': trimmed, 'invite_link': link, 'created_by': ownerId})
        .select('id')
        .single();
    final conversationId = '${created['id']}';
    final rows = <Map<String, dynamic>>[
      {'conversation_id': conversationId, 'user_id': ownerId, 'role': 'owner'},
    ];
    for (final id in memberIds.toSet()) {
      if (id == ownerId) continue;
      rows.add({
        'conversation_id': conversationId,
        'user_id': id,
        'role': adminIds.contains(id) ? 'admin' : 'member',
      });
    }
    await supabase.from('conversation_members').insert(rows);
    _conversationsCache.clear();
    return conversationId;
  }

  static Future<List<UserProfile>> membersForConversation(String conversationId) async {
    final memberRows = await supabase.from('conversation_members').select('user_id').eq('conversation_id', conversationId);
    final ids = (memberRows as List).map((e) => '${e['user_id']}').toList();
    if (ids.isEmpty) return [];
    final rows = await supabase.from('profiles').select().inFilter('id', ids);
    return (rows as List).map((e) => UserProfile.fromMap(Map<String, dynamic>.from(e))).toList();
  }



  static Future<void> deleteMessage({required String messageId}) async {
    await supabase.from('messages').delete().eq('id', messageId);
    _conversationsCache.clear();
  }

  static Future<void> addCallLog({required String ownerId, required String title, required String callType, required String status}) async {
    await supabase.from('call_logs').insert({
      'owner_id': ownerId,
      'title': title,
      'call_type': callType,
      'status': status,
    });
    _callLogsCache.remove(ownerId);
  }


  static Future<List<CallLogItem>> getCallLogs(String ownerId) async {
    final cached = _getCached(_callLogsCache, ownerId);
    if (cached != null) return cached;
    final rows = await supabase.from('call_logs').select().eq('owner_id', ownerId).order('created_at', ascending: false).limit(60);
    final items = (rows as List).map((e) => CallLogItem.fromMap(Map<String, dynamic>.from(e))).toList(growable: false);
    _setCached(_callLogsCache, ownerId, items);
    return items;
  }
}

class _CacheEntry<T> {
  final T value;
  final DateTime createdAt;

  const _CacheEntry(this.value, this.createdAt);
}

