import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'calls_module.dart';
import 'zego_config.dart';
import 'space_core.dart';
import 'space_models.dart';
import 'space_service.dart';

class ChatsHubPage extends StatefulWidget {
  final User currentUser;
  final UserProfile currentProfile;
  final ValueChanged<UserProfile>? onProfileUpdated;

  const ChatsHubPage({
    super.key,
    required this.currentUser,
    required this.currentProfile,
    this.onProfileUpdated,
  });

  @override
  State<ChatsHubPage> createState() => ChatsHubPageState();
}

class ChatsHubPageState extends State<ChatsHubPage> {
  bool _loading = true;
  bool _searchMode = false;
  String _selectedFolderId;
  final _searchController = TextEditingController();
  List<FolderItem> _folders = const [];
  List<ConversationItem> _conversations = const [];
  List<UserProfile> _userSearch = const [];
  Set<String> _mutedIds = const <String>{};
  Timer? _searchDebounce;

  ChatsHubPageState() : _selectedFolderId = 'all';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load(showLoader: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> reload() => _load(showLoader: false);

  Future<void> _load({bool showLoader = false}) async {
    if (showLoader && mounted) {
      setState(() => _loading = _conversations.isEmpty);
    }
    unawaited(_refreshFolders());
    unawaited(_refreshMutedStates());
    await _refreshConversations(showLoader: showLoader);
  }

  Future<void> _refreshMutedStates() async {
    try {
      final muted = await SpaceLocalPrefs.mutedChats();
      if (!mounted) return;
      setState(() => _mutedIds = muted);
    } catch (_) {}
  }

  Future<void> _refreshFolders() async {
    try {
      final folders = await SpaceService.getFolders(widget.currentUser.uid);
      if (!mounted) return;
      setState(() => _folders = folders);
    } catch (_) {}
  }

  Future<void> _refreshConversations({bool showLoader = false}) async {
    if (showLoader && mounted && _conversations.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      final conversations = await SpaceService.getConversations(
        ownerId: widget.currentUser.uid,
        folderId: _selectedFolderId == 'all' ? null : _selectedFolderId,
      );
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
      });
    } catch (e) {
      if (mounted) showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final q = _searchController.text.trim();
    if (!_searchMode) return;
    if (q.isEmpty) {
      setState(() => _userSearch = const []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final rows = await SpaceService.searchUsers(q);
      if (!mounted) return;
      setState(() => _userSearch = rows.where((e) => e.id != widget.currentUser.uid).toList());
    });
  }

