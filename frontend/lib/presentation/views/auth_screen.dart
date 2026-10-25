import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../viewmodels/auth_view_model.dart';
import '../theme/nerilum_theme.dart';
import '../widgets/brand_backdrop.dart';

enum AuthMode { login, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.mode});

  final AuthMode mode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthViewModel? _viewModel;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _acceptedDemo = false;
  bool _submitted = false;
  bool _confirmationSent = false;

  bool get _registering => widget.mode == AuthMode.register;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel == null) {
      _viewModel = AppScope.of(context).createAuthViewModel();
      _viewModel!.addListener(_onAuthChanged);
    }
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onAuthChanged);
    _viewModel?.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _submit() async {
    if (_viewModel!.busy) return;
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    if (_registering) {
      if (_viewModel!.isDemo && !_acceptedDemo) {
        _message('Acepta continuar en modo demostración.');
        return;
      }
      final created = await _viewModel!.register(
        _email.text,
        _password.text,
        _name.text,
      );
      if (!mounted) return;
      if (created) {
        if (_viewModel!.requiresEmailConfirmation) {
          setState(() => _confirmationSent = true);
        } else {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      } else if (_viewModel!.error != null) {
        _message(_viewModel!.error!);
      }
      return;
    }
    final loggedIn = await _viewModel!.login(_email.text, _password.text);
    if (!mounted) return;
    if (loggedIn) {
      if (_viewModel!.isDemo) {
        AppScope.of(context).mainViewModel.refreshHistory();
        Navigator.of(context).pushNamedAndRemoveUntil('/app', (_) => false);
      }
      // En modo Supabase, el listener global de onAuthStateChange realiza
      // restauración del historial y navegación una sola vez.
    } else if (_viewModel!.error != null) {
      _message(_viewModel!.error!);
    }
  }

  Widget _passwordField({bool confirmation = false}) {
    final obscure = confirmation ? _obscureConfirmation : _obscurePassword;
    return TextFormField(
      controller: confirmation ? _confirmation : _password,
      obscureText: obscure,
      autofillHints: confirmation ? null : const [AutofillHints.password],
      textInputAction: confirmation
          ? TextInputAction.done
          : (_registering ? TextInputAction.next : TextInputAction.done),
      onFieldSubmitted: (_) {
        if (confirmation || !_registering) _submit();
      },
      decoration: InputDecoration(
        labelText: confirmation ? 'Confirmar contraseña' : 'Contraseña',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
          onPressed: () => setState(() {
            if (confirmation) {
              _obscureConfirmation = !obscure;
            } else {
              _obscurePassword = !obscure;
            }
          }),
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Introduce tu contraseña';
        if (confirmation && value != _password.text) {
          return 'Las contraseñas no coinciden';
        }
        if (_registering && !confirmation && value.length < 8) {
          return 'Usa al menos 8 caracteres';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = NerilumPalette.of(context);
    if (_confirmationSent) {
      return Scaffold(
        body: BrandBackdrop(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.mark_email_read_outlined, size: 64),
                    const SizedBox(height: 24),
                    const Text(
                      'Confirma tu correo',
                      style: TextStyle(fontSize: 26),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Si el registro corresponde a una cuenta nueva, recibirás un enlace en '
                      '${_email.text.trim()}. Revisa también la carpeta de spam. '
                      'Confirma tu correo antes de ingresar.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () =>
                          Navigator.of(context).pushReplacementNamed('/login'),
                      child: const Text('Ir a iniciar sesión'),
                    ),
                    TextButton(
                      onPressed: _viewModel!.busy
                          ? null
                          : () async {
                              final sent = await _viewModel!.resend(
                                _email.text,
                              );
                              if (!mounted) return;
                              _message(
                                sent
                                    ? 'Solicitud de reenvío enviada. Revisa tu correo.'
                                    : _viewModel!.error!,
                              );
                            },
                      child: const Text('Reenviar confirmación'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: BrandBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  autovalidateMode: _submitted
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: 'Volver',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                      ),
                      SizedBox(height: _registering ? 4 : 24),
                      Center(child: BrandMark(size: _registering ? 60 : 90)),
                      SizedBox(height: _registering ? 24 : 36),
                      Text(
                        _registering ? 'Crear cuenta' : 'Iniciar sesión',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _registering
                            ? 'Únete para comenzar a explorar.'
                            : 'Accede a tu cuenta',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: colors.textSecondary,
                        ),
                      ),
                      SizedBox(height: _registering ? 28 : 36),
                      if (_registering) ...[
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Nombre',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Introduce tu nombre'
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) {
                            return 'Introduce tu correo electrónico';
                          }
                          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(email)) {
                            return 'Introduce un correo válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      _passwordField(),
                      if (_registering) ...[
                        const SizedBox(height: 12),
                        _passwordField(confirmation: true),
                        const SizedBox(height: 12),
                        if (_viewModel!.isDemo)
                          CheckboxListTile(
                            value: _acceptedDemo,
                            onChanged: (value) =>
                                setState(() => _acceptedDemo = value ?? false),
                            title: const Text(
                              'Acepto continuar en modo demostración',
                              style: TextStyle(fontSize: 14),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            activeColor: colors.mint,
                            checkColor: colors.mintDarkText,
                          ),
                      ] else ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => _message(
                              'Recuperación de contraseña disponible al conectar el backend.',
                            ),
                            child: const Text('¿Olvidaste tu contraseña?'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      ElevatedButton(
                        onPressed: _viewModel!.busy ? null : _submit,
                        child: Row(
                          children: [
                            Expanded(
                              child: Center(
                                child: Text(
                                  _registering ? 'Crear cuenta' : 'Ingresar',
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_forward),
                          ],
                        ),
                      ),
                      if (!_registering && _viewModel!.isDemo) ...[
                        const SizedBox(height: 14),
                        Text(
                          'Demo: demo@nerilum.app / Demo1234',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      Divider(color: colors.border),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              _registering
                                  ? '¿Ya tienes cuenta?'
                                  : '¿No tienes cuenta?',
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context)
                                .pushReplacementNamed(
                                  _registering ? '/login' : '/register',
                                ),
                            child: Text(
                              _registering ? 'Inicia sesión' : 'Regístrate',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
