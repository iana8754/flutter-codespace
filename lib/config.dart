import 'package:supabase_flutter/supabase_flutter.dart';

// Вставьте сюда данные из Supabase: Project Settings -> API
const kSupabaseUrl = 'https://ВАШ-ПРОЕКТ.supabase.co';
const kSupabaseAnonKey = 'ВАШ_ANON_PUBLIC_KEY';

SupabaseClient get supa => Supabase.instance.client;
