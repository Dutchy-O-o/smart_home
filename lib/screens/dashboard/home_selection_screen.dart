import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../constants/app_colors.dart';
import '../../providers/home_provider.dart';
import '../../providers/auth_provider.dart';
import 'dashboard_screen.dart';
import '../auth/login_screen.dart';

class HomeSelectionScreen extends ConsumerStatefulWidget {
  const HomeSelectionScreen({super.key});

  @override
  ConsumerState<HomeSelectionScreen> createState() => _HomeSelectionScreenState();
}

class _HomeSelectionScreenState extends ConsumerState<HomeSelectionScreen> {
  List<dynamic> _homes = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchHomes();
  }

  Future<void> _fetchHomes() async {
    try {
      final session = await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
      final token = session.userPoolTokensResult.value.idToken.raw;

      final String apiUrl = 'https://zz3kr12z0f.execute-api.us-east-1.amazonaws.com/prod/homes';

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _homes = data['homes'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = "Failed to load homes (\${response.statusCode}): \${response.body}";
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Connection error: $e";
          _isLoading = false;
        });
      }
    }
  }

  void _selectHome(Map<String, dynamic> home) {
    ref.read(selectedHomeProvider.notifier).setHome(home);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const DashboardScreen()),
    );
  }

  void _handleLogout() {
    ref.read(authProvider.notifier).signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.accentRed),
            onPressed: _handleLogout,
            tooltip: "Logout",
          )
        ],
      ),
      body: SafeArea(
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator(color: AppColors.primaryBlue)
              : _errorMessage.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(_errorMessage, style: const TextStyle(color: AppColors.accentRed), textAlign: TextAlign.center),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Text(
                          "Which home would you like to enter?",
                          style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 48),
                        if (_homes.isEmpty)
                          const Text(
                            "No registered homes found.",
                            style: TextStyle(color: AppColors.textGrey, fontSize: 16),
                          )
                        else
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 24,
                            runSpacing: 24,
                            children: _homes.map((home) {
                              final isGuest = (home['role']?.toString().toLowerCase() == 'guest');
                              final homeName = home['home_name'] ?? 'Home';

                              return GestureDetector(
                                onTap: () => _selectHome(home),
                                child: Column(
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        color: isGuest ? AppColors.accentOrange.withOpacity(0.1) : AppColors.primaryBlue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: isGuest ? AppColors.accentOrange.withOpacity(0.6) : AppColors.primaryBlue.withOpacity(0.6),
                                          width: 2,
                                        ),
                                      ),
                                      child: Icon(
                                        isGuest ? Icons.vpn_key_outlined : Icons.home_rounded,
                                        size: 48,
                                        color: isGuest ? AppColors.accentOrange : AppColors.primaryBlue,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      homeName,
                                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      (home['role'] ?? 'Unknown').toString().toUpperCase(),
                                      style: TextStyle(
                                        color: isGuest ? AppColors.accentOrange : AppColors.primaryBlue,
                                        fontSize: 12,
                                      ),
                                    )
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
        ),
      ),
    );
  }
}