  Future<void> _openDirectWith(UserProfile profile) async {
    final conversationId = await SpaceService.getOrCreateDirectConversation(
      currentUserId: widget.currentUser.uid,
      peerUserId: profile.id,
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomPage(
          currentUser: widget.currentUser,
          currentProfile: widget.currentProfile,
          conversationId: conversationId,
          title: profile.fullName,
          avatarUrl: profile.avatarUrl,
          subtitle: '@${profile.username}',
          directUserId: profile.id,
          type: 'direct',
          inviteLink: null,
        ),
      ),
    );
    await _load(showLoader: false);
  }

  Future<void> _openConversation(ConversationItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomPage(
          currentUser: widget.currentUser,
          currentProfile: widget.currentProfile,
          conversationId: item.id,
          title: item.title,
          avatarUrl: item.avatarUrl,
          subtitle: item.subtitle,
          directUserId: item.directUserId,
          type: item.type,
          inviteLink: item.inviteLink,
        ),
      ),
    );
    await _load(showLoader: false);
  }

  Future<void> _showCreateSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _CreateConversationSheet(
          currentUserId: widget.currentUser.uid,
          onCreated: () async {
            Navigator.pop(context);
            await _load(showLoader: false);
          },
        );
      },
    );
  }

  Future<void> _showFolderManager() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => FolderManagerSheet(ownerId: widget.currentUser.uid, onChanged: () => _load(showLoader: false)),
    );
  }

  Future<void> _showChatActions(ConversationItem item) async {
    final folders = await SpaceService.getFolders(widget.currentUser.uid);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatActionsSheet(
        item: item,
        ownerId: widget.currentUser.uid,
        folders: folders,
        isMuted: _mutedIds.contains(item.id),
        onChanged: () => _load(showLoader: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredChats = _searchMode
        ? _conversations.where((e) {
            final query = _searchController.text.trim().toLowerCase();
            if (query.isEmpty) return true;
            return e.title.toLowerCase().contains(query) || (e.subtitle ?? '').toLowerCase().contains(query);
          }).toList()
        : _conversations;

    return SpaceScaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(showLoader: false),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _searchMode ? 'Поиск' : 'Чаты',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () {
                      setState(() {
                        _searchMode = !_searchMode;
                        _searchController.clear();
                        _userSearch = const [];
                      });
                    },
                    icon: Icon(_searchMode ? Icons.close_rounded : Icons.search_rounded),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _showCreateSheet,
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_searchMode) ...[
                GlassCard(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Найти по username или названию чата',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          SpacePill(
                            label: 'Все',
                            selected: _selectedFolderId == 'all',
                            onTap: () {
                              setState(() => _selectedFolderId = 'all');
                              _refreshConversations(showLoader: false);
                            },
                          ),
                          for (final folder in _folders)
                            SpacePill(
                              label: folder.title,
                              selected: _selectedFolderId == folder.id,
                              onTap: () {
                                setState(() => _selectedFolderId = folder.id);
                                _refreshConversations(showLoader: false);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _showFolderManager,
                    icon: const Icon(Icons.folder_open_rounded),
                    tooltip: 'Папки',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_searchMode && _searchController.text.trim().isNotEmpty) ...[
                if (_userSearch.isNotEmpty) ...[
                  const _SearchBlockTitle(title: 'Люди'),
                  const SizedBox(height: 10),
                  for (final profile in _userSearch)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _UserSearchTile(profile: profile, onTap: () => _openDirectWith(profile)),
                    ),
                  const SizedBox(height: 16),
                ],
                const _SearchBlockTitle(title: 'Чаты'),
                const SizedBox(height: 10),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filteredChats.isEmpty)
                GlassCard(
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      Container(
                        width: 62,
                        height: 62,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.forum_rounded, size: 30),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Чатов пока нет',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Открой поиск сверху, найди пользователя по username или создай группу / канал через плюс.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: SpacePalette.sub(context), height: 1.45),
                      ),
                    ],
                  ),
                )
              else
                ...filteredChats.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ChatPreviewTile(
                      item: item,
                      isMuted: _mutedIds.contains(item.id),
                      onTap: () => _openConversation(item),
                      onLongPress: () => _showChatActions(item),
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

class ContactsPage extends StatefulWidget {
  final User currentUser;
  final UserProfile currentProfile;
  final VoidCallback? onConversationChanged;

  const ContactsPage({
    super.key,
    required this.currentUser,
    required this.currentProfile,
    this.onConversationChanged,
  });

  @override
  State<ContactsPage> createState() => ContactsPageState();
}

class ContactsPageState extends State<ContactsPage> {
  bool _loading = true;
  List<ContactItem> _contacts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await SpaceService.getContacts(widget.currentUser.uid);
      if (!mounted) return;
      setState(() => _contacts = items);
    } catch (e) {
      if (mounted) showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addContact() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddContactSheet(ownerId: widget.currentUser.uid, onSaved: _load),
    );
  }

  Future<void> _openChat(ContactItem item) async {
    final conversationId = await SpaceService.getOrCreateDirectConversation(
      currentUserId: widget.currentUser.uid,
      peerUserId: item.profile.id,
    );
    widget.onConversationChanged?.call();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomPage(
          currentUser: widget.currentUser,
          currentProfile: widget.currentProfile,
          conversationId: conversationId,
          title: item.title,
          avatarUrl: item.profile.avatarUrl,
          subtitle: '@${item.profile.username}',
          directUserId: item.profile.id,
          type: 'direct',
          inviteLink: null,
        ),
      ),
    );
    widget.onConversationChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContact,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Добавить'),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
            children: [
              SpaceSectionTitle(
                title: 'Контакты',
                subtitle: 'Люди, которых ты добавил по username.',
                trailing: IconButton.filledTonal(onPressed: _addContact, icon: const Icon(Icons.add_rounded)),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_contacts.isEmpty)
                GlassCard(
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.people_alt_rounded, size: 30),
                      ),
                      const SizedBox(height: 16),
                      Text('Контактов пока нет', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text('Нажми плюс и добавь человека по username.', style: TextStyle(color: SpacePalette.sub(context))),
                    ],
                  ),
                )
              else
                ..._contacts.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () => _openChat(item),
                        child: Row(
                          children: [
                            SpaceAvatar(title: item.title, imageUrl: item.profile.avatarUrl, radius: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text('@${item.profile.username}', style: TextStyle(color: SpacePalette.sub(context))),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _openChat(item),
                              icon: const Icon(Icons.chat_bubble_rounded),
                            ),
                          ],
                        ),
                      ),
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

