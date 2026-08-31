// ============================================================
//  خدمة الرسائل — مقابل messages-service.js
//
//  قائمة المحادثات تُبنى من دوال الخادم (RPC) لا بربط الجداول
//  في العميل: سياسة RLS ترفض قراءة صفوف profiles لطرف آخر،
//  ولذلك وُجدت get_conversation_peers.
//
//  المرفقات في دلو خاص، فتُوقَّع روابطها (signed URL) لساعة.
// ============================================================

import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import 'auth_service.dart';

const String _conversationSelect =
    'id, factory_id, individual_id, last_message_at, created_at';
const String _messageSelect =
    'id, sender_id, body, attachment_url, attachment_type, created_at';

/// رسالة واحدة بعد التطبيع — نفس شكل mapMessage في الويب.
class SFMessage {
  SFMessage({
    required this.id,
    required this.mine,
    required this.type,
    required this.text,
    required this.src,
    required this.at,
    this.pending = false,
    this.failed = false,
  });

  final String id;

  /// من المستخدم الحالي؟ (mine مقابل theirs في الويب)
  final bool mine;

  /// text أو image أو video.
  final String type;
  final String text;

  /// رابط المرفق الموقّع.
  final String src;
  final DateTime at;

  /// رسالة متفائلة لم يؤكّدها الخادم بعد.
  final bool pending;
  final bool failed;

  bool get isText => type == 'text' || type.isEmpty;

  SFMessage copyWith({bool? pending, bool? failed}) => SFMessage(
        id: id,
        mine: mine,
        type: type,
        text: text,
        src: src,
        at: at,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
      );

