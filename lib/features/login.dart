import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/session.dart';
import '../ui/brand_logo.dart';
import '../ui/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _remember = true;
  bool _busy = false;
  bool _hidden = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).api.savedEmail().then((email) {
      if (email != null && mounted && _email.text.isEmpty) _email.text = email;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (email.isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email address and password.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).login(email, _password.text, remember: _remember);
      TextInput.finishAutofillContext();
      HapticFeedback.mediumImpact();
    } on ApiException catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: darkBars,
      child: Scaffold(
        backgroundColor: Brand.deep,
        body: Container(
          decoration: const BoxDecoration(gradient: Brand.heroGradient),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const BrandLockup(onDark: true, size: 32),
                      const SizedBox(height: 44),
                      Text('Welcome back.', style: display(38, color: const Color(0xFFF6F1E8))),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in to your sales workspace.',
                        style: theme.textTheme.bodyLarge?.copyWith(color: const Color(0xFFD8D0C2), height: 1.45),
                      ),
                      const SizedBox(height: 30),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Brand.card,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 40, offset: const Offset(0, 18))],
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autofillHints: const [AutofillHints.email, AutofillHints.username],
                            onSubmitted: (_) => _passwordFocus.requestFocus(),
                            decoration: const InputDecoration(
                              labelText: 'Email address',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            focusNode: _passwordFocus,
                            obscureText: _hidden,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: _hidden ? 'Show password' : 'Hide password',
                                icon: Icon(_hidden ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                                onPressed: () => setState(() => _hidden = !_hidden),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _remember,
                            onChanged: (v) => setState(() => _remember = v),
                            title: const Text('Keep me signed in', style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: const Text('Stored securely on this phone', style: TextStyle(fontSize: 12.5)),
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            child: _error == null
                                ? const SizedBox(width: double.infinity)
                                : Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Brand.red.withValues(alpha: .08),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(children: [
                                      const Icon(Icons.error_outline_rounded, color: Brand.red, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(_error!,
                                            style: const TextStyle(color: Brand.red, fontWeight: FontWeight.w600)),
                                      ),
                                    ]),
                                  ),
                          ),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                            child: _busy
                                ? const SizedBox(
                                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Text('Sign in to workspace'),
                                    SizedBox(width: 8),
                                    Icon(Icons.arrow_forward_rounded, size: 20),
                                  ]),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 22),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.verified_user_rounded, size: 15, color: Colors.white.withValues(alpha: .6)),
                        const SizedBox(width: 6),
                        Text(
                          'Secure connection · ${AppConfig.host}',
                          style: TextStyle(color: Colors.white.withValues(alpha: .6), fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ]),
                    ]),
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

