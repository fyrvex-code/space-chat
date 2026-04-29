class UserProfile {
  final String id;
  final String email;
  final String fullName;
  final String username;
  final String? avatarUrl;
  final String bio;

  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.username,
    required this.avatarUrl,
    required this.bio,
  });

  bool get isComplete => fullName.trim().isNotEmpty && username.trim().isNotEmpty;

  String get displayHandle => '@$username';

  UserProfile copyWith({
    String? fullName,
    String? username,
    String? avatarUrl,
    String? bio,
  }) {
    return UserProfile(
      id: id,
      email: email,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
    );
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: '${map['id']}',
      email: '${map['email'] ?? ''}',
      fullName: '${map['full_name'] ?? ''}',
      username: '${map['username'] ?? ''}',
      avatarUrl: map['avatar_url']?.toString(),
      bio: '${map['bio'] ?? ''}',
    );
  }
}

class ContactItem {
  final String id;
  final String customName;
  final UserProfile profile;

  const ContactItem({
    required this.id,
    required this.customName,
    required this.profile,
  });

  String get title => customName.trim().isNotEmpty ? customName.trim() : profile.fullName;
}

class FolderItem {
  final String id;
  final String title;

  const FolderItem({required this.id, required this.title});
}

class ConversationItem {
  final String id;
  final String type;
  final String title;
  final String? avatarUrl;
  final String? subtitle;
  final String? inviteLink;
  final bool pinned;
  final String? directUserId;
  final String role;
  final DateTime? lastMessageAt;

  const ConversationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.avatarUrl,
    required this.subtitle,
    required this.inviteLink,
    required this.pinned,
    required this.directUserId,
    required this.role,
    required this.lastMessageAt,
  });

  ConversationItem copyWith({
    bool? pinned,
    String? subtitle,
    DateTime? lastMessageAt,
  }) {
    return ConversationItem(
      id: id,
      type: type,
      title: title,
      avatarUrl: avatarUrl,
      subtitle: subtitle ?? this.subtitle,
      inviteLink: inviteLink,
      pinned: pinned ?? this.pinned,
      directUserId: directUserId,
      role: role,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }
}

class MessageItem {
  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  const MessageItem({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.createdAt,
  });

  factory MessageItem.fromMap(Map<String, dynamic> map) {
    return MessageItem(
      id: '${map['id']}',
      conversationId: '${map['conversation_id']}',
      senderId: '${map['sender_id']}',
      body: '${map['body'] ?? ''}',
      createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
    );
  }
}

class CallLogItem {
  final String id;
  final String title;
  final String callType;
  final String status;
  final DateTime createdAt;

  const CallLogItem({
    required this.id,
    required this.title,
    required this.callType,
    required this.status,
    required this.createdAt,
  });

  bool get isMissed => status == 'missed';
  bool get isVideo => callType == 'video';
  bool get isGroup => callType == 'group';

  factory CallLogItem.fromMap(Map<String, dynamic> map) {
    return CallLogItem(
      id: '${map['id']}',
      title: '${map['title'] ?? ''}',
      callType: '${map['call_type'] ?? 'voice'}',
      status: '${map['status'] ?? 'done'}',
      createdAt: DateTime.tryParse('${map['created_at']}') ?? DateTime.now(),
    );
  }
}
