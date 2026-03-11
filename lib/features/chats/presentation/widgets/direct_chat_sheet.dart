import 'dart:math' as math;

import 'package:chatify/core/domain/entities/contact_candidate.dart';
import 'package:chatify/core/domain/repositories/contacts_repository.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<String?> showDirectChatSheet({
  required BuildContext context,
  required ContactsRepository contactsRepository,
}) async {
  final permissionResult = await contactsRepository.requestContactsPermission();

  var fallbackToManual = permissionResult.error != null;
  var loadingError = permissionResult.error?.message;
  var candidates = const <ContactCandidate>[];

  if (!fallbackToManual) {
    final candidatesResult = await contactsRepository.fetchContactCandidates();
    if (candidatesResult.error != null) {
      fallbackToManual = true;
      loadingError = candidatesResult.error?.message;
    } else {
      candidates = candidatesResult.data ?? const <ContactCandidate>[];
    }
  }

  if (!context.mounted) {
    return null;
  }

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _DirectChatSheet(
      candidates: candidates,
      fallbackToManual: fallbackToManual,
      loadingError: loadingError,
    ),
  );
}

class _DirectChatSheet extends StatefulWidget {
  const _DirectChatSheet({
    required this.candidates,
    required this.fallbackToManual,
    this.loadingError,
  });

  final List<ContactCandidate> candidates;
  final bool fallbackToManual;
  final String? loadingError;

  @override
  State<_DirectChatSheet> createState() => _DirectChatSheetState();
}

class _DirectChatSheetState extends State<_DirectChatSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _manualController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = math.min(MediaQuery.of(context).size.height * 0.9, 680.0);
    final insets = MediaQuery.of(context).viewInsets;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: insets.bottom),
        child: SizedBox(
          height: maxHeight,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'New direct chat',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.fallbackToManual)
                _buildManualFallback(context)
              else
                _buildContactsList(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualFallback(BuildContext context) {
    return Expanded(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          Text(
            widget.loadingError ??
                'Contacts access is unavailable. Enter user id or phone manually.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _manualController,
            decoration: const InputDecoration(
              labelText: 'Peer user id or phone',
              hintText: 'uid_123 or +2010XXXXXXXX',
            ),
            onSubmitted: (_) => _submitManual(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _submitManual,
                child: const Text('Create'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContactsList(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.candidates
        .where((candidate) {
          if (query.isEmpty) {
            return true;
          }
          final haystack = [
            candidate.displayName,
            candidate.rawPhone,
            candidate.normalizedPhoneE164,
            candidate.phoneDigits,
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);

    final registered = filtered
        .where((candidate) => candidate.isRegistered)
        .toList(growable: false);
    final notRegistered = filtered
        .where((candidate) => !candidate.isRegistered)
        .toList(growable: false);

    return Expanded(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search contacts',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_search_outlined),
                  title: const Text('Enter user id or phone manually'),
                  onTap: () async {
                    final manual = await _askForManualEntry(context);
                    if (!context.mounted || manual == null || manual.isEmpty) {
                      return;
                    }
                    Navigator.of(context).pop(manual);
                  },
                ),
                if (registered.isNotEmpty)
                  _SectionHeader(title: 'On Chatify (${registered.length})'),
                for (final candidate in registered)
                  _buildRegisteredTile(context, candidate),
                if (registered.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Text('No registered contacts match your search.'),
                  ),
                if (notRegistered.isNotEmpty)
                  _SectionHeader(
                    title: 'Not on Chatify (${notRegistered.length})',
                  ),
                for (final candidate in notRegistered)
                  _buildInviteTile(context, candidate),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisteredTile(
    BuildContext context,
    ContactCandidate candidate,
  ) {
    final userId = candidate.registeredUserId;
    if (userId == null || userId.isEmpty) {
      return const SizedBox.shrink();
    }
    final subtitle = candidate.normalizedPhoneE164.isNotEmpty
        ? candidate.normalizedPhoneE164
        : candidate.rawPhone;

    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.person_outline)),
      title: Text(candidate.displayName),
      subtitle: Text(subtitle),
      onTap: () => Navigator.of(context).pop(userId),
    );
  }

  Widget _buildInviteTile(BuildContext context, ContactCandidate candidate) {
    final label = candidate.normalizedPhoneE164.isNotEmpty
        ? candidate.normalizedPhoneE164
        : candidate.rawPhone;

    return ListTile(
      title: Text(candidate.displayName),
      subtitle: Text('$label\nNot on Chatify'),
      trailing: TextButton(
        onPressed: () => _inviteViaSms(candidate),
        child: const Text('Invite via SMS'),
      ),
    );
  }

  Future<String?> _askForManualEntry(BuildContext context) async {
    final controller = TextEditingController();
    try {
      return showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Manual entry'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Peer user id or phone',
              hintText: 'uid_123 or +2010XXXXXXXX',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Use'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _inviteViaSms(ContactCandidate candidate) async {
    final phone = candidate.normalizedPhoneE164.isNotEmpty
        ? candidate.normalizedPhoneE164
        : candidate.rawPhone;
    final smsUri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: const <String, String>{
        'body':
            'Join me on Chatify so we can chat with voice and groups more easily.',
      },
    );

    try {
      final launched = await launchUrl(
        smsUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showSnack('No SMS app found on this device.');
      }
    } catch (_) {
      if (mounted) {
        _showSnack('Could not open SMS app.');
      }
    }
  }

  void _submitManual() {
    final peer = _manualController.text.trim();
    if (peer.isEmpty) {
      _showSnack('Peer user id or phone is required.');
      return;
    }
    Navigator.of(context).pop(peer);
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
