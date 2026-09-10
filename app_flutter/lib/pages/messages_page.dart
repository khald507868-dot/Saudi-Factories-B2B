// ============================================================
//  قائمة المحادثات — مقابل app-messages.html
//
//  الصفوف من الخادم فقط؛ لا نسخة محلية. القائمة تتحدّث
//  مع تغيّرات جدول الرسائل عبر الاشتراك اللحظي.
// ============================================================

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/messages_service.dart';
import '../widgets/common.dart';
import 'auth_page.dart';
import 'chat_page.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  late Future<List<SFThread>> _future;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _channel = SFMessages.subscribe((_) {
      if (mounted) setState(() => _future = _load());
    });
  }

  @override
  void dispose() {
    if (_channel != null) {
      // ignore: discarded_futures
      _channel!.unsubscribe();
    }
    super.dispose();
  }

  Future<List<SFThread>> _load() {
    if (!AuthService.instance.isSignedIn) {
      return Future.value(<SFThread>[]);
    }
    return SFMessages.load();
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    if (!AuthService.instance.isSignedIn) {
      return Scaffold(
        backgroundColor: SFColors.pageBg,
        appBar: SFTopBar(title: i18n.t('nav_messages')),
        body: SFStateView(
          message: i18n.t('login_required_action'),
          icon: Icons.lock_outline,
          retryLabel: context.t('splash_login_btn'),
          onRetry: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AuthPage(accountType: 'individual'),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      appBar: SFTopBar(title: i18n.t('nav_messages')),
      body: RefreshIndicator(
        onRefresh: _reload,
        color: SFColors.midGreen,
        child: FutureBuilder<List<SFThread>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return SFStateView(message: i18n.t('fx_loading'), loading: true);
            }
            if (snap.hasError) {
              return SFStateView(
                message: i18n.t('fx_failed'),
                icon: Icons.cloud_off,
                onRetry: _reload,
              );
            }
            final threads = snap.data ?? [];
            if (threads.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 90),
                  SFStateView(
                    message: i18n.t('msg_empty_title'),
                    icon: Icons.chat_bubble_outline,
                  ),
                ],
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              itemCount: threads.length,
              itemBuilder: (context, i) => _ThreadTile(
                thread: threads[i],
                onReturn: _reload,
                first: i == 0,
                last: i == threads.length - 1,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.thread,
    required this.onReturn,
    required this.first,
    required this.last,
  });

  final SFThread thread;
  final Future<void> Function() onReturn;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final message = thread.lastMessage;
    final preview = message == null
        ? ''
        : (message.type == 'product'
              ? '📦 ${message.text.isNotEmpty ? message.text : message.product?.name ?? ''}'
              : message.isText
              ? message.text
              : (message.type == 'video'
                    ? '🎬 ${context.t('msg_video')}'
                    : '📷 ${context.t('msg_photo')}'));
    final radius = BorderRadius.vertical(
      top: first ? const Radius.circular(SFMetrics.radius) : Radius.zero,
      bottom: last ? const Radius.circular(SFMetrics.radius) : Radius.zero,
    );

    return Material(
      color: SFColors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: SFColors.border),
      ),
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChatPage(
                conversationId: thread.conversationId,
                title: thread.name,
              ),
            ),
          );
          await onReturn();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              SFImage(
                url: thread.avatar,
                width: 44,
                height: 44,
                radius: 999,
                placeholderIcon: Icons.person_outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.name.isEmpty ? '—' : thread.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _shortTime(thread.updated),
                          textDirection: TextDirection.ltr,
                          style: TextStyle(
                            fontSize: 11,
                            color: thread.unread > 0
                                ? SFColors.midGreen
                                : SFColors.muted2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: thread.unread > 0
                                  ? SFColors.darkGreen
                                  : SFColors.muted2,
                              fontWeight: thread.unread > 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (thread.unread > 0) ...[
                          const SizedBox(width: 8),
                          Semantics(
                            label: context.t('dash_stat_unread'),
                            child: Badge(
                              backgroundColor: SFColors.midGreen,
                              label: Text(
                                thread.unread > 99 ? '99+' : '${thread.unread}',
                              ),
                            ),
                          ),
                        ],
                      ],
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

  static String _shortTime(DateTime t) {
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    if (sameDay) {
      final h = t.hour.toString().padLeft(2, '0');
      final m = t.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${t.day}/${t.month}';
  }
}
