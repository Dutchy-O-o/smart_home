import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

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
        state = AuthState.authenticated;
        safePrint('2. Result: USER LET IN!');
      } else {
        state = AuthState.unauthenticated;
        safePrint('2. Result: VAULT EMPTY, REDIRECTING TO LOGIN.');
      }
    } catch (e) {
      safePrint('!!! ERROR DURING SESSION CHECK: $e');
      state = AuthState.unauthenticated;
    }
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
      state = AuthState.unauthenticated;
    } catch (e) {
      safePrint('Error signing out: $e');
      // Even if there's an error, we force state to unauthenticated
      state = AuthState.unauthenticated;
    }
  }
}

