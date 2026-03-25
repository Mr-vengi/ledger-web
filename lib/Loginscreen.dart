import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'ledgerlist.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  bool _showClientPasswordLogin = false;
  bool _showClientOTPLogin = false;
  bool _obscurePassword = true;
  String? _selectedShopId;

  // OTP Login State
  String? _verificationId;
  bool _otpSent = false;
  int? _resendToken;
  String _phoneNumber = '';

  late TextEditingController _employeeNameController;
  late TextEditingController _employeePasswordController;
  late TextEditingController _clientUsernameController;
  late TextEditingController _clientPasswordController;
  late TextEditingController _phoneNumberController;
  late TextEditingController _otpController;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _employeeNameController = TextEditingController();
    _employeePasswordController = TextEditingController();
    _clientUsernameController = TextEditingController();
    _clientPasswordController = TextEditingController();
    _phoneNumberController = TextEditingController();
    _otpController = TextEditingController();
    _checkLoginStatus();
    _setupAnimations();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _employeeNameController.dispose();
    _employeePasswordController.dispose();
    _clientUsernameController.dispose();
    _clientPasswordController.dispose();
    _phoneNumberController.dispose();
    _otpController.dispose();
    super.dispose();
  }

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

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    if (isLoggedIn) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LedgerListScreen()),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getAllShops() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('shop_list')
          .get();

      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            if (data['status'] != 'active') {
              return null;
            }

            return {
              'shopId': doc.id,
              'shopName': data['shopName'] ?? 'Unknown Shop',
              'location': data['location'] ?? '',
              'phone': data['phone'] ?? '',
              'username': data['username'] ?? '',
              'collectionName': data['collectionName'] ?? '',
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      debugPrint('Error fetching shops: $e');
      return [];
    }
  }

  Future<bool> _verifyEmployeeCredentialsForShop(
    String collectionName,
    String username,
    String password,
  ) async {
    try {
      debugPrint('🔍 Verifying credentials for collection: $collectionName');
      debugPrint('🔍 Username: $username');

      final credentialsSnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc('Credentials')
          .get();

      if (!credentialsSnapshot.exists) {
        debugPrint('❌ Credentials document does not exist');
        return false;
      }

      final data = credentialsSnapshot.data() as Map<String, dynamic>;
      final storedUsername = data['username']?.toString() ?? '';
      final storedHashedPassword = data['password']?.toString() ?? '';

      debugPrint('🔍 Stored username: $storedUsername');
      debugPrint('🔍 Stored hashed password: $storedHashedPassword');

      final hashedInputPassword = _hashPassword(password);
      debugPrint('🔍 Input hashed password: $hashedInputPassword');

      final usernameMatch =
          storedUsername.toLowerCase() == username.toLowerCase();
      final passwordMatch = storedHashedPassword == hashedInputPassword;

      debugPrint('🔍 Username match: $usernameMatch');
      debugPrint('🔍 Password match: $passwordMatch');

      return usernameMatch && passwordMatch;
    } catch (e) {
      debugPrint('❌ Error verifying employee credentials: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> _getEmployeeDetailsForShop(
    String collectionName,
    String shopId,
    String shopName,
  ) async {
    try {
      final credentialsSnapshot = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc('Credentials')
          .get();

      if (!credentialsSnapshot.exists) {
        return null;
      }

      final employeeData = credentialsSnapshot.data() as Map<String, dynamic>;

      employeeData['shopId'] = shopId;
      employeeData['shopName'] = shopName;
      employeeData['collectionName'] = collectionName;

      return employeeData;
    } catch (e) {
      debugPrint('Error fetching employee details: $e');
      return null;
    }
  }

  Future<bool> _verifyClientCredentials(
    String username,
    String password,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('adminlogin')
          .where('username', isEqualTo: username)
          .where('password', isEqualTo: password)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error verifying client credentials: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> _getClientDetails(String username) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('adminlogin')
          .where('username', isEqualTo: username)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first.data();
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching client details: $e');
      return null;
    }
  }

  /// Verify if phone number exists in adminlogin collection
  Future<Map<String, dynamic>?> _verifyPhoneNumberInAdminLogin(
      String phoneNumber) async {
    try {
      // Normalize phone number (remove +, spaces, etc.)
      String normalizedPhone = phoneNumber.replaceAll(RegExp(r'[+\s-]'), '');
      
      // Remove leading + if present
      if (normalizedPhone.startsWith('+')) {
        normalizedPhone = normalizedPhone.substring(1);
      }
      
      debugPrint('🔍 Searching for phone number: $normalizedPhone');
      
      // Get all adminlogin documents (since we can't query by phoneNumber if field doesn't exist)
      final snapshot = await FirebaseFirestore.instance
          .collection('adminlogin')
          .get();

      debugPrint('📋 Found ${snapshot.docs.length} adminlogin document(s)');

      // Check each document for phone number match
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final docPhone = data['phoneNumber']?.toString() ?? '';
        final docUsername = data['username']?.toString() ?? '';
        
        debugPrint('📄 Checking document: username=$docUsername, phoneNumber=$docPhone');
        
        if (docPhone.isEmpty) {
          debugPrint('⚠️ Document has no phoneNumber field');
          continue;
        }
        
        // Normalize document phone number
        String normalizedDocPhone = docPhone.replaceAll(RegExp(r'[+\s-]'), '');
        if (normalizedDocPhone.startsWith('+')) {
          normalizedDocPhone = normalizedDocPhone.substring(1);
        }
        
        debugPrint('🔍 Comparing: input=$normalizedPhone vs stored=$normalizedDocPhone');
        
        // Try exact match
        if (normalizedDocPhone == normalizedPhone) {
          debugPrint('✅ Exact match found!');
          return data;
        }
        
        // Try with country code variations (for Indian numbers)
        if (normalizedPhone.length == 10 && normalizedDocPhone == '91$normalizedPhone') {
          debugPrint('✅ Match found with country code!');
          return data;
        }
        if (normalizedDocPhone.length == 10 && normalizedPhone == '91$normalizedDocPhone') {
          debugPrint('✅ Match found (input had country code)!');
          return data;
        }
        
        // Try last 10 digits match (in case of different formats)
        if (normalizedPhone.length >= 10 && normalizedDocPhone.length >= 10) {
          final last10Input = normalizedPhone.substring(normalizedPhone.length - 10);
          final last10Doc = normalizedDocPhone.substring(normalizedDocPhone.length - 10);
          if (last10Input == last10Doc) {
            debugPrint('✅ Match found (last 10 digits)!');
            return data;
          }
        }
      }
      
      debugPrint('❌ No matching phone number found');
      return null;
    } catch (e) {
      debugPrint('❌ Error verifying phone number: $e');
      return null;
    }
  }

  /// Send OTP to phone number
  Future<void> _sendOTP(String phoneNumber) async {
    try {
      setState(() => _isLoading = true);

      // Verify phone number exists in adminlogin
      final adminData = await _verifyPhoneNumberInAdminLogin(phoneNumber);
      if (adminData == null) {
        _showErrorSnackBar(
          'Phone number not registered.\n\n'
          'Please add "phoneNumber" field to adminlogin collection in Firebase.\n'
          'Or use Username & Password login instead.',
        );
        setState(() => _isLoading = false);
        return;
      }

      // Format phone number with country code if needed
      String formattedPhone = phoneNumber.trim();
      if (!formattedPhone.startsWith('+')) {
        if (formattedPhone.startsWith('91')) {
          formattedPhone = '+$formattedPhone';
        } else if (formattedPhone.length == 10) {
          formattedPhone = '+91$formattedPhone';
        } else {
          formattedPhone = '+$formattedPhone';
        }
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-verification completed
          try {
            await _signInWithCredential(credential);
          } catch (e) {
            debugPrint('Error in verificationCompleted: $e');
            if (mounted) {
              setState(() => _isLoading = false);
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('Verification failed: ${e.message}');
          if (mounted) {
            _showErrorSnackBar('Failed to send OTP: ${e.message}');
            setState(() => _isLoading = false);
          }
        },
        codeSent: (String verificationId, int? resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verificationId;
              _resendToken = resendToken;
              _otpSent = true;
              _phoneNumber = formattedPhone;
              _isLoading = false;
            });
            _showSuccessSnackBar('OTP sent to $formattedPhone');
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      debugPrint('Error sending OTP: $e');
      _showErrorSnackBar('Error sending OTP: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Verify OTP and sign in
  Future<void> _verifyOTP(String otp) async {
    if (_verificationId == null) {
      _showErrorSnackBar('Please send OTP first');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otp,
      );

      await _signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      debugPrint('OTP verification failed: ${e.message}');
      _showErrorSnackBar('Invalid OTP. Please try again.');
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error verifying OTP: $e');
      _showErrorSnackBar('Error verifying OTP: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Sign in with phone credential and complete login
  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      
      // Get admin details from Firestore using phone number
      final adminData = await _verifyPhoneNumberInAdminLogin(_phoneNumber);
      
      if (adminData == null) {
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          _showErrorSnackBar('Admin account not found');
          setState(() => _isLoading = false);
        }
        return;
      }

      final username = adminData['username'] ?? 'Admin';
      final clientId = adminData['id'] ?? userCredential.user?.uid ?? '';

      await Future.delayed(const Duration(milliseconds: 500));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('loginType', 'client');
      await prefs.setString('userName', username);
      await prefs.setString('clientId', clientId);

      if (mounted) {
        _showSuccessSnackBar('Welcome, $username!');

        try {
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
        } catch (navError) {
          debugPrint('Navigation error: $navError');
          // If navigation fails, reset loading state
          if (mounted) {
            setState(() => _isLoading = false);
          }
        }
      } else {
        // If widget is not mounted, reset loading state
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error signing in: $e');
      if (mounted) {
        _showErrorSnackBar('Error signing in: $e');
        setState(() => _isLoading = false);
      }
    }
  }

  /// Resend OTP
  Future<void> _resendOTP() async {
    if (_phoneNumber.isEmpty) {
      _showErrorSnackBar('Please enter phone number first');
      return;
    }
    await _sendOTP(_phoneNumber);
  }

  Future<void> _loginAsClient() async {
    final username = _clientUsernameController.text.trim();
    final password = _clientPasswordController.text.trim();

    if (username.isEmpty) {
      _showErrorSnackBar('Please enter your username');
      return;
    }

    if (password.isEmpty) {
      _showErrorSnackBar('Please enter your password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Verify credentials from Firestore
      final credentialsValid = await _verifyClientCredentials(
        username,
        password,
      );

      if (!credentialsValid) {
        _showErrorSnackBar('Invalid username or password');
        setState(() => _isLoading = false);
        return;
      }

      final clientDetails = await _getClientDetails(username);
      
      // Get email from adminlogin for Firebase Auth
      final email = clientDetails?['email'] as String?;
      
      // Sign in to Firebase Auth if email exists
      if (email != null && email.isNotEmpty) {
        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          debugPrint('✅ Signed in to Firebase Auth as client');
        } catch (authError) {
          debugPrint('⚠️ Could not sign in to Firebase Auth: $authError');
          // Continue anyway - Firestore credentials are valid
        }
      } else {
        // Create email if it doesn't exist (for backward compatibility)
        final adminDoc = await FirebaseFirestore.instance
            .collection('adminlogin')
            .where('username', isEqualTo: username)
            .limit(1)
            .get();
        
        if (adminDoc.docs.isNotEmpty) {
          final emailToCreate = '$username@admin.ledger.local';
          try {
            // Try to create Firebase Auth user
            final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
              email: emailToCreate,
              password: password,
            );
            debugPrint('✅ Created Firebase Auth user for client');
            
            // Update Firestore with email
            await adminDoc.docs.first.reference.update({
              'email': emailToCreate,
              'authUid': userCredential.user?.uid,
            });
          } catch (e) {
            // User might already exist, try to sign in
            try {
              await FirebaseAuth.instance.signInWithEmailAndPassword(
                email: emailToCreate,
                password: password,
              );
              debugPrint('✅ Signed in to existing Firebase Auth user');
            } catch (signInError) {
              debugPrint('⚠️ Could not sign in to Firebase Auth: $signInError');
            }
          }
        }
      }

      await Future.delayed(const Duration(milliseconds: 500));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('loginType', 'client');
      await prefs.setString('userName', clientDetails?['username'] ?? username);
      await prefs.setString('clientId', clientDetails?['id'] ?? username);

      if (mounted) {
        _showSuccessSnackBar('Welcome, $username!');

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
    } catch (e) {
      debugPrint('Error: $e');
      _showErrorSnackBar('Error: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loginAsEmployee() async {
    final employeeUsername = _employeeNameController.text.trim();
    final employeePassword = _employeePasswordController.text.trim();

    if (_selectedShopId == null || _selectedShopId!.isEmpty) {
      _showErrorSnackBar('Please select a shop');
      return;
    }

    if (employeeUsername.isEmpty) {
      _showErrorSnackBar('Please enter your username');
      return;
    }

    if (employeePassword.isEmpty) {
      _showErrorSnackBar('Please enter your password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      debugPrint('🔍 Looking up shop with ID: $_selectedShopId');

      final shopDoc = await FirebaseFirestore.instance
          .collection('shop_list')
          .doc(_selectedShopId!)
          .get();

      if (!shopDoc.exists) {
        _showErrorSnackBar('Shop not found');
        setState(() => _isLoading = false);
        return;
      }

      final shopData = shopDoc.data() as Map<String, dynamic>;
      final collectionName = shopData['collectionName'] as String;
      final shopName = shopData['shopName'] as String;

      debugPrint('🔍 Shop collection: $collectionName');
      debugPrint('🔍 Shop name: $shopName');

      final credentialsValid = await _verifyEmployeeCredentialsForShop(
        collectionName,
        employeeUsername,
        employeePassword,
      );

      if (!credentialsValid) {
        _showErrorSnackBar('Invalid username or password for this shop');
        setState(() => _isLoading = false);
        return;
      }

      // Verify device IMEI
      final imeiValid = await _verifyDeviceImei(collectionName);
      if (!imeiValid) {
        _showErrorSnackBar(
          'This device is not eligible.\n\n'
          'Access denied: This device is not authorized. Please contact admin.',
        );
        setState(() => _isLoading = false);
        return;
      }

      final employeeDetails = await _getEmployeeDetailsForShop(
        collectionName,
        _selectedShopId!,
        shopName,
      );

      await Future.delayed(const Duration(milliseconds: 500));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('loginType', 'employee');
      await prefs.setString(
        'userName',
        employeeDetails?['username'] ?? employeeUsername,
      );
      await prefs.setString('shopCollection', collectionName);
      await prefs.setString('shopName', shopName);

      if (mounted) {
        _showSuccessSnackBar('Welcome, ${employeeDetails?['username']}!');

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
    } catch (e) {
      debugPrint('❌ Login error: $e');
      _showErrorSnackBar('Login failed: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
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
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
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
          backgroundColor: const Color(0xFF4285F4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
          bottom: true,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: size.height - 
                    MediaQuery.of(context).padding.top - 
                    MediaQuery.of(context).padding.bottom,
              ),
              child: IntrinsicHeight(
                child: Column(
                  children: [
                    Expanded(
                      flex: 2,
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
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
                                Icons.receipt_long,
                                size: 45,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Ledger App',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Smart Business Management',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white.withOpacity(0.85),
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
                            padding: EdgeInsets.only(
                              left: 24,
                              right: 24,
                              top: 32,
                              bottom: 32 + MediaQuery.of(context).padding.bottom,
                            ),
                            child: _showClientPasswordLogin
                                ? _buildClientPasswordLoginView()
                                : _showClientOTPLogin
                                    ? _buildClientOTPLoginView()
                                : _buildMainLoginView(),
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
    );
  }

  Widget _buildMainLoginView() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Welcome Back',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose your login type to continue',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[600],
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 32),
          _buildMainButton(
            title: 'Admin Login',
            subtitle: 'OTP or Username & password login',
            icon: Icons.business_center_outlined,
            isLoading: _isLoading,
            onPressed: _isLoading
                ? null
                : () {
                    setState(() {
                      _showClientOTPLogin = true;
                      _otpSent = false;
                      _phoneNumberController.clear();
                      _otpController.clear();
                    });
                  },
          ),
          const SizedBox(height: 16),
          _buildMainButton(
            title: 'Employee Login',
            subtitle: 'Team member access',
            icon: Icons.person_outline,
            isLoading: _isLoading,
            onPressed: _isLoading ? null : () => _showEmployeeLoginSheet(),
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Secure and fast login',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientOTPLoginView() {
    // Safeguard: If OTP was sent but loading is still true, reset it
    if (_otpSent && _isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      });
    }
    
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _showClientOTPLogin = false;
                _otpSent = false;
                _phoneNumberController.clear();
                _otpController.clear();
                _verificationId = null;
                _isLoading = false; // Reset loading when going back
              });
            },
            child: Row(
              children: [
                Icon(Icons.arrow_back_ios, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Admin Login',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _otpSent
                ? 'Enter the OTP sent to your phone'
                : 'Enter your phone number to receive OTP',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 32),
          if (!_otpSent) ...[
            const Text(
              'Phone Number',
              style: TextStyle(
                fontSize: 15,
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
                border: Border.all(color: Colors.grey[300]!, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _phoneNumberController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: 'Enter your phone number',
                  prefixIcon: const Icon(
                    Icons.phone_outlined,
                    color: Color(0xFF4285F4),
                    size: 24,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
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
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        final phone = _phoneNumberController.text.trim();
                        if (phone.isEmpty) {
                          _showErrorSnackBar('Please enter your phone number');
                          return;
                        }
                        _sendOTP(phone);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  elevation: 4,
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
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Send OTP',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _showClientOTPLogin = false;
                    _showClientPasswordLogin = true;
                  });
                },
                child: Text(
                  'Use Username & Password instead',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ] else ...[
            const Text(
              'OTP Code',
              style: TextStyle(
                fontSize: 15,
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
                border: Border.all(color: Colors.grey[300]!, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  hintText: 'Enter 6-digit OTP',
                  prefixIcon: const Icon(
                    Icons.lock_outlined,
                    color: Color(0xFF4285F4),
                    size: 24,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  hintStyle: TextStyle(
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w400,
                  ),
                  counterText: '',
                ),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  letterSpacing: 4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        final otp = _otpController.text.trim();
                        if (otp.length != 6) {
                          _showErrorSnackBar('Please enter 6-digit OTP');
                          return;
                        }
                        _verifyOTP(otp);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  elevation: 4,
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
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Verify OTP',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : _resendOTP,
                  child: Text(
                    'Resend OTP',
                    style: TextStyle(
                      fontSize: 14,
                      color: const Color(0xFF4285F4),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  ' | ',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _otpSent = false;
                      _otpController.clear();
                    });
                  },
                  child: Text(
                    'Change Number',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _showClientOTPLogin = false;
                    _showClientPasswordLogin = true;
                    _otpSent = false;
                    _phoneNumberController.clear();
                    _otpController.clear();
                  });
                },
                child: Text(
                  'Use Username & Password instead',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildClientPasswordLoginView() {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _showClientPasswordLogin = false;
                _clientUsernameController.clear();
                _clientPasswordController.clear();
              });
            },
            child: Row(
              children: [
                Icon(Icons.arrow_back_ios, size: 18, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Text(
                  'Back',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Admin Login',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your credentials to access your account',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Username',
            style: TextStyle(
              fontSize: 15,
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
              border: Border.all(color: Colors.grey[300]!, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _clientUsernameController,
              decoration: InputDecoration(
                hintText: 'Enter your username',
                prefixIcon: const Icon(
                  Icons.account_circle_outlined,
                  color: Color(0xFF4285F4),
                  size: 24,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
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
          const SizedBox(height: 20),
          const Text(
            'Password',
            style: TextStyle(
              fontSize: 15,
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
              border: Border.all(color: Colors.grey[300]!, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _clientPasswordController,
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
                    setState(() => _obscurePassword = !_obscurePassword);
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
                contentPadding: const EdgeInsets.symmetric(
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
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _loginAsClient,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
                elevation: 4,
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
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () {
                setState(() {
                  _showClientPasswordLogin = false;
                  _showClientOTPLogin = true;
                  _otpSent = false;
                  _phoneNumberController.clear();
                  _otpController.clear();
                });
              },
              child: Text(
                'Use OTP Login instead',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                      ),
                    ),
            ),
          ),
          // Add extra bottom padding to ensure button is fully visible
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  void _showEmployeeLoginSheet() {
    _selectedShopId = null;
    _employeeNameController.clear();
    _employeePasswordController.clear();
    bool obscureEmployeePassword = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _getAllShops(),
            builder: (context, snapshot) {
              final shops = snapshot.data ?? [];
              final isLoading =
                  snapshot.connectionState == ConnectionState.waiting;

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 
                      MediaQuery.of(context).padding.bottom + 24,
                  left: 24,
                  right: 24,
                  top: 24,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Employee Portal',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign in to access your shop',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Shop Selection
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
                      isLoading
                          ? Container(
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(14),
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
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Color(0xFF4285F4),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _selectedShopId != null
                                      ? const Color(0xFF4285F4)
                                      : Colors.grey[300]!,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: DropdownButton<String>(
                                value: _selectedShopId,
                                isExpanded: true,
                                underline: const SizedBox(),
                                icon: Padding(
                                  padding: const EdgeInsets.only(right: 12),
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
                                items: shops.map<DropdownMenuItem<String>>((
                                  shop,
                                ) {
                                  return DropdownMenuItem<String>(
                                    value: shop['shopId'] as String,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.store_mall_directory,
                                            color: const Color(0xFF4285F4),
                                            size: 22,
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Text(
                                              shop['shopName'] as String,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setModalState(() {
                                    _selectedShopId = value;
                                  });
                                },
                              ),
                            ),
                      const SizedBox(height: 24),
                      // Username Field
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
                          controller: _employeeNameController,
                          enabled: _selectedShopId != null,
                          decoration: InputDecoration(
                            hintText: 'Enter your username',
                            prefixIcon: const Icon(
                              Icons.account_circle_outlined,
                              color: Color(0xFF4285F4),
                              size: 24,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
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
                      const SizedBox(height: 20),
                      // Password Field
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
                          controller: _employeePasswordController,
                          enabled: _selectedShopId != null,
                          obscureText: obscureEmployeePassword,
                          decoration: InputDecoration(
                            hintText: 'Enter your password',
                            prefixIcon: const Icon(
                              Icons.lock_outlined,
                              color: Color(0xFF4285F4),
                              size: 24,
                            ),
                            suffixIcon: GestureDetector(
                              onTap: () {
                                setModalState(
                                  () => obscureEmployeePassword =
                                      !obscureEmployeePassword,
                                );
                              },
                              child: Icon(
                                obscureEmployeePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: Colors.grey[600],
                                size: 22,
                              ),
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
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
                      const SizedBox(height: 32),
                      // Login Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: (_selectedShopId == null || _isLoading)
                              ? null
                              : _loginAsEmployee,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4285F4),
                            disabledBackgroundColor: Colors.grey[400],
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Sign In',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMainButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isLoading,
    required VoidCallback? onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF4285F4), Color(0xFF2E5BF8)],
                  ),
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF4285F4),
                    ),
                  ),
                )
              else
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey[400],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
