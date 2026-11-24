import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/session.dart';
import '../../core/widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with SingleTickerProviderStateMixin {
  late final TabController tab = TabController(length: 2, vsync: this);
  final nombre = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();
  final pass2 = TextEditingController();
  bool busy = false, ver = false;

  String _traduce(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Correo o contraseña incorrectos.';
      case 'email-already-in-use':
        return 'Ese correo ya está registrado.';
      case 'weak-password':
        return 'La contraseña es muy débil.';
      case 'invalid-email':
        return 'Correo inválido.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera unos minutos.';
      default:
        return e.message ?? e.code;
    }
  }

  Future<void> _go() async {
    final registro = tab.index == 1;
    if (email.text.trim().isEmpty || pass.text.isEmpty) return toast(context, 'Captura correo y contraseña.', error: true);
    if (registro) {
      if (nombre.text.trim().isEmpty) return toast(context, 'Captura tu nombre.', error: true);
      if (pass.text.length < 8) return toast(context, 'Usa al menos 8 caracteres.', error: true);
      if (pass.text != pass2.text) return toast(context, 'Las contraseñas no coinciden.', error: true);
    }
    setState(() => busy = true);
    try {
      if (registro) {
        await Session.I.registrar(nombre.text, email.text, pass.text);
      } else {
        await Session.I.login(email.text, pass.text);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) toast(context, _traduce(e), error: true);
    } catch (e) {
      if (mounted) toast(context, errMsg(e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AnimatedBuilder(
                  animation: tab,
                  builder: (_, __) => Column(mainAxisSize: MainAxisSize.min, children: [
                    Image.asset('assets/logo/logo.png', height: 72, errorBuilder: (_, __, ___) => const Icon(Icons.inventory, size: 64)),
                    const SizedBox(height: 8),
                    const Text('CARTÓN BOOM', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                    const Text('Plataforma integral de operación'),
                    const SizedBox(height: 16),
                    TabBar(controller: tab, tabs: const [Tab(text: 'Iniciar sesión'), Tab(text: 'Registrarme')]),
                    const SizedBox(height: 16),
                    if (tab.index == 1) ...[textField(nombre, 'Nombre completo'), const SizedBox(height: 12)],
                    TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo electrónico', prefixIcon: Icon(Icons.mail_outline))),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pass,
                      obscureText: !ver,
                      onSubmitted: (_) => tab.index == 0 ? _go() : null,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(icon: Icon(ver ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => ver = !ver)),
                      ),
                    ),
                    if (tab.index == 1) ...[
                      const SizedBox(height: 12),
                      TextField(controller: pass2, obscureText: !ver, decoration: const InputDecoration(labelText: 'Confirmar contraseña', prefixIcon: Icon(Icons.lock_outline))),
                      const SizedBox(height: 8),
                      Text('Tu cuenta quedará pendiente hasta que un administrador la apruebe y te asigne un rol.', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: busy ? null : _go, child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(tab.index == 0 ? 'Entrar' : 'Crear cuenta')),
                    ),
                    if (tab.index == 0)
                      TextButton(
                        onPressed: () async {
                          if (email.text.trim().isEmpty) return toast(context, 'Escribe tu correo primero.', error: true);
                          try {
                            await Session.I.resetPassword(email.text);
                            if (mounted) toast(context, 'Te enviamos un correo para restablecer tu contraseña.');
                          } catch (e) {
                            if (mounted) toast(context, errMsg(e), error: true);
                          }
                        },
                        child: const Text('Olvidé mi contraseña'),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PendientePage extends StatelessWidget {
  const PendientePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: AnimatedBuilder(
                  animation: Session.I,
                  builder: (_, __) => Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.hourglass_top, size: 56),
                    const SizedBox(height: 12),
                    Text('Hola, ${Session.I.nombre}', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      Session.I.profile == null
                          ? 'No encontramos tu perfil. Cierra sesión y regístrate de nuevo, o pide al administrador que lo cree.'
                          : 'Tu cuenta está pendiente de aprobación. Un administrador debe activarla y asignarte un rol.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(onPressed: () => Session.I.logout(), icon: const Icon(Icons.logout), label: const Text('Cerrar sesión')),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}
