import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neostation/services/credential_store.dart';
import 'package:neostation/services/neosync/auth_service.dart';
import 'package:neostation/services/neosync/billing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_credential_backends.dart';

// Signing in, registering, the password and verification e-mails, and the
// billing calls had no time limit. A server that took the connection and then
// said nothing left the Login button spinning for as long as the socket lived,
// and the failure that did come back reached the screen as the client's
// English "Network error: …" text.

/// Never answers, and records each request and its abort trigger firing.
class _SilentClient extends http.BaseClient {
  int sent = 0;
  int aborted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sent++;
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) => aborted++);
    }
    return Completer<http.StreamedResponse>().future;
  }
}

/// Sends its headers at once, then never the body.
class _StallingClient extends http.BaseClient {
  int aborted = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Abortable) {
      request.abortTrigger?.then((_) => aborted++);
    }
    return http.StreamedResponse(StreamController<List<int>>().stream, 200);
  }
}

/// Answers every request at once with [status] and [body].
class _AnsweringClient extends http.BaseClient {
  _AnsweringClient(this.status, this.body);

  final int status;
  final String body;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream.value(body.codeUnits), status);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  const limit = Duration(milliseconds: 200);

  setUp(() async {
    // In memory, so nothing is written to the keyring or the user-data folder.
    CredentialStore.debugUseBackends(secure: MemoryBackend(), file: null);
    // The profile request is only made with a token to send.
    await CredentialStore.write('auth_token', 'stored-jwt');
  });

  tearDown(CredentialStore.debugReset);

  group('NeoSync sign-in requests', () {
    final calls = <String, Future<Map<String, dynamic>> Function(AuthService)>{
      'registering': (s) => s.register('player', 'p@example.com', 'secret12'),
      'signing in': (s) => s.login('p@example.com', 'secret12'),
      'verifying the e-mail': (s) => s.verifyEmail('token'),
      'checking the verification': (s) =>
          s.checkEmailVerificationStatus('p@example.com'),
      'resending the verification': (s) =>
          s.resendVerificationEmail('p@example.com'),
      'loading the profile': (s) => s.getProfile(),
      'asking for a password reset': (s) => s.forgotPassword('p@example.com'),
      'resetting the password': (s) => s.resetPassword('token', 'secret12'),
    };

    for (final MapEntry(key: name, value: call) in calls.entries) {
      test('$name gives up when the server never answers', () async {
        final client = _SilentClient();
        final auth = AuthService(requestTimeout: limit, profileTimeout: limit)
          ..httpClient = client;
        addTearDown(auth.dispose);

        final result = await call(auth).timeout(const Duration(seconds: 5));

        expect(result['success'], isFalse);
        expect(result['isNetworkError'], isTrue);
        expect(client.sent, 1);
        await pumpEventQueue();
        expect(client.aborted, 1, reason: 'the connection is closed');
      });
    }

    test('a server that sends its headers and then stalls is given up '
        'on', () async {
      final client = _StallingClient();
      final auth = AuthService(requestTimeout: limit)..httpClient = client;
      addTearDown(auth.dispose);

      final result = await auth
          .login('p@example.com', 'secret12')
          .timeout(const Duration(seconds: 5));

      expect(result['isNetworkError'], isTrue);
      await pumpEventQueue();
      expect(client.aborted, 1);
    });

    test("the server's own refusal is passed on as it was", () async {
      final auth = AuthService(requestTimeout: limit)
        ..httpClient = _AnsweringClient(401, '{"error":"Invalid credentials"}');
      addTearDown(auth.dispose);

      final result = await auth.login('p@example.com', 'wrong');

      expect(result['success'], isFalse);
      expect(result['message'], 'Invalid credentials');
      expect(result.containsKey('isNetworkError'), isFalse);
    });

    test('requests wait 15 seconds by default, the profile 10', () {
      expect(AuthService.defaultRequestTimeout, const Duration(seconds: 15));
      expect(AuthService().requestTimeout, const Duration(seconds: 15));
      expect(AuthService().profileTimeout, const Duration(seconds: 10));
    });
  });

  group('NeoSync billing requests', () {
    final calls =
        <String, Future<Map<String, dynamic>> Function(BillingService)>{
          'starting a checkout': (s) => s.createCheckoutSession(
            userId: '1',
            planName: 'mini',
            billingPeriod: 'monthly',
            email: 'p@example.com',
          ),
          'cancelling the subscription': (s) => s.cancelSubscription('1'),
          'loading the plans': (s) => s.getAvailablePlans(),
        };

    for (final MapEntry(key: name, value: call) in calls.entries) {
      test('$name gives up when the server never answers', () async {
        final client = _SilentClient();
        final billing = BillingService(client: client, requestTimeout: limit);

        final result = await call(billing).timeout(const Duration(seconds: 5));

        expect(result['success'], isFalse);
        expect(result['isNetworkError'], isTrue);
        expect(client.sent, 1);
        await pumpEventQueue();
        expect(client.aborted, 1, reason: 'the connection is closed');
      });
    }

    test("the server's own refusal is passed on as it was", () async {
      final billing = BillingService(
        client: _AnsweringClient(500, '{"error":"Plans unavailable"}'),
        requestTimeout: limit,
      );

      final result = await billing.getAvailablePlans();

      expect(result['success'], isFalse);
      expect(result['message'], 'Plans unavailable');
      expect(result.containsKey('isNetworkError'), isFalse);
    });

    test('requests wait 15 seconds by default', () {
      expect(BillingService.defaultRequestTimeout, const Duration(seconds: 15));
      expect(BillingService().requestTimeout, const Duration(seconds: 15));
    });
  });
}