class ChatRoomPage extends StatefulWidget {
  final User currentUser;
  final UserProfile currentProfile;
  final String conversationId;
  final String title;
  final String? avatarUrl;
  final String? subtitle;
  final String? directUserId;
  final String type;
  final String? inviteLink;

  const ChatRoomPage({
    super.key,
    required this.currentUser,
    required this.currentProfile,
    required this.conversationId,
    required this.title,
    required this.avatarUrl,
    required this.subtitle,
    required this.directUserId,
    required this.type,
    required this.inviteLink,
  });

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  StreamSubscription<List<MessageItem>>? _sub;
  Timer? _draftDebounce;
  List<MessageItem> _messages = const [];

  @override
  void initState() {
    super.initState();
    _messageController.text = SpaceLocalPrefs.draftFor(widget.conversationId);
    _messageController.addListener(_persistDraft);
    _sub = SpaceService.messagesStream(widget.conversationId).listen((items) {
      if (!mounted) return;
      setState(() => _messages = items);
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _draftDebounce?.cancel();
    _messageController.removeListener(_persistDraft);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _persistDraft() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 250), () {
      SpaceLocalPrefs.setDraft(widget.conversationId, _messageController.text);
    });
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();
    await SpaceLocalPrefs.clearDraft(widget.conversationId);
    await SpaceService.sendMessage(
      conversationId: widget.conversationId,
      senderId: widget.currentUser.uid,
      body: text,
    );
    _jumpToBottom();
  }

