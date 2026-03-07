import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

class WhatsAppBusinessPage extends StatefulWidget {
  const WhatsAppBusinessPage({super.key});

  @override
  State<WhatsAppBusinessPage> createState() => _WhatsAppBusinessPageState();
}

class _WhatsAppBusinessPageState extends State<WhatsAppBusinessPage> {
  final TextEditingController _textToController = TextEditingController();
  final TextEditingController _textBodyController = TextEditingController();
  final TextEditingController _templateToController = TextEditingController();
  final TextEditingController _templateNameController = TextEditingController();
  final TextEditingController _templateLangController = TextEditingController(
    text: 'en_US',
  );
  final TextEditingController _templateParamsController =
      TextEditingController();

  bool _sendingText = false;
  bool _sendingTemplate = false;
  String? _lastResult;

  @override
  void dispose() {
    _textToController.dispose();
    _textBodyController.dispose();
    _templateToController.dispose();
    _templateNameController.dispose();
    _templateLangController.dispose();
    _templateParamsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = Firebase.apps.isEmpty;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('WhatsApp Business'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Text'),
              Tab(text: 'Template'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_buildTextTab(disabled), _buildTemplateTab(disabled)],
        ),
      ),
    );
  }

  Widget _buildTextTab(bool disabled) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _InfoCard(),
        const SizedBox(height: 12),
        TextField(
          controller: _textToController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Recipient number',
            hintText: '+2010XXXXXXXX',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _textBodyController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Message body',
            hintText: 'Hello from Chatify',
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: disabled || _sendingText ? null : _sendText,
          icon: _sendingText
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: Text(_sendingText ? 'Sending...' : 'Send text message'),
        ),
        const SizedBox(height: 12),
        _ResultCard(result: _lastResult),
      ],
    );
  }

  Widget _buildTemplateTab(bool disabled) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _InfoCard(),
        const SizedBox(height: 12),
        TextField(
          controller: _templateToController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Recipient number',
            hintText: '+2010XXXXXXXX',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _templateNameController,
          decoration: const InputDecoration(
            labelText: 'Template name',
            hintText: 'order_update',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _templateLangController,
          decoration: const InputDecoration(
            labelText: 'Language code',
            hintText: 'en_US',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _templateParamsController,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Body params (comma separated)',
            hintText: 'Ahmed, #12345, today',
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: disabled || _sendingTemplate ? null : _sendTemplate,
          icon: _sendingTemplate
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.mark_chat_read_outlined),
          label: Text(
            _sendingTemplate ? 'Sending...' : 'Send template message',
          ),
        ),
        const SizedBox(height: 12),
        _ResultCard(result: _lastResult),
      ],
    );
  }

  Future<void> _sendText() async {
    final to = _textToController.text.trim();
    final body = _textBodyController.text.trim();
    if (to.isEmpty || body.isEmpty) {
      _showSnack('Recipient and message body are required');
      return;
    }

    setState(() => _sendingText = true);
    try {
      final result = await _callFunction(
        name: 'sendWhatsappText',
        data: {'to': to, 'body': body},
      );
      if (!mounted) {
        return;
      }
      setState(
        () => _lastResult = const JsonEncoder.withIndent('  ').convert(result),
      );
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _sendingText = false);
      }
    }
  }

  Future<void> _sendTemplate() async {
    final to = _templateToController.text.trim();
    final templateName = _templateNameController.text.trim();
    final languageCode = _templateLangController.text.trim();
    final bodyParams = _templateParamsController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    if (to.isEmpty || templateName.isEmpty || languageCode.isEmpty) {
      _showSnack('Recipient, template name and language are required');
      return;
    }

    setState(() => _sendingTemplate = true);
    try {
      final result = await _callFunction(
        name: 'sendWhatsappTemplate',
        data: {
          'to': to,
          'templateName': templateName,
          'languageCode': languageCode,
          'bodyParams': bodyParams,
        },
      );
      if (!mounted) {
        return;
      }
      setState(
        () => _lastResult = const JsonEncoder.withIndent('  ').convert(result),
      );
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _sendingTemplate = false);
      }
    }
  }

  Future<Map<String, dynamic>> _callFunction({
    required String name,
    required Map<String, dynamic> data,
  }) async {
    if (Firebase.apps.isEmpty) {
      throw Exception('Firebase is not initialized');
    }
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(name);
      final result = await callable.call<Map<String, dynamic>>(data);
      return result.data;
    } on FirebaseFunctionsException catch (error) {
      throw Exception(
        'Cloud Function error (${error.code}): ${error.message ?? 'unknown'}',
      );
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

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'This screen uses Cloud Functions to call WhatsApp Cloud API.\n'
          'Required function env vars:\n'
          '- WHATSAPP_ACCESS_TOKEN\n'
          '- WHATSAPP_PHONE_NUMBER_ID\n'
          '- WHATSAPP_VERIFY_TOKEN',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final String? result;

  @override
  Widget build(BuildContext context) {
    final value = result;
    if (value == null || value.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(value),
      ),
    );
  }
}
