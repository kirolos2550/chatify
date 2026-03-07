import 'package:chatify/app/di/injection.dart';
import 'package:chatify/core/common/result.dart';
import 'package:chatify/core/domain/entities/app_user.dart';
import 'package:chatify/core/domain/repositories/auth_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({required this.userId, super.key});

  final String userId;

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _loading = true;
  String? _errorMessage;
  AppUser? _profile;
  List<_GroupEntry> _groups = const <_GroupEntry>[];
  List<_GroupEntry> _sharedGroups = const <_GroupEntry>[];

  String? get _currentUid =>
      Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser?.uid : null;

  bool get _isViewingSelf =>
      _currentUid != null && _currentUid == widget.userId;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (widget.userId.trim().isEmpty) {
      setState(() {
        _loading = false;
        _errorMessage = 'Invalid user id';
      });
      return;
    }
    if (Firebase.apps.isEmpty) {
      setState(() {
        _loading = false;
        _errorMessage = 'User profile is unavailable in demo mode';
      });
      return;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore
          .collection('users')
          .doc(widget.userId)
          .get();
      final profile = _mapUser(userDoc);

      final conversationsSnapshot = await firestore
          .collection('conversations')
          .where('memberIds', arrayContains: widget.userId)
          .get();

      final groups =
          conversationsSnapshot.docs
              .map((doc) => _mapGroup(doc, viewedUserId: widget.userId))
              .where((group) => group != null)
              .cast<_GroupEntry>()
              .toList()
            ..sort((a, b) => b.activityAt.compareTo(a.activityAt));

      final currentUid = _currentUid;
      final shared = currentUid == null || currentUid == widget.userId
          ? groups
          : groups
                .where((group) => group.memberIds.contains(currentUid))
                .toList();

      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _profile = profile;
        _groups = groups;
        _sharedGroups = shared;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = error.toString();
      });
    }
  }

  AppUser _mapUser(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return AppUser(
      id: doc.id,
      phone: (data['phone'] as String? ?? '').trim(),
      displayName: (data['displayName'] as String? ?? 'User').trim().isEmpty
          ? 'User'
          : (data['displayName'] as String).trim(),
      avatarUrl: (data['avatarUrl'] as String?)?.trim().isEmpty ?? true
          ? null
          : (data['avatarUrl'] as String).trim(),
      about: (data['about'] as String?)?.trim(),
      createdAt: _toDateTime(data['createdAt']) ?? DateTime.now().toUtc(),
    );
  }

  _GroupEntry? _mapGroup(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String viewedUserId,
  }) {
    final data = doc.data() ?? <String, dynamic>{};
    if ((data['type'] as String?) != 'group') {
      return null;
    }
    final memberIds = _toStringList(data['memberIds']);
    final ownerId = (data['ownerId'] as String?)?.trim();
    final titleRaw = (data['title'] as String?)?.trim();
    final title = (titleRaw == null || titleRaw.isEmpty)
        ? 'Group ${doc.id.substring(0, doc.id.length > 6 ? 6 : doc.id.length)}'
        : titleRaw;
    return _GroupEntry(
      conversationId: doc.id,
      title: title,
      ownerId: ownerId,
      memberIds: memberIds,
      isOwnedByViewedUser: ownerId == viewedUserId,
      activityAt:
          _toDateTime(data['updatedAt']) ??
          _toDateTime(data['createdAt']) ??
          DateTime.now().toUtc(),
    );
  }

  List<String> _toStringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value.whereType<String>().toList(growable: false);
  }

  DateTime? _toDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isViewingSelf ? 'My profile' : 'User profile'),
        actions: [
          if (_isViewingSelf)
            IconButton(
              tooltip: 'Edit profile',
              onPressed: _editMyProfile,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(_errorMessage!, textAlign: TextAlign.center),
        ),
      );
    }

    final profile = _profile;
    if (profile == null) {
      return const Center(child: Text('User not found'));
    }

    final createdCount = _groups
        .where((group) => group.isOwnedByViewedUser)
        .length;
    final sharedCount = _sharedGroups.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ProfileHeader(profile: profile, isSelf: _isViewingSelf),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Groups overview',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Total groups: ${_groups.length}'),
                Text('Created by this user: $createdCount'),
                if (!_isViewingSelf) Text('Shared with you: $sharedCount'),
              ],
            ),
          ),
        ),
        _buildGroupSection(
          context: context,
          title: _isViewingSelf ? 'Your groups' : 'User groups',
          groups: _groups,
          emptyText: 'No groups to show yet.',
        ),
        if (!_isViewingSelf)
          _buildGroupSection(
            context: context,
            title: 'Shared groups',
            groups: _sharedGroups,
            emptyText: 'No shared groups with you yet.',
          ),
      ],
    );
  }

  Widget _buildGroupSection({
    required BuildContext context,
    required String title,
    required List<_GroupEntry> groups,
    required String emptyText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (groups.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(emptyText),
            ),
          )
        else
          ...groups.map(
            (group) => Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.group_outlined)),
                title: Text(group.title),
                subtitle: Text(
                  group.isOwnedByViewedUser
                      ? 'Owner'
                      : 'Member${group.ownerId != null ? ' - owner ${group.ownerId}' : ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/chat/${group.conversationId}'),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _editMyProfile() async {
    final profile = _profile;
    if (profile == null) {
      return;
    }
    if (!getIt.isRegistered<AuthRepository>()) {
      _showSnack('Profile service is unavailable');
      return;
    }

    final displayNameController = TextEditingController(
      text: profile.displayName,
    );
    final aboutController = TextEditingController(text: profile.about ?? '');
    final avatarController = TextEditingController(
      text: profile.avatarUrl ?? '',
    );

    try {
      final payload = await showDialog<(String, String, String)>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Edit profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: displayNameController,
                  decoration: const InputDecoration(labelText: 'Display name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: aboutController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'About'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: avatarController,
                  decoration: const InputDecoration(
                    labelText: 'Avatar URL',
                    hintText: 'https://...',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((
                displayNameController.text,
                aboutController.text,
                avatarController.text,
              )),
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (!mounted || payload == null) {
        return;
      }

      final displayName = payload.$1.trim();
      if (displayName.isEmpty) {
        _showSnack('Display name is required');
        return;
      }
      final about = payload.$2.trim();
      final avatarUrl = payload.$3.trim();

      final result = await getIt<AuthRepository>().updateProfile(
        displayName: displayName,
        about: about.isEmpty ? null : about,
        avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
      );
      if (!mounted) {
        return;
      }

      if (result is Success<void>) {
        _showSnack('Profile updated');
        setState(() {
          _loading = true;
          _errorMessage = null;
        });
        await _loadProfile();
        return;
      }
      _showSnack(result.error?.message ?? 'Failed to update profile');
    } finally {
      displayNameController.dispose();
      aboutController.dispose();
      avatarController.dispose();
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.isSelf});

  final AppUser profile;
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final avatarLetter = profile.displayName.isEmpty
        ? '?'
        : profile.displayName[0].toUpperCase();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundImage: profile.avatarUrl != null
                  ? NetworkImage(profile.avatarUrl!)
                  : null,
              child: profile.avatarUrl == null ? Text(avatarLetter) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(profile.phone.isEmpty ? '-' : profile.phone),
                  const SizedBox(height: 4),
                  Text(
                    profile.about?.isNotEmpty == true
                        ? profile.about!
                        : 'No bio',
                  ),
                  const SizedBox(height: 6),
                  SelectableText('ID: ${profile.id}'),
                  if (isSelf)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Visible to other users'),
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

class _GroupEntry {
  const _GroupEntry({
    required this.conversationId,
    required this.title,
    required this.memberIds,
    required this.isOwnedByViewedUser,
    required this.activityAt,
    this.ownerId,
  });

  final String conversationId;
  final String title;
  final String? ownerId;
  final List<String> memberIds;
  final bool isOwnedByViewedUser;
  final DateTime activityAt;
}
