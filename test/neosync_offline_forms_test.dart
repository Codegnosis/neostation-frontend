import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/screens/neo_sync_screen/login_screen/plan_selection_view.dart';
import 'package:neostation/services/credential_store.dart';
import 'package:neostation/services/neosync/auth_service.dart';
import 'package:neostation/services/neosync/billing_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/themes/corner_radii.dart';
import 'package:neostation/widgets/auth_form.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_credential_backends.dart';

// With NeoSync out of reach, signing in left the Login button spinning for as
// long as the socket lived and then showed the client's English "Network
// error: …" text. Each A press while it spun sent another request, and backing
// out of the password-reset view mid-request left the Login button spinning.

/// Never answers, and counts the requests it was sent.
class _SilentClient extends http.BaseClient {
  int sent = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    sent++;
    return Completer<http.StreamedResponse>().future;
  }
}

class _SignedIn extends AuthService {
  @override
  bool get isLoggedIn => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const limit = Duration(milliseconds: 200);
  final unreachable = AppLocale.en[AppLocale.neoSyncUnreachable] as String;
  String en(String key) => AppLocale.en[key] as String;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/gamepads'),
          (call) async => <dynamic>[],
        );
    await FlutterLocalization.instance.ensureInitialized();
    FlutterLocalization.instance.init(
      mapLocales: [MapLocale('en', AppLocale.en)],
      initLanguageCode: 'en',
    );
    SfxService().setEnabled(false);
  });

  setUp(() {
    CredentialStore.debugUseBackends(secure: MemoryBackend(), file: null);
  });
  tearDown(CredentialStore.debugReset);

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    required AuthService auth,
    BillingService? billing,
  }) async {
    const size = Size(1280, 720);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(640, 480),
        minTextAdapt: true,
        builder: (context, _) => MaterialApp(
          localizationsDelegates:
              FlutterLocalization.instance.localizationsDelegates,
          supportedLocales: FlutterLocalization.instance.supportedLocales,
          theme: ThemeData(extensions: [CornerRadii.m()]),
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthService>.value(value: auth),
              if (billing != null)
                ChangeNotifierProvider<BillingService>.value(value: billing),
            ],
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Waits out the navigator's activation grace and key throttle, which drop
  /// early input.
  Future<void> pastGrace(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 180)),
  );

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await pastGrace(tester);
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  /// Leaves the text field being typed in, as B does, so the controller's
  /// presses reach the form.
  Future<void> leaveField(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
  }

  Finder loginButton() => find.byType(ElevatedButton);

  /// Types the e-mail and password. The password goes first: typed after the
  /// e-mail, the test's text input loses it to the rebuild the selection
  /// highlight makes when focus moves.
  Future<void> signInDetails(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(1), 'secret12');
    await tester.enterText(find.byType(TextFormField).at(0), 'p@example.com');
  }

  testWidgets('signing in with NeoSync out of reach says so, in the app '
      'language', (tester) async {
    final client = _SilentClient();
    final auth = AuthService(requestTimeout: limit)..httpClient = client;
    await pump(tester, AuthForm(onLoginSuccess: () {}), auth: auth);

    await signInDetails(tester);
    await tester.tap(loginButton());
    await tester.pump();
    expect(client.sent, 1);

    await tester.pump(limit * 2);
    await tester.pump();

    expect(find.text(unreachable), findsOneWidget);
    expect(find.textContaining('Network error'), findsNothing);
    expect(tester.widget<ElevatedButton>(loginButton()).onPressed, isNotNull);
  });

  testWidgets('A while a sign-in is out sends no second request', (
    tester,
  ) async {
    final client = _SilentClient();
    final auth = AuthService(requestTimeout: limit)..httpClient = client;
    await pump(tester, AuthForm(onLoginSuccess: () {}), auth: auth);

    await signInDetails(tester);
    await leaveField(tester);
    // From the e-mail field down past the password to Login, then A. S, not
    // the arrow: the framework's own arrow-key traversal would focus a field.
    await press(tester, LogicalKeyboardKey.keyS);
    await press(tester, LogicalKeyboardKey.keyS);
    await press(tester, LogicalKeyboardKey.enter);
    expect(client.sent, 1, reason: 'A on Login signs in');

    await press(tester, LogicalKeyboardKey.enter);
    await press(tester, LogicalKeyboardKey.enter);
    expect(client.sent, 1, reason: 'the sign-in already out is still waiting');

    await tester.pump(limit * 2);
    await tester.pump();
  });

  testWidgets('B out of the password reset mid-request leaves Login usable', (
    tester,
  ) async {
    final client = _SilentClient();
    final auth = AuthService(requestTimeout: limit)..httpClient = client;
    await pump(tester, AuthForm(onLoginSuccess: () {}), auth: auth);

    await tester.tap(find.text(en(AppLocale.forgotPasswordQuestion)));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, 'p@example.com');
    await tester.tap(find.text(en(AppLocale.sendResetToken)));
    await tester.pump();
    expect(client.sent, 1);
    await leaveField(tester);

    await press(tester, LogicalKeyboardKey.backspace);

    expect(find.text(en(AppLocale.login)), findsOneWidget);
    expect(tester.widget<ElevatedButton>(loginButton()).onPressed, isNotNull);

    await tester.pump(limit * 2);
    await tester.pump();
  });

  testWidgets('a request left behind by B, answering later, leaves the '
      'sign-in that followed alone', (tester) async {
    final client = _SilentClient();
    final auth = AuthService(requestTimeout: limit)..httpClient = client;
    await pump(tester, AuthForm(onLoginSuccess: () {}), auth: auth);

    await tester.tap(find.text(en(AppLocale.forgotPasswordQuestion)));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, 'p@example.com');
    await tester.tap(find.text(en(AppLocale.sendResetToken)));
    await tester.pump();
    await leaveField(tester);
    await press(tester, LogicalKeyboardKey.backspace);

    // Signs in half way through the reset request's wait.
    await tester.pump(limit ~/ 2);
    // Each field tapped before typing, as a user would: typing into one that
    // was never focused loses the text to the selection highlight's rebuild.
    for (final (field, text) in [(0, 'p@example.com'), (1, 'secret12')]) {
      await tester.tap(find.byType(TextFormField).at(field));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).at(field), text);
      await tester.pump();
    }
    await leaveField(tester);
    await tester.tap(loginButton());
    await tester.pump();
    expect(client.sent, 2);

    // The reset request gives up; the sign-in is still out.
    await tester.pump(limit * 3 ~/ 4);

    expect(
      tester.widget<ElevatedButton>(loginButton()).onPressed,
      isNull,
      reason: 'the sign-in is still running',
    );
    expect(find.text(unreachable), findsNothing);

    await tester.pump(limit);
    await tester.pump();
    expect(find.text(unreachable), findsOneWidget);
  });

  testWidgets('the plans with NeoSync out of reach say so, in the app '
      'language', (tester) async {
    final billing = BillingService(
      client: _SilentClient(),
      requestTimeout: limit,
    );
    await pump(
      tester,
      PlanSelectionView(
        initialPlans: const [],
        onUpgrade: (_, _) {},
        onCancel: () {},
        getPlanIcon: (_) => Icons.storage,
        onBack: () {},
      ),
      auth: _SignedIn(),
      billing: billing,
    );

    await tester.pump(limit * 2);
    await tester.pump();

    expect(find.text(unreachable), findsOneWidget);
    expect(find.textContaining('Network error'), findsNothing);
    expect(find.text(en(AppLocale.retry)), findsOneWidget);
  });
}
