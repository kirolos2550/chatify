import 'dart:math' as math;

import 'package:chatify/core/domain/entities/contact_candidate.dart';
import 'package:chatify/core/domain/repositories/contacts_repository.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class GroupCreationDraft {
  const GroupCreationDraft({
    required this.title,
    required this.memberIdentifiers,
  });

  final String title;
  final List<String> memberIdentifiers;
}

Future<GroupCreationDraft?> showGroupCreationSheet({
  required BuildContext context,
  required ContactsRepository contactsRepository,
  required String title,
  Set<String> preselectedMemberIdentifiers = const <String>{},
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

  return showModalBottomSheet<GroupCreationDraft>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _GroupCreationSheet(
      sheetTitle: title,
      candidates: candidates,
      fallbackToManual: fallbackToManual,
      loadingError: loadingError,
      preselectedMemberIdentifiers: preselectedMemberIdentifiers,
    ),
  );
}

class _GroupCreationSheet extends StatefulWidget {
  const _GroupCreationSheet({
    required this.sheetTitle,
    required this.candidates,
    required this.fallbackToManual,
    required this.preselectedMemberIdentifiers,
    this.loadingError,
  });

  final String sheetTitle;
  final List<ContactCandidate> candidates;
  final bool fallbackToManual;
  final String? loadingError;
  final Set<String> preselectedMemberIdentifiers;

  @override
  State<_GroupCreationSheet> createState() => _GroupCreationSheetState();
}

class _GroupCreationSheetState extends State<_GroupCreationSheet> {
  final TextEditingController _groupTitleController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _manualMembersController =
      TextEditingController();

  late final Set<String> _selectedMemberIds = widget
      .preselectedMemberIdentifiers
      .toSet();

  bool _submitting = false;

  @override
  void dispose() {
    _groupTitleController.dispose();
    _searchController.dispose();
    _manualMembersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = math
        .min(MediaQuery.of(context).size.height * 0.9, 700)
        .toDouble();
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.sheetTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _groupTitleController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Group title',
                    hintText: 'Product launch',
                  ),
                ),
              ),
              Expanded(
                child: widget.fallbackToManual
                    ? _buildManualFallback(context)
                    : _buildContactsPicker(context),
              ),
              const Divider(height: 0),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create group'),
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

  Widget _buildContactsPicker(BuildContext context) {
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

    return Column(
      children: [
        if (widget.preselectedMemberIdentifiers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Preselected from current chat: ${widget.preselectedMemberIdentifiers.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
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
              if (registered.isNotEmpty)
                _SectionHeader(
                  title:
                      'On Chatify (${registered.length}) - Selected ${_selectedMemberIds.length}',
                ),
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
    );
  }

  Widget _buildManualFallback(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      children: [
        Text(
          widget.loadingError ??
              'Contacts access is unavailable. You can still create a group by entering member uid or phone.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _manualMembersController,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Members (uid/phone)',
            hintText: 'uid_1, +2010xxxx, uid_2',
          ),
        ),
        if (widget.preselectedMemberIdentifiers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Preselected members will be included automatically (${widget.preselectedMemberIdentifiers.length}).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildRegisteredTile(
    BuildContext context,
    ContactCandidate candidate,
  ) {
    final userId = candidate.registeredUserId;
    final checked =
        userId != null &&
        userId.isNotEmpty &&
        _selectedMemberIds.contains(userId);

    return CheckboxListTile(
      value: checked,
      onChanged: (value) {
        if (userId == null || userId.isEmpty) {
          return;
        }
        setState(() {
          if (value == true) {
            _selectedMemberIds.add(userId);
          } else {
            _selectedMemberIds.remove(userId);
          }
        });
      },
      title: Text(candidate.displayName),
      subtitle: Text(
        candidate.normalizedPhoneE164.isNotEmpty
            ? candidate.normalizedPhoneE164
            : candidate.rawPhone,
      ),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
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

  Future<void> _inviteViaSms(ContactCandidate candidate) async {
    final phone = candidate.normalizedPhoneE164.isNotEmpty
        ? candidate.normalizedPhoneE164
        : candidate.rawPhone;
    final smsUri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: const <String, String>{
        'body':
            'Join me on Chatify so we can chat in groups and calls more easily.',
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

  Future<void> _submit() async {
    final title = _groupTitleController.text.trim();
    if (title.isEmpty) {
      _showSnack('Group title is required.');
      return;
    }

    setState(() => _submitting = true);

    final identifiers = <String>{..._selectedMemberIds};
    if (widget.fallbackToManual) {
      final manual = _manualMembersController.text
          .split(RegExp(r'[,\n]'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty);
      identifiers.addAll(manual);
    }

    if (identifiers.isEmpty) {
      setState(() => _submitting = false);
      _showSnack('Add at least one member.');
      return;
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(
      GroupCreationDraft(
        title: title,
        memberIdentifiers: identifiers.toList(growable: false),
      ),
    );
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
