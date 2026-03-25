import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'widgets/AppBottomBar.dart';
import 'SubmitFeedbackPage.dart';
import 'BackupDataPage.dart';
import 'AnalyticsPage.dart';
import 'LoginScreen.dart';
import 'EmployeesPage.dart';
import 'ChangeCredentialsPage.dart';
import 'ledgerlist.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _isClientLogin = false;
  int _shopCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkLoginType();
  }

  /// Check if current logged in user is client or employee
  Future<void> _checkLoginType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginType = prefs.getString('loginType') ?? 'client';
      setState(() {
        _isClientLogin = loginType.toString().toLowerCase() == 'client';
      });
      debugPrint('Login Type: $loginType, Is Client: $_isClientLogin');

      if (_isClientLogin) {
        _fetchShopCount();
      }
    } catch (e) {
      debugPrint('Error checking login type: $e');
    }
  }

  /// Fetch shop count from shop_list collection
  Future<void> _fetchShopCount() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('shop_list')
          .get();

      setState(() {
        _shopCount = snapshot.docs.length;
      });
    } catch (e) {
      debugPrint('Error fetching shop count: $e');
    }
  }

  /// 🔹 Simulate loading settings
  Future<void> _loadSettings() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// 🔹 Check if device is in landscape mode
  bool _isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  // ✅ Logout Confirmation Dialog
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.logout, color: Colors.red[700], size: 24),
              ),
              const SizedBox(width: 12),
              const Text(
                'Logout',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to logout?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You will need to login again to access your account.',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _performLogout(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  // ✅ Perform Logout
  Future<void> _performLogout(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (context.mounted) {
        _showSnackBar(context, 'Logged out successfully');

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error during logout: $e');
      if (context.mounted) {
        _showSnackBar(context, 'Failed to logout: $e', isError: true);
      }
    }
  }

  // ✅ Helper to show SnackBar
  void _showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ✅ Modern Settings Item Builder
  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    bool hasTrailingArrow = false,
    bool isLandscape = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 20 : 24,
          vertical: isLandscape ? 14 : 16,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (iconColor ?? const Color(0xFF4285F4)).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor ?? const Color(0xFF4285F4),
                size: isLandscape ? 22 : 24,
              ),
            ),
            SizedBox(width: isLandscape ? 14 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isLandscape ? 15 : 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: isLandscape ? 12 : 13,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            if (hasTrailingArrow)
              Icon(
                Icons.arrow_forward_ios,
                size: isLandscape ? 16 : 18,
                color: Colors.grey[400],
              ),
          ],
        ),
      ),
    );
  }

  // ✅ Shimmer Loading Effect
  Widget _buildShimmerLoading(bool isLandscape) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[50]!,
      period: const Duration(milliseconds: 1200),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: 8,
        separatorBuilder: (context, index) =>
            Divider(height: 1, thickness: 1, color: Colors.grey[200]),
        itemBuilder: (context, index) {
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 20 : 24,
              vertical: isLandscape ? 14 : 16,
            ),
            child: Row(
              children: [
                Container(
                  width: isLandscape ? 42 : 44,
                  height: isLandscape ? 42 : 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                SizedBox(width: isLandscape ? 14 : 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: isLandscape ? 14 : 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 200,
                        height: isLandscape ? 12 : 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = _isLandscape(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          elevation: 0,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1976D2), Color(0xFF4285F4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          foregroundColor: Colors.white,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          title: Text(
            'Settings',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: isLandscape ? 18 : 20,
              letterSpacing: 0.3,
            ),
          ),
          automaticallyImplyLeading: false,
        ),
        body: _isLoading
            ? _buildShimmerLoading(isLandscape)
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  SizedBox(height: isLandscape ? 12 : 16),

                  // Show Shop Count Card for ADMIN only
                  if (_isClientLogin) ...[
                    // Shop Count Card
                    Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isLandscape ? 20 : 24,
                        vertical: isLandscape ? 8 : 10,
                      ),
                      padding: EdgeInsets.all(isLandscape ? 14 : 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4285F4).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF4285F4).withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.store,
                                color: const Color(0xFF4285F4),
                                size: isLandscape ? 22 : 24,
                              ),
                              SizedBox(width: isLandscape ? 12 : 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Shops',
                                    style: TextStyle(
                                      fontSize: isLandscape ? 13 : 14,
                                      color: Colors.grey[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    _shopCount.toString(),
                                    style: TextStyle(
                                      fontSize: isLandscape ? 18 : 20,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF4285F4),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: isLandscape ? 16 : 18,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    ).wrapInGestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ShopsPage(),
                          ),
                        ).then((_) => _fetchShopCount()); // Refresh on return
                      },
                    ),

                    Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                    SizedBox(height: isLandscape ? 12 : 16),
                  ],

                  // Analytics & Insights - Only for ADMIN
                  if (_isClientLogin) ...[
                    _buildSettingsItem(
                      icon: Icons.analytics_outlined,
                      title: 'Analytics & Insights',
                      subtitle:
                          'Business analytics, trends & performance metrics',
                      hasTrailingArrow: true,
                      isLandscape: isLandscape,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AnalyticsPage(),
                          ),
                        );
                      },
                    ),
                    Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ],

                  // Change Credentials - Only for ADMIN
                  if (_isClientLogin) ...[
                    _buildSettingsItem(
                      icon: Icons.vpn_key_outlined,
                      title: 'Change Username & Password',
                      subtitle: 'Update your credentials ',
                      hasTrailingArrow: true,
                      iconColor: const Color(
                        0xFF4285F4,
                      ), // Blue to match app theme
                      isLandscape: isLandscape,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ChangeCredentialsPage(),
                          ),
                        );
                      },
                    ),
                    Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ],

                  // Backup Data to Cloud - Only for ADMIN
                  if (_isClientLogin) ...[
                    _buildSettingsItem(
                      icon: Icons.cloud_upload_outlined,
                      title: 'Backup Data to Cloud',
                      subtitle: 'Secure your data in Firebase',
                      hasTrailingArrow: true,
                      isLandscape: isLandscape,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const BackupDataPage(),
                          ),
                        );
                      },
                    ),
                    Divider(height: 1, thickness: 1, color: Colors.grey[200]),
                  ],

                  // Submit Feedback - Available for BOTH Admin and Employee
                  _buildSettingsItem(
                    icon: Icons.rate_review_outlined,
                    title: 'Submit Feedback',
                    subtitle: 'Share your thoughts with us',
                    hasTrailingArrow: true,
                    isLandscape: isLandscape,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SubmitFeedbackPage(),
                        ),
                      );
                    },
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),

                  // Logout - Available for BOTH Admin and Employee
                  _buildSettingsItem(
                    icon: Icons.logout,
                    title: 'Logout',
                    subtitle: 'Secure your account remotely',
                    iconColor: Colors.red[700],
                    isLandscape: isLandscape,
                    onTap: () => _showLogoutDialog(context),
                  ),
                  Divider(height: 1, thickness: 1, color: Colors.grey[200]),

                  // Version Information
                  SizedBox(height: isLandscape ? 28 : 32),
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4285F4).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.info_outline,
                            size: isLandscape ? 28 : 32,
                            color: const Color(0xFF4285F4),
                          ),
                        ),
                        SizedBox(height: isLandscape ? 10 : 12),
                        Text(
                          'Ledger App',
                          style: TextStyle(
                            fontSize: isLandscape ? 15 : 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Version 2.1.0',
                          style: TextStyle(
                            fontSize: isLandscape ? 13 : 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Build 2025.02',
                          style: TextStyle(
                            fontSize: isLandscape ? 11 : 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isLandscape ? 28 : 32),
                ],
              ),
        bottomNavigationBar: const AppBottomBar(currentIndex: 2),
      ),
    );
  }
}

/// Extension to wrap widget in GestureDetector
extension GestureDetectorExtension on Widget {
  Widget wrapInGestureDetector({required VoidCallback onTap}) {
    return GestureDetector(onTap: onTap, child: this);
  }
}
