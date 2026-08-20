// ============================================================
//  إعدادات الاتصال بـ Supabase
//  يُحمَّل في <head> قبل أي سكربت يستخدم قاعدة البيانات.
//
//  المفتاح هنا عام ومقصود كشفه — الحماية الحقيقية
//  من سياسات RLS في schema.sql، لا من إخفاء المفتاح.
//  لا تضع مفتاح sb_secret_ هنا إطلاقًا.
// ============================================================

var SUPABASE_URL = "https://yhofxryhlrrwzztfowpa.supabase.co";
var SUPABASE_KEY = "sb_publishable_ur0SfOOGa552ZvQf2icdfg_6xVpw-yM";

// عميل مشترك لكل الصفحات
var sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
