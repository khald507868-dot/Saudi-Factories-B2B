import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../services/auth_service.dart';

class AccountGate extends StatefulWidget {
  const AccountGate({super.key, required this.child, this.auth});
  final Widget child;
  final AuthService? auth;
  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> with WidgetsBindingObserver {
  Timer? _approvalTimer;
  bool _refreshing = false;
  AuthService get auth => widget.auth ?? AuthService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _approvalTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if ((state == null || state == AppLifecycleState.resumed) &&
          ['pending', 'rejected', 'error'].contains(auth.accessState)) {
        _refresh(silent: true);
      }
    });
  }

  Future<void> _refresh({bool silent = false}) async {
    if (_refreshing || auth.user == null || auth.accessState == 'checking') {
      return;
    }
    _refreshing = true;
    try {
      await auth.refreshProfile(silent: silent);
    } finally {
      _refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _approvalTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: auth,
    builder: (context, _) {
      final state = auth.accessState;
      final blocked = state != 'ready' && state != 'signed_out';
      return Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: blocked,
            child: Offstage(offstage: blocked, child: widget.child),
          ),
          if (blocked)
            Positioned.fill(
              child: state == 'email_required'
                  ? VerifyEmailPage(email: auth.user?.email ?? '', auth: auth)
                  : Scaffold(
                      body: SafeArea(
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.hourglass_top,
                                  size: 60,
                                  color: Color(0xff386641),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  context.t(
                                    state == 'rejected'
                                        ? 'auth_rejected_title'
                                        : state == 'checking'
                                        ? 'auth_checking'
                                        : state == 'error'
                                        ? 'auth_check_failed'
                                        : 'auth_pending_title',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (state == 'pending' || state == 'rejected')
                                  Text(
                                    context.t(
                                      state == 'rejected'
                                          ? 'auth_rejected_hint'
                                          : 'auth_pending_hint',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                if (state == 'rejected' &&
                                    auth.rejectionReason != null)
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(
                                      auth.rejectionReason!,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                const SizedBox(height: 20),
                                if (state == 'checking')
                                  const CircularProgressIndicator()
                                else ...[
                                  ElevatedButton(
                                    onPressed: _refresh,
                                    child: Text(
                                      context.t('auth_check_approval'),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      try {
                                        await auth.signOut();
                                      } catch (_) {
                                        /* Keep the gate closed; retry remains available. */
                                      }
                                    },
                                    child: Text(context.t('auth_signout')),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      );
    },
  );
}

class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({
    super.key,
    required this.email,
    this.onVerified,
    this.auth,
  });
  final String email;
  final VoidCallback? onVerified;
  final AuthService? auth;
  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  AuthService get auth => widget.auth ?? AuthService.instance;
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false, _failed = false;
  String? _message;
  DateTime? _resendAt;
  Timer? _timer;
  bool get _validEmail =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim());
  int get seconds => _resendAt == null
      ? 0
      : (_resendAt!.difference(DateTime.now()).inSeconds + 1).clamp(0, 60);
  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await auth.verifyEmail(_email.text, _code.text);
      if (mounted) widget.onVerified?.call();
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'auth_code_failed';
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_busy || seconds > 0) return;
    if (!_validEmail) {
      setState(() {
        _message = 'field_email';
        _failed = true;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      await auth.resendCode(_email.text);
      if (!mounted) return;
      setState(() {
        _message = 'auth_code_sent';
        _failed = false;
        _resendAt = DateTime.now().add(const Duration(seconds: 60));
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {});
        if (seconds == 0) timer.cancel();
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'auth_resend_failed';
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.t('auth_verify_title')),
      actions: [
        if (auth.user != null)
          IconButton(
            tooltip: context.t('auth_signout'),
            onPressed: _busy
                ? null
                : () async {
                    try {
                      await auth.signOut();
                    } catch (_) {
                      if (mounted) {
                        setState(() {
                          _message = 'auth_check_failed';
                          _failed = true;
                        });
                      }
                    }
                  },
            icon: const Icon(Icons.logout),
          ),
      ],
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.mark_email_unread_outlined,
                size: 64,
                color: Color(0xff386641),
              ),
              const SizedBox(height: 20),
              Text(context.t('auth_verify_hint'), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextFormField(
                controller: _email,
                enabled: !_busy,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(
                  labelText: context.t('field_email'),
                ),
                validator: (v) => _validEmail ? null : context.t('field_email'),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _code,
                enabled: !_busy,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                style: const TextStyle(fontSize: 28, letterSpacing: 6),
                decoration: InputDecoration(
                  labelText: context.t('auth_code_label'),
                ),
                validator: (v) => RegExp(r'^\d{6,10}$').hasMatch(v ?? '')
                    ? null
                    : context.t('auth_code_failed'),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    context.t(_message!),
                    style: TextStyle(
                      color: _failed ? Colors.red : const Color(0xff386641),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _busy ? null : _verify,
                child: Text(
                  context.t(_busy ? 'auth_checking' : 'auth_verify_action'),
                ),
              ),
              TextButton(
                onPressed: _busy || seconds > 0 ? null : _resend,
                child: Text(
                  '${context.t('auth_resend')}${seconds > 0 ? ' ($seconds)' : ''}',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
