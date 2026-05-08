import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';

import '../services/user_scope.dart';

// Represents the current authentication state
enum AuthState { initial, loading, authenticated, unauthenticated }

// Riverpod provider for AuthNotifier
final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// Cognito user attributes (email, given_name, preferred_username, sub, etc.)
/// Refreshed whenever the auth state flips back to authenticated.
final userAttributesProvider =
    FutureProvider<Map<String, String>>((ref) async {
  final auth = ref.watch(authProvider);
  if (auth != AuthState.authenticated) return const {};
  try {
    final attrs = await Amplify.Auth.fetchUserAttributes();
    return {
      for (final a in attrs) a.userAttributeKey.key: a.value,
    };
  } catch (e) {
    safePrint('Error fetching user attributes: $e');
    return const {};
  }
});

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Check current user status asynchronously, starts as initial.
    Future.microtask(() => checkCurrentUser());
    return AuthState.initial;
  }

  // Check if a user is currently signed in
 // Check if a user is currently signed in
  Future<void> checkCurrentUser() async {
    state = AuthState.loading;
    try {
      safePrint('--- SESSION CHECK STARTED ---');
      final session = await Amplify.Auth.fetchAuthSession();

      safePrint('1. Amplify Vault Status: ${session.isSignedIn ? "FILLED" : "EMPTY"}');

      if (session.isSignedIn) {
        await _activateUserScope();
        state = AuthState.authenticated;
        safePrint('2. Result: USER LET IN!');
      } else {
        await UserScope.clear();
        state = AuthState.unauthenticated;
        safePrint('2. Result: VAULT EMPTY, REDIRECTING TO LOGIN.');
      }
    } catch (e) {
      safePrint('!!! ERROR DURING SESSION CHECK: $e');
      state = AuthState.unauthenticated;
    }
  }

  /// Pull the Cognito user id (`sub`) and pin it on UserScope so any
  /// downstream SharedPreferences read is scoped to this account. Falls
  /// back to email if `sub` isn't available, then to nothing — services
  /// keep working unscoped if neither is reachable.
  ///
  /// After scoping, runs a one-time migration that copies any legacy
  /// unscoped data (from before the scoping change) into this user's
  /// namespace so existing mood history / alerts / scenes don't appear
  /// to vanish.
  Future<void> _activateUserScope() async {
    try {
      final session =
          await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
      final sub = session.userSubResult.value;
      if (sub.isNotEmpty) {
        await UserScope.setUser(sub);
        await _migrateLegacyData();
        return;
      }
    } catch (_) {/* try email next */}
    try {
      final attrs = await Amplify.Auth.fetchUserAttributes();
      final email = attrs
          .firstWhere(
            (a) => a.userAttributeKey.key == 'email',
            orElse: () => const AuthUserAttribute(
              userAttributeKey: CognitoUserAttributeKey.email,
              value: '',
            ),
          )
          .value;
      if (email.isNotEmpty) {
        await UserScope.setUser(email);
        await _migrateLegacyData();
      }
    } catch (e) {
      safePrint('Could not activate user scope: $e');
    }
  }

  /// Pre-scoping versions of the keys various services persist. New
  /// per-home keys (sensor history) are migrated separately via their
  /// own service entry points since they need the home id.
  static const _legacyBaseKeys = <String>[
    'alerts_v1',
    'mood_history_v1',
    'scene_slots_v1',
    'theme_mode_v1',
    'mood_state_v1',
    'profile_push_notifications',
  ];

  Future<void> _migrateLegacyData() async {
    await UserScope.migrateLegacyKeys(_legacyBaseKeys);
  }

  // Sign up a new user
  Future<bool> signUp({required String email, required String password}) async {
    state = AuthState.loading;
    try {
      final result = await Amplify.Auth.signUp(
        username: email,
        password: password,
        options: SignUpOptions(
          userAttributes: {
            AuthUserAttributeKey.email: email,
          },
        ),
      );
      state = AuthState.unauthenticated;
      return result.isSignUpComplete || result.nextStep.signUpStep == AuthSignUpStep.confirmSignUp;
    } catch (e) {
      safePrint('Error signing up: $e');
      state = AuthState.unauthenticated;
      rethrow;
    }
  }

  // Confirm sign up with OTP
  Future<bool> confirmSignUp({required String email, required String confirmationCode}) async {
    state = AuthState.loading;
    try {
      final result = await Amplify.Auth.confirmSignUp(
        username: email,
        confirmationCode: confirmationCode,
      );
      state = AuthState.unauthenticated;
      return result.isSignUpComplete;
    } catch (e) {
      safePrint('Error confirming sign up: $e');
      state = AuthState.unauthenticated;
      rethrow;
    }
  }

  // Sign in an existing user
  Future<bool> signIn({required String email, required String password}) async {
    state = AuthState.loading;
    try {
      final result = await Amplify.Auth.signIn(username: email, password: password);
      if (result.isSignedIn) {
        await _activateUserScope();
        state = AuthState.authenticated;
        return true;
      }
      state = AuthState.unauthenticated;
      return false;
    } catch (e) {
      safePrint('Error signing in: $e');
      state = AuthState.unauthenticated;
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    state = AuthState.loading;
    try {
      // Sign out globally from all devices
      await Amplify.Auth.signOut(
        options: const SignOutOptions(
          globalSignOut: true,
        ),
      );
      await UserScope.clear();
      state = AuthState.unauthenticated;
    } catch (e) {
      safePrint('Error signing out: $e');
      // Even if there's an error, we force state to unauthenticated
      await UserScope.clear();
      state = AuthState.unauthenticated;
    }
  }
}