  Future<void> _showSearch() async {
    final controller = TextEditingController();
    List<MessageItem> results = [];
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            Future<void> runSearch() async {
              results = await SpaceService.searchMessages(conversationId: widget.conversationId, query: controller.text);
              setSheet(() {});
            }

            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 14, left: 14, right: 14, top: 14),
              child: GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      onSubmitted: (_) => runSearch(),
                      decoration: InputDecoration(
                        labelText: 'Найти текст в чате',
                        suffixIcon: IconButton(onPressed: runSearch, icon: const Icon(Icons.search_rounded)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (results.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Совпадений пока нет', style: TextStyle(color: SpacePalette.sub(context))),
                      )
                    else
                      SizedBox(
                        height: 280,
                        child: ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final message = results[index];
                            return ListTile(
                              title: Text(message.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(message.createdAt.toLocal().toString().substring(0, 16)),
                            );
                          },
                        ),
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

  Future<void> _showFolders() async {
    final folders = await SpaceService.getFolders(widget.currentUser.uid);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => FolderPickerSheet(
        ownerId: widget.currentUser.uid,
        conversationId: widget.conversationId,
        folders: folders,
      ),
    );
  }

  Future<void> _startCall(String kind) async {
    final isVideo = kind == 'video';
    if (widget.type == 'direct' && widget.directUserId != null) {
      await startSpaceChatInvitation(
        context: context,
        currentUser: widget.currentUser,
        currentProfile: widget.currentProfile,
        title: widget.title,
        conversationId: widget.conversationId,
        isVideo: isVideo,
        invitees: [
          SpaceCallInvitee(userId: widget.directUserId!, userName: widget.title),
        ],
      );
      return;
    }

    final members = await SpaceService.membersForConversation(widget.conversationId);
    final invitees = members
        .where((member) => member.id != widget.currentUser.uid)
        .map((member) => SpaceCallInvitee(userId: member.id, userName: member.fullName))
        .toList();

    if (!mounted) return;
    if (invitees.isEmpty) {
      showSpaceSnack(context, 'Некого приглашать в звонок.');
      return;
    }

    await startSpaceChatInvitation(
      context: context,
      currentUser: widget.currentUser,
      currentProfile: widget.currentProfile,
      title: widget.title,
      conversationId: widget.conversationId,
      isVideo: isVideo,
      invitees: invitees,
    );
  }

  Future<void> _showMessageActions(MessageItem message) async {
    final mine = message.senderId == widget.currentUser.uid;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(14),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetAction(
                icon: Icons.copy_rounded,
                title: 'Копировать текст',
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: message.body));
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  showSpaceSnack(context, 'Текст скопирован.');
                },
              ),
              if (mine)
                _SheetAction(
                  icon: Icons.delete_outline_rounded,
                  title: 'Удалить у всех',
                  onTap: () async {
                    await SpaceService.deleteMessage(messageId: message.id);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    showSpaceSnack(context, 'Сообщение удалено.');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SpaceScaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            SpaceAvatar(title: widget.title, imageUrl: widget.avatarUrl, radius: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  if (widget.subtitle != null)
                    Text(widget.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: SpacePalette.sub(context))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: () => _startCall('voice'), icon: const Icon(Icons.call_rounded)),
          IconButton(onPressed: () => _startCall('video'), icon: const Icon(Icons.videocam_rounded)),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'search') {
                _showSearch();
              } else if (value == 'folder') {
                _showFolders();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'search', child: Text('Найти в чате')),
              PopupMenuItem(value: 'folder', child: Text('Добавить в папку')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: GlassCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.forum_rounded, size: 40),
                          const SizedBox(height: 12),
                          Text('Сообщений пока нет', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Text('Напиши первое сообщение. Старые будут сверху, новые — внизу.', style: TextStyle(color: SpacePalette.sub(context))),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final mine = message.senderId == widget.currentUser.uid;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                            child: InkWell(
                              onLongPress: () => _showMessageActions(message),
                              borderRadius: BorderRadius.circular(22),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  gradient: mine
                                      ? const LinearGradient(colors: [SpacePalette.indigo, SpacePalette.cyan])
                                      : null,
                                  color: mine ? null : SpacePalette.cardStrong(context),
                                  border: mine ? null : Border.all(color: SpacePalette.stroke(context)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message.body,
                                      style: TextStyle(
                                        color: mine ? Colors.white : SpacePalette.text(context),
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _timeLabel(message.createdAt),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: mine ? Colors.white.withOpacity(0.76) : SpacePalette.sub(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: GlassCard(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                borderRadius: BorderRadius.circular(28),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          hintText: 'Сообщение',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: _send,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [SpacePalette.indigo, SpacePalette.cyan]),
                        ),
                        child: const Icon(Icons.send_rounded, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _timeLabel(DateTime time) {
  final hh = time.hour.toString().padLeft(2, '0');
  final mm = time.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

class ChatPreviewTile extends StatelessWidget {
  final ConversationItem item;
  final bool isMuted;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ChatPreviewTile({
    super.key,
    required this.item,
    required this.isMuted,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (item.type) {
      'group' => Icons.groups_rounded,
      'channel' => Icons.campaign_rounded,
      _ => Icons.person_rounded,
    };
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(
          children: [
            Stack(
              children: [
                SpaceAvatar(title: item.title, imageUrl: item.avatarUrl, radius: 27),
                if (item.type != 'direct')
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: SpacePalette.cardStrong(context),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: SpacePalette.stroke(context)),
                      ),
                      child: Icon(icon, size: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      if (isMuted)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.notifications_off_rounded, size: 16, color: SpacePalette.sub(context)),
                        ),
                      if (item.pinned) const Icon(Icons.push_pin_rounded, size: 16),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.subtitle?.isNotEmpty == true ? item.subtitle! : 'Новый диалог',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: SpacePalette.sub(context), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              item.lastMessageAt != null ? _timeLabel(item.lastMessageAt!) : '',
              style: TextStyle(fontSize: 11, color: SpacePalette.sub(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class AddContactSheet extends StatefulWidget {
  final String ownerId;
  final Future<void> Function() onSaved;

  const AddContactSheet({super.key, required this.ownerId, required this.onSaved});

  @override
  State<AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<AddContactSheet> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _found = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_checkUser);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _nameController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _checkUser() {
    _debounce?.cancel();
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      setState(() => _found = false);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final user = await SpaceService.findUserByUsername(username);
      if (!mounted) return;
      setState(() => _found = user != null && user.id != widget.ownerId);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_found) {
      showSpaceSnack(context, 'Сначала найди существующий username.');
      return;
    }
    setState(() => _saving = true);
    try {
      await SpaceService.addContact(
        ownerId: widget.ownerId,
        customName: _nameController.text,
        username: _usernameController.text,
      );
      await widget.onSaved();
      if (!mounted) return;
      Navigator.pop(context);
      showSpaceSnack(context, 'Контакт сохранён.');
    } catch (e) {
      showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 14, right: 14, top: 14, bottom: MediaQuery.of(context).viewInsets.bottom + 14),
      child: GlassCard(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios_new_rounded)),
                  const SizedBox(width: 4),
                  Text('Добавить контакт', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Имя для контакта'),
                validator: (value) => value == null || value.trim().isEmpty ? 'Имя обязательно.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                  suffixIcon: _usernameController.text.trim().isEmpty
                      ? null
                      : Icon(_found ? Icons.check_circle_rounded : Icons.cancel_rounded, color: _found ? SpacePalette.emerald : SpacePalette.red),
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Username обязателен.' : null,
              ),
              const SizedBox(height: 18),
              SpacePrimaryButton(text: _saving ? 'Сохраняем...' : 'Сохранить контакт', onPressed: _saving ? null : _save),
            ],
          ),
        ),
      ),
    );
  }
}

class FolderManagerSheet extends StatefulWidget {
  final String ownerId;
  final Future<void> Function() onChanged;

  const FolderManagerSheet({super.key, required this.ownerId, required this.onChanged});

  @override
  State<FolderManagerSheet> createState() => _FolderManagerSheetState();
}

class _FolderManagerSheetState extends State<FolderManagerSheet> {
  final _controller = TextEditingController();
  List<FolderItem> _folders = const [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await SpaceService.getFolders(widget.ownerId);
    if (!mounted) return;
    setState(() {
      _folders = items;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      await SpaceService.createFolder(ownerId: widget.ownerId, title: title);
      _controller.clear();
      await _load();
      await widget.onChanged();
    } catch (e) {
      showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
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
            const SizedBox(height: 8),
            Text('Папку «Все» удалить нельзя. Можно создать до 15 папок.', style: TextStyle(color: SpacePalette.sub(context))),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Название новой папки'),
            ),
            const SizedBox(height: 12),
            SpacePrimaryButton(text: _saving ? 'Создаём...' : 'Создать папку', onPressed: _saving ? null : _create),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
            else
              ..._folders.map(
                (folder) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_rounded),
                  title: Text(folder.title),
                  trailing: IconButton(onPressed: () => _delete(folder), icon: const Icon(Icons.delete_outline_rounded)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ChatActionsSheet extends StatelessWidget {
  final ConversationItem item;
  final String ownerId;
  final List<FolderItem> folders;
  final bool isMuted;
  final Future<void> Function() onChanged;

  const ChatActionsSheet({
    super.key,
    required this.item,
    required this.ownerId,
    required this.folders,
    required this.isMuted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetAction(
              icon: item.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              title: item.pinned ? 'Открепить чат' : 'Закрепить чат',
              onTap: () async {
                Navigator.pop(context);
                try {
                  if (item.pinned) {
                    await SpaceService.unpinChat(ownerId: ownerId, conversationId: item.id);
                  } else {
                    await SpaceService.pinChat(ownerId: ownerId, conversationId: item.id);
                  }
                  await onChanged();
                } catch (e) {
                  showSpaceSnack(context, '$e');
                }
              },
            ),
            _SheetAction(
              icon: isMuted ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
              title: isMuted ? 'Включить уведомления' : 'Выключить уведомления',
              onTap: () async {
                Navigator.pop(context);
                await SpaceLocalPrefs.toggleMutedChat(item.id);
                await onChanged();
              },
            ),
            _SheetAction(
              icon: Icons.folder_copy_rounded,
              title: 'Добавить в папку',
              onTap: () async {
                Navigator.pop(context);
                await showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (context) => FolderPickerSheet(ownerId: ownerId, conversationId: item.id, folders: folders),
                );
                await onChanged();
              },
            ),
            if (item.directUserId != null)
              _SheetAction(
                icon: Icons.block_rounded,
                title: 'Заблокировать',
                onTap: () async {
                  Navigator.pop(context);
                  await SpaceService.blockUser(ownerId: ownerId, blockedUserId: item.directUserId!);
                  showSpaceSnack(context, 'Пользователь заблокирован.');
                },
              ),
            _SheetAction(
              icon: Icons.delete_outline_rounded,
              title: 'Удалить чат у меня',
              onTap: () async {
                Navigator.pop(context);
                await SpaceService.hideChat(ownerId: ownerId, conversationId: item.id);
                await onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class FolderPickerSheet extends StatefulWidget {
  final String ownerId;
  final String conversationId;
  final List<FolderItem> folders;

  const FolderPickerSheet({super.key, required this.ownerId, required this.conversationId, required this.folders});

  @override
  State<FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends State<FolderPickerSheet> {
  Set<String> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final current = await SpaceService.folderAssignments(ownerId: widget.ownerId, conversationId: widget.conversationId);
    if (!mounted) return;
    setState(() {
      _selected = current.toSet();
      _loading = false;
    });
  }

  Future<void> _toggle(FolderItem folder) async {
    final contains = _selected.contains(folder.id);
    if (contains) {
      await SpaceService.removeChatFromFolder(ownerId: widget.ownerId, conversationId: widget.conversationId, folderId: folder.id);
      _selected.remove(folder.id);
    } else {
      await SpaceService.addChatToFolder(ownerId: widget.ownerId, conversationId: widget.conversationId, folderId: folder.id);
      _selected.add(folder.id);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Папки для этого чата', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (widget.folders.isEmpty)
              Text('Сначала создай папку в настройках или через экран чатов.', style: TextStyle(color: SpacePalette.sub(context)))
            else if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
            else
              ...widget.folders.map(
                (folder) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.trailing,
                  value: _selected.contains(folder.id),
                  title: Text(folder.title),
                  onChanged: (_) => _toggle(folder),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CreateConversationSheet extends StatefulWidget {
  final String currentUserId;
  final Future<void> Function() onCreated;

  const _CreateConversationSheet({required this.currentUserId, required this.onCreated});

  @override
  State<_CreateConversationSheet> createState() => _CreateConversationSheetState();
}

class _CreateConversationSheetState extends State<_CreateConversationSheet> {
  int _mode = 0; // 0 group 1 channel
  bool _loading = false;
  final _titleController = TextEditingController();
  final _searchController = TextEditingController();
  List<UserProfile> _results = const [];
  final Set<String> _selectedMemberIds = {};
  final Set<String> _selectedAdminIds = {};
  Timer? _debounce;

  @override
  void dispose() {
    _titleController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _runSearch(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () async {
      final rows = await SpaceService.searchUsers(q);
      if (!mounted) return;
      setState(() => _results = rows.where((e) => e.id != widget.currentUserId).toList());
    });
  }

  Future<void> _create() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      showSpaceSnack(context, 'Название обязательно.');
      return;
    }
    setState(() => _loading = true);
    try {
      if (_mode == 0) {
        await SpaceService.createGroup(ownerId: widget.currentUserId, title: title, memberIds: _selectedMemberIds.toList());
      } else {
        await SpaceService.createPrivateChannel(
          ownerId: widget.currentUserId,
          title: title,
          memberIds: _selectedMemberIds.toList(),
          adminIds: _selectedAdminIds.toList(),
        );
      }
      await widget.onCreated();
    } catch (e) {
      showSpaceSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
            Text('Создать', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: SpacePill(label: 'Группа', selected: _mode == 0, onTap: () => setState(() => _mode = 0))),
                Expanded(child: SpacePill(label: 'Канал', selected: _mode == 1, onTap: () => setState(() => _mode = 1))),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(labelText: _mode == 0 ? 'Название группы' : 'Название канала'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: _runSearch,
              decoration: const InputDecoration(labelText: 'Найти участников по username', prefixIcon: Icon(Icons.search_rounded)),
            ),
            const SizedBox(height: 12),
            if (_selectedMemberIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Выбрано участников: ${_selectedMemberIds.length}', style: TextStyle(color: SpacePalette.sub(context))),
              ),
            if (_results.isNotEmpty)
              SizedBox(
                height: 220,
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final user = _results[index];
                    final selected = _selectedMemberIds.contains(user.id);
                    final admin = _selectedAdminIds.contains(user.id);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SpaceAvatar(title: user.fullName, imageUrl: user.avatarUrl, radius: 18),
                      title: Text(user.fullName),
                      subtitle: Text('@${user.username}'),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          if (_mode == 1 && selected)
                            ChoiceChip(
                              label: const Text('Админ'),
                              selected: admin,
                              onSelected: (value) {
                                setState(() {
                                  if (value) {
                                    _selectedAdminIds.add(user.id);
                                  } else {
                                    _selectedAdminIds.remove(user.id);
                                  }
                                });
                              },
                            ),
                          Checkbox(
                            value: selected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedMemberIds.add(user.id);
                                } else {
                                  _selectedMemberIds.remove(user.id);
                                  _selectedAdminIds.remove(user.id);
                                }
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            if (_mode == 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Канал создаётся приватным. Войти можно только по ссылке. Владельца нельзя убрать из админов.', style: TextStyle(color: SpacePalette.sub(context), height: 1.35)),
              ),
            const SizedBox(height: 14),
            SpacePrimaryButton(text: _loading ? 'Создаём...' : (_mode == 0 ? 'Создать группу' : 'Создать канал'), onPressed: _loading ? null : _create),
          ],
        ),
      ),
    );
  }
}

class _SearchBlockTitle extends StatelessWidget {
  final String title;

  const _SearchBlockTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800));
  }
}

class _UserSearchTile extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onTap;

  const _UserSearchTile({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Row(
          children: [
            SpaceAvatar(title: profile.fullName, imageUrl: profile.avatarUrl, radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('@${profile.username}', style: TextStyle(color: SpacePalette.sub(context))),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _SheetAction({required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      onTap: onTap,
    );
  }
}
