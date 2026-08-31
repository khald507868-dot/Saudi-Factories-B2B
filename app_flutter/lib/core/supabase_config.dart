// ============================================================
//  إعدادات الاتصال بـ Supabase — نفس مشروع نسخة الويب
//
//  المفتاح هنا عام ومقصود كشفه؛ الحماية الحقيقية من سياسات
//  RLS داخل الخادم لا من إخفاء المفتاح.
//  لا تضع مفتاح sb_secret_ هنا إطلاقاً — لا يوجد كود خادم يستخدمه.
// ============================================================

import 'package:supabase_flutter/supabase_flutter.dart';

const String kSupabaseUrl = 'https://yhofxryhlrrwzztfowpa.supabase.co';
const String kSupabaseKey = 'sb_publishable_ur0SfOOGa552ZvQf2icdfg_6xVpw-yM';

/// العميل المشترك — مقابل المتغيّر العام `sb` في نسخة الويب.
SupabaseClient get sb => Supabase.instance.client;

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: kSupabaseUrl,
    anonKey: kSupabaseKey,
  );
}

/// أسماء دِلاء التخزين كما في schema.sql.
class SFBuckets {
  static const String factoryMedia = 'factory-media';
  static const String chatMedia = 'chat-media';
}
