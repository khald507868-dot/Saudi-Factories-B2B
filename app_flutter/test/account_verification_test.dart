import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:saudi_factories/core/i18n.dart';
import 'package:saudi_factories/pages/account_gate.dart';
import 'package:saudi_factories/services/auth_service.dart';

const uid = '10000000-0000-4000-8000-000000000001';

class MemoryAuthStorage extends GotrueAsyncStorage {
  final values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

class AuthFixture {
  bool confirmed = true, autoConfirm = false, profileFailure = false;
  bool signupSession = false, admin = false;
  String accountType = 'individual', factoryStatus = 'pending';
  int signups = 0, resends = 0, factoryReads = 0;
  late final client = SupabaseClient(
    'https://auth-tests.invalid',
    'test-key',
    authOptions: AuthClientOptions(
      autoRefreshToken: false,
      pkceAsyncStorage: MemoryAuthStorage(),
    ),
    httpClient: MockClient(handle),
  );
  late final auth = AuthService.forTesting(client, MockClient(handle));

  Map<String, dynamic> get user => {
    'id': uid,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'member@example.test',
    'created_at': '2026-01-01T00:00:00Z',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    if (confirmed) 'email_confirmed_at': '2026-01-01T00:00:00Z',
  };

  Map<String, dynamic> get session {
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({'sub': uid, 'exp': 4102444800})))
        .replaceAll('=', '');
    return {
      'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.test',
      'refresh_token': 'test-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': user,
    };
  }

  Future<http.Response> handle(http.Request request) async {
    Object? data;
    var status = 200;
    switch (request.url.path) {
      case '/auth/v1/settings':
        data = {'mailer_autoconfirm': autoConfirm};
      case '/auth/v1/token':
        data = session;
      case '/auth/v1/user':
        data = user;
      case '/auth/v1/logout':
        return http.Response('', 204, request: request);
      case '/auth/v1/signup':
        signups++;
        data = signupSession ? session : user;
      case '/auth/v1/resend':
        resends++;
        data = {};
      case '/auth/v1/verify':
        final body = jsonDecode(request.body) as Map;
        if (body['token'] != '123456') {
          status = 403;
          data = {
            'code': 'otp_expired',
            'msg': 'Token has expired or is invalid',
          };
        } else {
          confirmed = true;
          data = session;
        }
      case '/rest/v1/profiles':
        status = profileFailure ? 403 : 200;
        data = profileFailure
            ? {'code': '42501', 'message': 'unavailable'}
            : {
                'account_type': accountType,
                'full_name': 'Member',
                'is_admin': admin,
              };
      case '/rest/v1/factories':
        factoryReads++;
        data = {
          'status': factoryStatus,
          'rejection_reason': 'Documents incomplete',
        };
      default:
        throw StateError('Unexpected request ${request.url.path}');
    }
    return http.Response(
      jsonEncode(data),
      status,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  Future<void> login() =>
      auth.signIn('member@example.test', 'password123').then((_) {});
  Future<void> close() async {
    auth.dispose();
    await client.dispose();
  }
}

Widget host(AuthFixture f, {Widget? page}) => I18nScope(
  i18n: I18n('ar'),
  child: MaterialApp(
    builder: (context, child) => AccountGate(auth: f.auth, child: child!),
    home: page ?? const Scaffold(body: Text('protected content')),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AuthFixture f;
  setUp(() {
    f = AuthFixture();
  });
  tearDown(() async {
    await f.close();
  });

  test('restored session rechecks confirmation with the server', () async {
    await f.client.auth.signInWithPassword(
      email: 'member@example.test',
      password: 'password123',
    );
    f.confirmed = false;
    await f.auth.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(f.auth.ready, isTrue);
    expect(f.auth.accessState, 'email_required');
    expect(f.auth.isSignedIn, isFalse);
  });

  test(
    'unconfirmed email cannot access even when a session is returned',
    () async {
      f.confirmed = false;
      await f.login();
      expect(f.auth.accessState, 'email_required');
      expect(f.auth.isSignedIn, isFalse);
      expect(f.auth.profile, isNull);
    },
  );

  test(
    'signup waits for OTP and fails closed if confirmation is disabled',
    () async {
      f.confirmed = false;
      await f.auth.signUp(
        email: 'member@example.test',
        password: 'password123',
        data: {},
      );
      expect(f.auth.user, isNull);
      expect(f.auth.isSignedIn, isFalse);
      expect(f.signups, 1);
      f.autoConfirm = true;
      await expectLater(
        f.auth.signUp(
          email: 'member@example.test',
          password: 'password123',
          data: {},
        ),
        throwsA(isA<AuthException>()),
      );
      expect(f.signups, 1);
      expect(f.auth.isSignedIn, isFalse);
    },
  );

  test(
    'unexpected signup session is cleared instead of admitting the user',
    () async {
      f.signupSession = true;
      await expectLater(
        f.auth.signUp(
          email: 'member@example.test',
          password: 'password123',
          data: {},
        ),
        throwsA(isA<AuthException>()),
      );
      expect(f.client.auth.currentSession, isNull);
      expect(f.auth.isSignedIn, isFalse);
    },
  );

  test(
    'invalid OTP stays blocked; valid OTP still needs factory approval',
    () async {
      f.confirmed = false;
      f.accountType = 'factory';
      await expectLater(
        f.auth.verifyEmail('member@example.test', '000000'),
        throwsA(isA<AuthException>()),
      );
      expect(f.auth.isSignedIn, isFalse);
      await f.auth.verifyEmail('member@example.test', '123456');
      expect(f.auth.accessState, 'pending');
      expect(f.auth.isSignedIn, isFalse);
      f.factoryStatus = 'approved';
      await f.auth.refreshProfile();
      expect(f.auth.isSignedIn, isTrue);
      f.factoryStatus = 'rejected';
      await f.auth.refreshProfile();
      expect(f.auth.accessState, 'rejected');
      expect(f.auth.isSignedIn, isFalse);
    },
  );

  test('unavailable or invalid profile cannot bypass access checks', () async {
    f.profileFailure = true;
    await f.login();
    expect(f.auth.accessState, 'error');
    expect(f.auth.isSignedIn, isFalse);
    f.profileFailure = false;
    f.accountType = 'unknown';
    await f.auth.refreshProfile();
    expect(f.auth.accessState, 'error');
    f.accountType = 'individual';
    await f.auth.refreshProfile();
    expect(f.auth.isSignedIn, isTrue);
  });

  testWidgets(
    'waiting page hides protected content until server approves automatically',
    (tester) async {
      f.accountType = 'factory';
      await tester.runAsync(f.login);
      await tester.pumpWidget(host(f));
      await tester.pumpAndSettle();
      expect(find.text(I18n('ar').t('auth_pending_title')), findsOneWidget);
      expect(find.text('protected content'), findsNothing);
      f.factoryStatus = 'approved';
      await tester.pump(const Duration(seconds: 31));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.text('protected content'), findsOneWidget);
      expect(f.auth.isSignedIn, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'rejection reason stays on waiting page and sign out remains available',
    (tester) async {
      f.accountType = 'factory';
      f.factoryStatus = 'rejected';
      await tester.runAsync(f.login);
      await tester.pumpWidget(host(f));
      await tester.pumpAndSettle();
      expect(find.text('Documents incomplete'), findsOneWidget);
      expect(find.text('protected content'), findsNothing);
      await tester.tap(find.text(I18n('ar').t('auth_signout')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(f.auth.user, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('OTP screen rejects invalid code and throttles resending', (
    tester,
  ) async {
    await tester.runAsync(() async => f.auth);
    var verified = false;
    await tester.pumpWidget(
      I18nScope(
        i18n: I18n('ar'),
        child: MaterialApp(
          home: VerifyEmailPage(
            email: 'member@example.test',
            auth: f.auth,
            onVerified: () {
              verified = true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '000000');
    await tester.tap(find.text(I18n('ar').t('auth_verify_action')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(verified, isFalse);
    expect(find.text(I18n('ar').t('auth_code_failed')), findsOneWidget);
    await tester.ensureVisible(find.text(I18n('ar').t('auth_resend')));
    await tester.runAsync(() async {
      await tester.tap(find.text(I18n('ar').t('auth_resend')));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
    expect(f.resends, 1);
    final resend = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '${I18n('ar').t('auth_resend')} (60)'),
    );
    expect(resend.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
