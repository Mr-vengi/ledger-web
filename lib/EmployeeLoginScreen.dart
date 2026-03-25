import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'ledgerlist.dart';

class EmployeeLoginScreen extends StatefulWidget {
  const EmployeeLoginScreen({super.key});

  @override
  State<EmployeeLoginScreen> createState() => _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends State<EmployeeLoginScreen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _isShopsLoading = true;
  bool _obscurePassword = true;
  List<Map<String, dynamic>> _shops = [];
  String? _selectedShopCollection;
  String? _selectedShopName;

  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _setupAnimations();
    _fetchShops();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeController.forward();
    _slideController.forward();
  }

  /// Hash password using SHA256
  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  /// Get device IMEI/ID
  Future<String?> _getDeviceImei() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        // Use Android ID as device identifier
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        // Use Identifier for Vendor as device identifier
        return iosInfo.identifierForVendor;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting device IMEI: $e');
      return null;
    }
  }

  /// Get comprehensive device information
  Future<Map<String, dynamic>?> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String? deviceId;
      String deviceModel = 'Unknown';
      String deviceBrand = 'Unknown';
      String deviceName = 'Unknown';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
        deviceModel = androidInfo.model;
        deviceBrand = androidInfo.brand;
        deviceName = '${androidInfo.brand} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor;
        deviceModel = iosInfo.model;
        deviceName = iosInfo.name;
        deviceBrand = 'Apple';
      }

      if (deviceId == null || deviceId.isEmpty) {
        return null;
      }

      return {
        'deviceId': deviceId,
        'deviceModel': deviceModel,
        'deviceBrand': deviceBrand,
        'deviceName': deviceName,
        'platform': Platform.isAndroid ? 'Android' : 'iOS',
      };
    } catch (e) {
      debugPrint('Error getting device info: $e');
      return null;
    }
  }

  /// Track device history when employee logs in
  Future<void> _trackDeviceHistory(String collectionName) async {
    try {
      final deviceInfo = await _getDeviceInfo();
      if (deviceInfo == null) return;

      final deviceId = deviceInfo['deviceId'] as String;
      final loginTimestamp = FieldValue.serverTimestamp();

      // Get current device history
      final credDoc = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc('Credentials')
          .get();

      if (!credDoc.exists) return;

      final credData = credDoc.data() ?? {};
      final deviceHistory = credData['deviceHistory'] as List<dynamic>? ?? [];

      // Check if device already exists in history
      final deviceIndex = deviceHistory.indexWhere(
        (d) => (d as Map<String, dynamic>)['deviceId'] == deviceId,
      );

      if (deviceIndex >= 0) {
        // Update existing device
        final existingDevice = deviceHistory[deviceIndex] as Map<String, dynamic>;
        final loginHistory = existingDevice['loginHistory'] as List<dynamic>? ?? [];
        
        // Add new login to history
        loginHistory.add(loginTimestamp);

        deviceHistory[deviceIndex] = {
          ...existingDevice,
          'lastLoginAt': loginTimestamp,
          'loginHistory': loginHistory,
        };
      } else {
        // Add new device
        deviceHistory.add({
          ...deviceInfo,
          'firstLoginAt': loginTimestamp,
          'lastLoginAt': loginTimestamp,
          'loginHistory': [loginTimestamp],
        });
      }

      // Update Firestore
      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc('Credentials')
          .update({
            'deviceHistory': deviceHistory,
          });

      debugPrint('✅ Device history tracked');
    } catch (e) {
      debugPrint('Error tracking device history: $e');
      // Don't block login if history tracking fails
    }
  }

  /// Verify device IMEI matches stored IMEI
  Future<bool> _verifyDeviceImei(String collectionName) async {
    try {
      // Get stored IMEI from Firestore
      final credDoc = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc('Credentials')
          .get();

      if (!credDoc.exists) {
        debugPrint('Credentials document not found for IMEI check');
        return false;
      }

      final credData = credDoc.data() ?? {};
      final storedImei = credData['deviceImei'] as String?;

      // If no IMEI is stored, allow login (backward compatibility)
      if (storedImei == null || storedImei.isEmpty) {
        debugPrint('⚠️ No IMEI stored, allowing login (backward compatibility)');
        return true;
      }

      // Get current device IMEI
      final currentImei = await _getDeviceImei();

      if (currentImei == null || currentImei.isEmpty) {
        debugPrint('⚠️ Could not get device IMEI');
        return false;
      }

      // Compare IMEIs
      final isMatch = storedImei.trim() == currentImei.trim();
      debugPrint('IMEI Check - Stored: $storedImei, Current: $currentImei, Match: $isMatch');
      
      return isMatch;
    } catch (e) {
      debugPrint('Error verifying device IMEI: $e');
      return false;
    }
  }

  /// Fetch all shops from shop_list collection
  Future<void> _fetchShops() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('shop_list')
          .get();

      List<Map<String, dynamic>> shopsList = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        shopsList.add({
          'collectionName': data['collectionName'] ?? '',
          'shopName': data['shopName'] ?? 'Unknown Shop',
        });
      }

      setState(() {
        _shops = shopsList;
        _isShopsLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching shops: $e');
      setState(() => _isShopsLoading = false);
      if (mounted) {
        _showSnackBar('Error loading shops', isError: true);
      }
    }
  }

  /// Verify employee credentials from selected shop collection
  Future<bool> _verifyEmployeeCredentials(
    String collectionName,
    String username,
    String password,
  ) async {
    try {
      // Get Credentials document from shop collection
      final credDoc = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc('Credentials')
          .get();

      if (!credDoc.exists) {
        debugPrint('Credentials document not found');
        return false;
      }

      final credData = credDoc.data() ?? {};
      final storedUsername = credData['username'] ?? '';
      final storedPasswordHash = credData['password'] ?? '';

      // Verify username and password
      final passwordHash = _hashPassword(password);

      return storedUsername == username && storedPasswordHash == passwordHash;
    } catch (e) {
      debugPrint('Error verifying credentials: $e');
      return false;
    }
  }

  /// Login as Employee
  Future<void> _loginAsEmployee() async {
    // Validation
    if (_selectedShopCollection == null) {
      _showSnackBar('Please select a shop', isError: true);
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty) {
      _showSnackBar('Please enter username', isError: true);
      return;
    }

    if (password.isEmpty) {
      _showSnackBar('Please enter password', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Verify credentials from Firestore
      final isValid = await _verifyEmployeeCredentials(
        _selectedShopCollection!,
        username,
        password,
      );

      if (!isValid) {
        if (mounted) {
          _showSnackBar('Invalid username or password', isError: true);
        }
        setState(() => _isLoading = false);
        return;
      }

      // Verify device IMEI
      final imeiValid = await _verifyDeviceImei(_selectedShopCollection!);
      if (!imeiValid) {
        if (mounted) {
          _showSnackBar(
            'Access denied: This device is not authorized. Please contact admin.',
            isError: true,
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // Track device history (non-blocking)
      _trackDeviceHistory(_selectedShopCollection!);

      // Get employee email from Firestore for Firebase Auth
      final credDoc = await FirebaseFirestore.instance
          .collection(_selectedShopCollection!)
          .doc('Credentials')
          .get();

      final credData = credDoc.data() ?? {};
      final email = credData['email'] as String?;

      // Sign in to Firebase Auth if email exists
      if (email != null && email.isNotEmpty) {
        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          debugPrint('✅ Signed in to Firebase Auth as employee');
        } catch (authError) {
          debugPrint('⚠️ Could not sign in to Firebase Auth: $authError');
          // Continue anyway - Firestore credentials are valid
        }
      }

      // Save login info to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('loginType', 'employee');
      await prefs.setString('userName', username);
      await prefs.setString('shopName', _selectedShopName ?? '');
      await prefs.setString('shopCollection', _selectedShopCollection ?? '');

      if (mounted) {
        _showSnackBar('Welcome, $username!');

        // Navigate to Ledger List
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const LedgerListScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Login error: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      if (mounted) {
        _showSnackBar('Error: $e', isError: true);
        setState(() => _isLoading = false);
      }
    }
  }

  /// Show snackbar
  void _showSnackBar(String message, {bool isError = false}) {
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4285F4), Color(0xFF2E5BF8)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: SizedBox(
              height: size.height - MediaQuery.of(context).padding.top,
              child: Column(
                children: [
                  // Top Section with Logo
                  Expanded(
                    flex: 2,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Back Button
                          Align(
                            alignment: Alignment.topLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16, top: 8),
                              child: GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.arrow_back_ios,
                                      size: 18,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Back',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Logo with improved design
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.15),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.4),
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.person_outline,
                              size: 45,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'Employee Portal',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sign in to access your shop',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                  // Bottom Section with Login Form
                  Expanded(
                    flex: 3,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Container(
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(32),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 32,
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Shop Selection with improved design
                                const Text(
                                  'Select Your Shop',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1F2937),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _isShopsLoading
                                    ? Container(
                                        height: 56,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[100],
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color: Colors.grey[300]!,
                                            width: 1.5,
                                          ),
                                        ),
                                        child: const Center(
                                          child: SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Color(0xFF4285F4),
                                                  ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color: _selectedShopCollection !=
                                                    null
                                                ? const Color(0xFF4285F4)
                                                : Colors.grey[300]!,
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.05),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: DropdownButton<String>(
                                          value: _selectedShopCollection,
                                          isExpanded: true,
                                          underline: const SizedBox(),
                                          icon: Padding(
                                            padding: const EdgeInsets.only(
                                                right: 12),
                                            child: Icon(
                                              Icons.keyboard_arrow_down,
                                              color: Colors.grey[600],
                                              size: 24,
                                            ),
                                          ),
                                          hint: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 16,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  Icons.store_mall_directory,
                                                  color: Colors.grey[500],
                                                  size: 22,
                                                ),
                                                const SizedBox(width: 14),
                                                Text(
                                                  'Choose your shop',
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    color: Colors.grey[500],
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          items: _shops.map((shop) {
                                            return DropdownMenuItem<String>(
                                              value: shop['collectionName'],
                                              onTap: () {
                                                setState(() {
                                                  _selectedShopName =
                                                      shop['shopName'];
                                                });
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                  horizontal: 16,
                                                  vertical: 14,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .store_mall_directory,
                                                      color: const Color(
                                                          0xFF4285F4),
                                                      size: 22,
                                                    ),
                                                    const SizedBox(width: 14),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            shop['shopName'],
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 15,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color:
                                                                  Colors.black87,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (value) {
                                            setState(
                                              () =>
                                                  _selectedShopCollection =
                                                      value,
                                            );
                                          },
                                        ),
                                      ),
                                const SizedBox(height: 28),

                                // Username Field with improved design
                                const Text(
                                  'Username',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1F2937),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: _usernameController,
                                    decoration: InputDecoration(
                                      hintText: 'Enter your username',
                                      prefixIcon: const Icon(
                                        Icons.account_circle_outlined,
                                        color: Color(0xFF4285F4),
                                        size: 24,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                      hintStyle: TextStyle(
                                        color: Colors.grey[500],
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Password Field with improved design
                                const Text(
                                  'Password',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1F2937),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: TextField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    decoration: InputDecoration(
                                      hintText: 'Enter your password',
                                      prefixIcon: const Icon(
                                        Icons.lock_outlined,
                                        color: Color(0xFF4285F4),
                                        size: 24,
                                      ),
                                      suffixIcon: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                        child: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: Colors.grey[600],
                                          size: 22,
                                        ),
                                      ),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                      hintStyle: TextStyle(
                                        color: Colors.grey[500],
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 36),

                                // Login Button with improved design
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: _isLoading
                                        ? null
                                        : _loginAsEmployee,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF4285F4),
                                      foregroundColor: Colors.white,
                                      elevation: _isLoading ? 2 : 4,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      disabledBackgroundColor: Colors.grey[400],
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          )
                                        : const Text(
                                            'Sign In',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}