  static SFMessage fromRow(Map<String, dynamic> m, String currentId,
      {String signedUrl = ''}) {
    return SFMessage(
      id: '${m['id']}',
      mine: m['sender_id'] == currentId,
      type: (m['attachment_type'] as String?)?.isNotEmpty == true
          ? m['attachment_type'] as String
          : 'text',
      text: (m['body'] as String?) ?? '',
      src: signedUrl,
      at: DateTime.tryParse('${m['created_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// محادثة في القائمة.
class SFThread {
  SFThread({
    required this.id,
    required this.conversationId,
    required this.factoryId,
    required this.name,
    required this.role,
    required this.avatar,
    required this.updated,
    this.unread = 0,
    this.lastMessage,
    this.messages = const [],
    this.messagesLoaded = false,
  });

  final String id;
  final int conversationId;
  final int? factoryId;
  final String name;
  final String role;
  final String avatar;
  final DateTime updated;
  final int unread;
  final SFMessage? lastMessage;
  final List<SFMessage> messages;
  final bool messagesLoaded;

  SFThread copyWith({
    List<SFMessage>? messages,
    bool? messagesLoaded,
    int? unread,
    SFMessage? lastMessage,
    DateTime? updated,
  }) =>
      SFThread(
        id: id,
        conversationId: conversationId,
        factoryId: factoryId,
        name: name,
        role: role,
        avatar: avatar,
        updated: updated ?? this.updated,
        unread: unread ?? this.unread,
        lastMessage: lastMessage ?? this.lastMessage,
        messages: messages ?? this.messages,
        messagesLoaded: messagesLoaded ?? this.messagesLoaded,
      );
}

class SFMessages {
  SFMessages._();

  static void _ready() {
    if (AuthService.instance.user == null) {
      throw Exception('يجب تسجيل الدخول للرسائل');
    }
  }

  static String get _uid => AuthService.instance.user!.id;

  /// قائمة المحادثات — عبر get_conversation_summaries.
  static Future<List<SFThread>> load() async {
    _ready();
    final rows = await sb.rpc('get_conversation_summaries') as List<dynamic>?;
    final list = (rows ?? []).map((r) {
      final m = r as Map<String, dynamic>;
      final lastAt = m['last_message_created_at'] ?? m['last_message_at'];
      final updated =
          DateTime.tryParse('$lastAt')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0);
      SFMessage? last;
      if (m['last_message_created_at'] != null) {
        last = SFMessage(
          id: 'last-${m['conversation_id']}',
          mine: m['last_message_sender_id'] == _uid,
          type: (m['last_message_type'] as String?)?.isNotEmpty == true
              ? m['last_message_type'] as String
              : 'text',
          text: (m['last_message_body'] as String?) ?? '',
          src: '',
          at: updated,
        );
      }
      return SFThread(
        id: '${m['conversation_id']}',
        conversationId: (m['conversation_id'] as num).toInt(),
        factoryId: (m['factory_id'] as num?)?.toInt(),
        name: (m['peer_name'] as String?) ?? '',
        role: (m['peer_role'] as String?) ?? '',
        avatar: (m['peer_avatar'] as String?) ?? '',
        updated: updated,
        unread: ((m['unread_count'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30),
        lastMessage: last,
      );
    }).toList();
    list.sort((a, b) => b.updated.compareTo(a.updated));
    return list;
  }

  /// رسائل محادثة واحدة، مع توقيع روابط المرفقات.
  static Future<List<SFMessage>> loadMessages(int conversationId) async {
    _ready();
    if (conversationId <= 0) throw Exception('معرّف المحادثة غير صالح');
    final rows = await sb
        .from('messages')
        .select(_messageSelect)
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: true)
        .order('id', ascending: true);

    final out = <SFMessage>[];
    for (final r in rows) {
      final m = Map<String, dynamic>.from(r as Map);
      final path = (m['attachment_url'] as String?) ?? '';
      String signed = '';
      if (path.isNotEmpty) {
        try {
          signed = await sb.storage
              .from(SFBuckets.chatMedia)
              .createSignedUrl(path, 3600);
        } catch (_) {
          // تبقى الرسالة ظاهرة حتى لو تعذّر توقيع المرفق.
        }
      }
      out.add(SFMessage.fromRow(m, _uid, signedUrl: signed));
    }
    return out;
  }

  /// تعليم المحادثة مقروءة — الدالة ترفض غير الطرفين بـ 42501.
  static Future<int> markRead(int conversationId) async {
    _ready();
    if (conversationId <= 0) throw Exception('معرّف المحادثة غير صالح');
    try {
      final res =
          await sb.rpc('mark_conversation_read', params: {
        'p_conversation_id': conversationId,
      });
      return (res as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// إجمالي غير المقروء — لشارة الرسائل في الشريط السفلي.
  static Future<int> unreadTotal() async {
    if (AuthService.instance.user == null) return 0;
    try {
      final res = await sb.rpc('get_unread_message_total');
      return (res as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<List<Map<String, dynamic>>> listFactories() async {
    _ready();
    final rows = await sb
        .from('factories')
        .select('id, name, logo')
        .eq('status', 'approved')
        .order('name', ascending: true);
    return rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// يفتح محادثة مع مصنع أو ينشئها.
  static Future<SFThread> ensureFactoryConversation(int factoryId) async {
    _ready();
    if (factoryId <= 0) throw Exception('معرّف المصنع غير صالح');
    if (AuthService.instance.profile?.accountType == 'factory') {
      throw Exception(
          'حساب المصنع يستقبل محادثات العملاء ولا يبدأ محادثة مع مصنع آخر');
    }

    Map<String, dynamic>? row = await sb
        .from('conversations')
        .select(_conversationSelect)
        .eq('factory_id', factoryId)
        .eq('individual_id', _uid)
        .maybeSingle();

    if (row == null) {
      try {
        row = await sb
            .from('conversations')
            .insert({'factory_id': factoryId, 'individual_id': _uid})
            .select(_conversationSelect)
            .single();
      } on PostgrestException catch (e) {
        // 23505: أنشأها طلب متزامن — نقرأها بدل الفشل.
        if (e.code != '23505') rethrow;
        row = await sb
            .from('conversations')
            .select(_conversationSelect)
            .eq('factory_id', factoryId)
            .eq('individual_id', _uid)
            .maybeSingle();
        if (row == null) rethrow;
      }
    }

    final peers = await _peers();
    final peer = peers['${row['id']}'];
    return SFThread(
      id: '${row['id']}',
      conversationId: (row['id'] as num).toInt(),
      factoryId: (row['factory_id'] as num?)?.toInt(),
      name: (peer?['peer_name'] as String?) ?? '',
      role: (peer?['peer_role'] as String?) ?? '',
      avatar: (peer?['peer_avatar'] as String?) ?? '',
      updated: DateTime.tryParse('${row['last_message_at'] ?? row['created_at']}')
              ?.toLocal() ??
          DateTime.now(),
    );
  }

  static Future<Map<String, Map<String, dynamic>>> _peers() async {
    try {
      final res = await sb.rpc('get_conversation_peers') as List<dynamic>?;
      final out = <String, Map<String, dynamic>>{};
      for (final r in res ?? []) {
        final m = Map<String, dynamic>.from(r as Map);
        out['${m['conversation_id']}'] = m;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  static Future<SFMessage> sendText(int conversationId, String text) async {
    _ready();
    final row = await sb
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': _uid,
          'body': text.length > 10000 ? text.substring(0, 10000) : text,
          'attachment_url': '',
          'attachment_type': '',
        })
        .select(_messageSelect)
        .single();
    return SFMessage.fromRow(Map<String, dynamic>.from(row), _uid);
  }

  /// يشترك في تغيّرات جدول الرسائل — البديل عن realtime في الويب.
  static RealtimeChannel? subscribe(void Function() onChange) {
    if (AuthService.instance.user == null) return null;
    return sb
        .channel('sf-messages-$_uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => onChange(),
        )
        .subscribe();
  }
}
