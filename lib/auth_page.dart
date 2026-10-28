import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false, _busy = false, _hide = true;

  Future<void> _submit() async {
    final email = _email.text.trim(), pass = _pass.text;
    if (email.isEmpty || pass.length < 6) {
      _msg('Введите e-mail и пароль (минимум 6 символов)');
      return;
    }
    setState(() => _busy = true);
    try {
      if (_register) {
        final r = await supa.auth.signUp(email: email, password: pass);
        if (r.session == null) _msg('Проверьте почту и подтвердите регистрацию');
      } else {
        await supa.auth.signInWithPassword(email: email, password: pass);
      }
    } on AuthException catch (e) {
      _msg(e.message);
    } catch (e) {
      _msg('Ошибка соединения');
    }
    if (mounted) setState(() => _busy = false);
  }

  void _msg(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                      color: c.primary, borderRadius: BorderRadius.circular(28)),
                  child: const Icon(Icons.cloud_rounded, size: 52, color: Colors.white),
                ),
                const SizedBox(height: 20),
                Text('Мой Диск',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Ваши файлы, фото и видео всегда с вами',
                    style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 32),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _deco('E-mail', Icons.mail_outline),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pass,
                  obscureText: _hide,
                  decoration: _deco('Пароль', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_register ? 'Создать аккаунт' : 'Войти'),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _register = !_register),
                  child: Text(_register
                      ? 'Уже есть аккаунт? Войти'
                      : 'Нет аккаунта? Зарегистрироваться'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _deco(String l, IconData i) => InputDecoration(
        labelText: l,
        prefixIcon: Icon(i),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      );
}
