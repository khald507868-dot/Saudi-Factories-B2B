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
    _channel = SFMessages.subscribe(() {
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

    if (!AuthService.instance.isSignedIn) {
      return Scaffold(
        backgroundColor: SFColors.pageBg,
        appBar: SFTopBar(title: i18n.t('nav_messages')),
        body: SFStateView(
          message: 'يجب تسجيل الدخول للرسائل',
          icon: Icons.lock_outline,
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
              return SFStateView(
                message: i18n.t('fx_loading'),
                loading: true,
              );
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
            return ListView.separated(
              itemCount: threads.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) =>
                  _ThreadTile(thread: threads[i], onReturn: _reload),
            );
          },
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread, required this.onReturn});

  final SFThread thread;
  final Future<void> Function() onReturn;

  @override
  Widget build(BuildContext context) {
    final last = thread.lastMessage;
    final preview = last == null
        ? ''
        : (last.isText
            ? last.text
            : (last.type == 'video' ? '🎬' : '📷'));

    return ListTile(
      tileColor: SFColors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: SFImage(
        url: thread.avatar,
        width: 46,
        height: 46,
        radius: 999,
        placeholderIcon: Icons.person_outline,
      ),
      title: Text(
        thread.name.isEmpty ? '—' : thread.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: preview.isEmpty
          ? null
          : Text(
              preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: SFColors.muted2,
              ),
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _shortTime(thread.updated),
            style: const TextStyle(fontSize: 11, color: SFColors.muted),
          ),
          const SizedBox(height: 6),
          if (thread.unread > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: SFColors.danger,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                thread.unread > 99 ? '99+' : '${thread.unread}',
                style: const TextStyle(
                  color: SFColors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
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
