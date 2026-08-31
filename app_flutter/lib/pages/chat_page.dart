// ============================================================
//  المحادثة — الجزء الثاني من app-messages.html
//
//  الإرسال متفائل: تظهر الفقاعة فوراً بمعرّف مؤقّت ثم يحلّ
//  محلّها صفّ الخادم؛ وعند الفشل تُزال ويعود النص للمحرّر.
//
//  مهم: يجب تجاهل صدى الاشتراك اللحظي لرسائلنا نحن. بدون
//  ذلك يُعاد تحميل المحادثة بعد كل إرسال بجزء من الثانية،
//  فتبدو الصفحة وكأنها "تُحدِّث نفسها" والإرسال بطيئاً —
//  وهما عرَض واحد لا اثنان.
// ============================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/messages_service.dart';
import '../widgets/common.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.conversationId,
    this.title = '',
    this.draft = '',
  });

  final int conversationId;
  final String title;

  /// نص مبدئي يُوضع في المحرّر — يأتي من صفحة المنتج.
  final String draft;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  List<SFMessage> _messages = [];
  bool _loading = true;
  Object? _error;
  RealtimeChannel? _channel;

  /// معرّفات الرسائل التي أرسلناها — يُسقَط صدى الاشتراك لها.
  final Set<String> _sentIds = {};

  @override
  void initState() {
    super.initState();
    _composer.text = widget.draft;
    _load();
    _channel = SFMessages.subscribe(_onRealtime);
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    if (_channel != null) {
      // ignore: discarded_futures
      _channel!.unsubscribe();
    }
    super.dispose();
  }

  void _onRealtime() {
    // صدى إرسالنا: نتجاهل إشعاراً واحداً لكل رسالة أرسلناها.
    if (_sentIds.isNotEmpty) {
      _sentIds.remove(_sentIds.first);
      return;
    }
    _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final rows = await SFMessages.loadMessages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages = rows;
        _loading = false;
        _error = null;
      });
      _jumpToEnd();
      unawaited(SFMessages.markRead(widget.conversationId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;

    final tempId = 'tmp-${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = SFMessage(
      id: tempId,
      mine: true,
      type: 'text',
      text: text,
      src: '',
      at: DateTime.now(),
      pending: true,
    );

    setState(() {
      _messages = [..._messages, optimistic];
      _composer.clear();
    });
    _jumpToEnd();

    try {
      final saved = await SFMessages.sendText(widget.conversationId, text);
      _sentIds.add(saved.id);
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((m) => m.id == tempId ? saved : m)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      // الفشل ظاهر: تُزال الفقاعة ويعود النص إلى المحرّر.
      setState(() {
        _messages = _messages.where((m) => m.id != tempId).toList();
        _composer.text = text;
      });
      showSFError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: AppBar(
        title: Text(
          widget.title.isEmpty ? i18n.t('nav_messages') : widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody(i18n)),
          _Composer(
            controller: _composer,
            hint: i18n.t('msg_input_placeholder'),
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildBody(I18n i18n) {
    if (_loading) {
      return SFStateView(message: i18n.t('fx_loading'), loading: true);
    }
    if (_error != null) {
      return SFStateView(
        message: i18n.t('fx_failed'),
        icon: Icons.cloud_off,
        onRetry: _load,
      );
    }
    if (_messages.isEmpty) {
      return SFStateView(
        message: i18n.t('msg_empty_title'),
        icon: Icons.chat_bubble_outline,
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(14),
      itemCount: _messages.length,
      itemBuilder: (context, i) => _Bubble(message: _messages[i]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final SFMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;

    return Align(
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        decoration: BoxDecoration(
          color: mine ? SFColors.darkGreen : SFColors.white,
          border: Border.all(
            color: mine ? SFColors.darkGreen : SFColors.border,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!message.isText && message.src.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SFImage(url: message.src, height: 160),
              ),
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.7,
                  color: mine ? SFColors.white : SFColors.darkGreen,
                ),
              ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _time(message.at),
                  style: TextStyle(
                    fontSize: 10,
                    color: mine ? SFColors.muted : SFColors.muted,
                  ),
                ),
                if (message.pending) ...[
                  const SizedBox(width: 4),
                  const SizedBox(
                    width: 9,
                    height: 9,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.4,
                      color: SFColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.hint,
    required this.onSend,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          color: SFColors.white,
          border: Border(top: BorderSide(color: SFColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  fillColor: SFColors.pageBg,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: onSend,
              style: IconButton.styleFrom(
                backgroundColor: SFColors.darkGreen,
                foregroundColor: SFColors.white,
              ),
              icon: const Icon(Icons.send, size: 19),
            ),
          ],
        ),
      ),
    );
  }
}
