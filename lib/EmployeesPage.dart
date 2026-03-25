import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shimmer/shimmer.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:convert';
import 'dart:io';

class ShopsPage extends StatefulWidget {
  const ShopsPage({super.key});

  @override
  State<ShopsPage> createState() => _ShopsPageState();
}

class _ShopsPageState extends State<ShopsPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _shops = [];

  @override
  void initState() {
    super.initState();
    _fetchShops();
  }

  Future<void> _fetchShops() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('shop_list')
          .get();

      List<Map<String, dynamic>> shopsList = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        shopsList.add({
          'docId': doc.id,
          'collectionName': data['collectionName'] ?? '',
          'shopName': data['shopName'] ?? 'Unknown Shop',
          'location': data['location'] ?? 'N/A',
          'phone': data['phone'] ?? 'N/A',
          'employeeUsername': data['username'] ?? 'N/A',
          'deviceImei': data['deviceImei'] ?? '',
          'createdAt': data['createdAt'],
          'status': data['status'] ?? 'active',
        });
      }

      setState(() {
        _shops = shopsList;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching shops: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteShop(
    String docId,
    String collectionName,
    String shopName,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('shop_list')
          .doc(docId)
          .delete();

      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc('Credentials')
          .delete();

      _showSnackBar('Shop deleted successfully');
      _fetchShops();
    } catch (e) {
      debugPrint('Error deleting shop: $e');
      _showSnackBar('Error deleting shop: $e', isError: true);
    }
  }

  Widget _buildShopItem(Map<String, dynamic> shop) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.store,
                    color: Color(0xFF4285F4),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop['shopName'],
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 12,
                            color: Colors.grey[500],
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              shop['location'],
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4285F4).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'User: ${shop['employeeUsername']}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF4285F4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.phone_android,
                    color: Color(0xFF4285F4),
                    size: 20,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DeviceHistoryPage(
                          shopData: shop,
                        ),
                      ),
                    );
                  },
                  tooltip: 'View Devices',
                  splashRadius: 24,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFF4285F4),
                    size: 20,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EditShopPage(
                          shopData: shop,
                          onShopUpdated: _fetchShops,
                        ),
                      ),
                    );
                  },
                  tooltip: 'Edit Shop',
                  splashRadius: 24,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[50]!,
      period: const Duration(milliseconds: 1200),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: 6,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: 120, height: 14, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(width: 180, height: 12, color: Colors.white),
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

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: const Text(
          'Shops',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 26),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      CreateShopPage(onShopCreated: _fetchShops),
                ),
              );
            },
            tooltip: 'Add Shop',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? _buildShimmerLoading()
          : _shops.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.store_mall_directory,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No shops yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first shop to get started',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : Container(
              color: Colors.white,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _shops.length,
                itemBuilder: (context, index) {
                  return _buildShopItem(_shops[index]);
                },
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// CREATE SHOP PAGE
// ─────────────────────────────────────────────────────────────────────

class CreateShopPage extends StatefulWidget {
  final VoidCallback onShopCreated;

  const CreateShopPage({super.key, required this.onShopCreated});

  @override
  State<CreateShopPage> createState() => _CreateShopPageState();
}

class _CreateShopPageState extends State<CreateShopPage> {
  final shopNameController = TextEditingController();
  final shopLocationController = TextEditingController();
  final shopPhoneController = TextEditingController();
  final empUsernameController = TextEditingController();
  final empPasswordController = TextEditingController();
  final empConfirmPasswordController = TextEditingController();
  final deviceImeiController = TextEditingController();
  bool _isLoading = false;

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  /// Get device ID from current device (for admin to copy)
  Future<String?> _getCurrentDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        final deviceId = androidInfo.id;
        debugPrint('🔍 Android Device ID retrieved: $deviceId');
        debugPrint('   Device: ${androidInfo.device}, Model: ${androidInfo.model}, Brand: ${androidInfo.brand}');
        return deviceId;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        final deviceId = iosInfo.identifierForVendor;
        debugPrint('🔍 iOS Device ID retrieved: $deviceId');
        debugPrint('   Device Name: ${iosInfo.name}, Model: ${iosInfo.model}');
        return deviceId;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      return null;
    }
  }

  Future<Map<String, String>> _getDeviceDetails() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return {
          'deviceId': androidInfo.id,
          'deviceName': androidInfo.device ?? 'Unknown',
          'model': androidInfo.model ?? 'Unknown',
          'brand': androidInfo.brand ?? 'Unknown',
          'manufacturer': androidInfo.manufacturer ?? 'Unknown',
          'platform': 'Android',
          'version': '${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})',
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return {
          'deviceId': iosInfo.identifierForVendor ?? 'Unknown',
          'deviceName': iosInfo.name ?? 'Unknown',
          'model': iosInfo.model ?? 'Unknown',
          'brand': 'Apple',
          'manufacturer': 'Apple',
          'platform': 'iOS',
          'version': '${iosInfo.systemVersion}',
        };
      }
      return {};
    } catch (e) {
      debugPrint('Error getting device details: $e');
      return {};
    }
  }

  void _showDeviceIdVerificationDialog(BuildContext context, String deviceId, Map<String, String> deviceDetails) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phone_android, color: Color(0xFF4285F4), size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Device ID Verification',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Verify this is the correct device:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                _buildDeviceInfoRow('Platform', deviceDetails['platform'] ?? 'Unknown', Icons.phone_android),
                const SizedBox(height: 8),
                _buildDeviceInfoRow('Device Name', deviceDetails['deviceName'] ?? 'Unknown', Icons.devices),
                const SizedBox(height: 8),
                _buildDeviceInfoRow('Model', deviceDetails['model'] ?? 'Unknown', Icons.phone_iphone),
                const SizedBox(height: 8),
                _buildDeviceInfoRow('Brand', deviceDetails['brand'] ?? 'Unknown', Icons.branding_watermark),
                const SizedBox(height: 8),
                _buildDeviceInfoRow('Version', deviceDetails['version'] ?? 'Unknown', Icons.info),
                const Divider(height: 24),
                const Text(
                  'Device ID:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          deviceId,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          // Copy to clipboard would require clipboard package
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Device ID is already in the text field'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'If the device details above match the device you want to authorize, click "Use This Device ID".',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                deviceImeiController.text = deviceId;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Device ID verified and added',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green[600],
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                minimumSize: const Size(0, 40),
              ),
              child: const Text(
                'Use Device ID',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeviceInfoRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$label: ',
            style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  Future<void> _createShop() async {
    final shopName = shopNameController.text.trim();
    final location = shopLocationController.text.trim();
    final phone = shopPhoneController.text.trim();
    final empUsername = empUsernameController.text.trim();
    final empPassword = empPasswordController.text.trim();
    final empConfirmPassword = empConfirmPasswordController.text.trim();
    final deviceImei = deviceImeiController.text.trim();

    if (shopName.isEmpty) {
      _showSnackBar('Please enter shop name', isError: true);
      return;
    }
    if (phone.isEmpty || phone.length != 10) {
      _showSnackBar('Please enter valid 10-digit phone', isError: true);
      return;
    }
    if (empUsername.isEmpty) {
      _showSnackBar('Please enter username', isError: true);
      return;
    }
    if (empPassword.isEmpty || empPassword.length < 6) {
      _showSnackBar('Password must be at least 6 characters', isError: true);
      return;
    }
    if (empPassword != empConfirmPassword) {
      _showSnackBar('Passwords do not match', isError: true);
      return;
    }
    if (deviceImei.isEmpty) {
      _showSnackBar('Please enter device ID', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      String collectionName = shopName.replaceAll(' ', '_').toLowerCase();

      // Create Firebase Auth user for employee
      // Use email format: username@shopname.ledger.local
      final email = '${empUsername}@${collectionName}.ledger.local';
      UserCredential? userCredential;
      
      try {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: empPassword,
        );
        debugPrint('✅ Firebase Auth user created: ${userCredential.user?.uid}');
      } catch (authError) {
        // If user already exists, try to sign in and update password
        if (authError is FirebaseAuthException && authError.code == 'email-already-in-use') {
          debugPrint('⚠️ User already exists, signing in to update...');
          try {
            await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: email,
              password: empPassword,
            );
            // User exists and password matches, continue
          } catch (e) {
            // Password might be different, create new email or handle error
            debugPrint('⚠️ Could not sign in existing user: $e');
            // Continue anyway - Firestore credentials will still work
          }
        } else {
          debugPrint('⚠️ Could not create Firebase Auth user: $authError');
          // Continue anyway - Firestore credentials will still work
        }
      }

      // Get Firebase Auth UID if available
      final authUid = userCredential?.user?.uid ?? 
                      (await FirebaseAuth.instance.currentUser)?.uid;

      await FirebaseFirestore.instance
          .collection(collectionName)
          .doc('Credentials')
          .set({
            'shopName': shopName,
            'location': location.isEmpty ? 'N/A' : location,
            'phone': phone,
            'username': empUsername,
            'password': _hashPassword(empPassword),
            'email': email, // Store email for Firebase Auth
            'authUid': authUid, // Store Firebase Auth UID
            'deviceImei': deviceImei, // Store device IMEI for device restriction
            'createdAt': Timestamp.now(),
            'status': 'active',
          });

      final shopDocRef = await FirebaseFirestore.instance.collection('shop_list').add({
        'collectionName': collectionName,
        'shopName': shopName,
        'location': location.isEmpty ? 'N/A' : location,
        'phone': phone,
        'username': empUsername,
        'email': email,
        'authUid': authUid,
        'deviceImei': deviceImei, // Store device IMEI
        'createdAt': Timestamp.now(),
        'status': 'active',
      });

      _showSnackBar('Shop "$shopName" created successfully');
      widget.onShopCreated();
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Error creating shop: $e');
      _showSnackBar('Error creating shop: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    shopNameController.dispose();
    shopLocationController.dispose();
    shopPhoneController.dispose();
    empUsernameController.dispose();
    empPasswordController.dispose();
    empConfirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: const Text('Create Shop'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF4285F4), Color(0xFF2E7FE8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.store_mall_directory,
                        color: Colors.white,
                        size: 40,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Add New Shop',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Create a new shop and set employee credentials',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                // Form
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Shop Details', Icons.store),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: shopNameController,
                        label: 'Shop Name',
                        hint: 'Enter shop name',
                        icon: Icons.store,
                        isRequired: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: shopLocationController,
                        label: 'Location',
                        hint: 'Enter location',
                        icon: Icons.location_on,
                        isRequired: false,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: shopPhoneController,
                        label: 'Phone Number',
                        hint: 'Enter 10-digit phone',
                        icon: Icons.phone,
                        isRequired: true,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                      ),

                      const SizedBox(height: 28),

                      _buildSectionHeader(
                        'Employee Credentials',
                        Icons.security,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: empUsernameController,
                        label: 'Username',
                        hint: 'Login username',
                        icon: Icons.account_circle,
                        isRequired: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: empPasswordController,
                        label: 'Password',
                        hint: 'Min 6 characters',
                        icon: Icons.lock,
                        isRequired: true,
                        obscureText: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: empConfirmPasswordController,
                        label: 'Confirm Password',
                        hint: 'Re-enter password',
                        icon: Icons.lock_outline,
                        isRequired: true,
                        obscureText: true,
                      ),

                      const SizedBox(height: 28),

                      _buildSectionHeader(
                        'Device Security',
                        Icons.phone_android,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: deviceImeiController,
                              label: 'Device ID',
                              hint: 'Enter device identifier',
                              icon: Icons.phone_android,
                              isRequired: true,
                              keyboardType: TextInputType.text,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            tooltip: 'Get Device ID from this device',
                            onPressed: () async {
                              final deviceDetails = await _getDeviceDetails();
                              final deviceId = deviceDetails['deviceId'];
                              if (deviceId != null && deviceId.isNotEmpty && mounted) {
                                _showDeviceIdVerificationDialog(context, deviceId, deviceDetails);
                              } else if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Could not get device ID'),
                                    backgroundColor: Colors.red[600],
                                  ),
                                );
                              }
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF4285F4).withOpacity(0.1),
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Employee can only login from this device. Admin can change Device ID anytime.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[900],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'How to get Device ID:\n'
                              '• Tap the QR icon to get Device ID from this device\n'
                              '• Or ask employee to login once, then check Device History page\n'
                              '• Android: Uses Android ID\n'
                              '• iOS: Uses Identifier for Vendor',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue[800],
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // <<< EXTRA SPACE SO LAST FIELD IS ALWAYS VISIBLE >>>
                      SizedBox(height: bottomInset + 80),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // FIXED BUTTON – NEVER CUT BY NAVIGATION BAR
          Positioned(
            left: 0,
            right: 0,
            bottom: 0, // <-- stays at the very bottom of the screen
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createShop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Create Shop',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
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
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4285F4), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4285F4),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isRequired = false,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        labelStyle: const TextStyle(
          color: Color(0xFF4285F4),
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey[400],
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF4285F4), size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4285F4), width: 2),
        ),
        counterText: '',
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 12,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// EDIT SHOP PAGE
// ─────────────────────────────────────────────────────────────────────

class EditShopPage extends StatefulWidget {
  final Map<String, dynamic> shopData;
  final VoidCallback onShopUpdated;

  const EditShopPage({
    super.key,
    required this.shopData,
    required this.onShopUpdated,
  });

  @override
  State<EditShopPage> createState() => _EditShopPageState();
}

class _EditShopPageState extends State<EditShopPage> {
  late TextEditingController shopNameController;
  late TextEditingController shopLocationController;
  late TextEditingController shopPhoneController;
  late TextEditingController empUsernameController;
  final empPasswordController = TextEditingController();
  final empConfirmPasswordController = TextEditingController();
  late TextEditingController deviceImeiController;
  bool _isLoading = false;

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  @override
  void initState() {
    super.initState();
    shopNameController = TextEditingController(
      text: widget.shopData['shopName'],
    );
    shopLocationController = TextEditingController(
      text: widget.shopData['location'],
    );
    shopPhoneController = TextEditingController(text: widget.shopData['phone']);
    empUsernameController = TextEditingController(
      text: widget.shopData['employeeUsername'],
    );
    deviceImeiController = TextEditingController(
      text: widget.shopData['deviceImei'] ?? '',
    );
  }

  Future<void> _updateShop() async {
    final shopName = shopNameController.text.trim();
    final location = shopLocationController.text.trim();
    final phone = shopPhoneController.text.trim();
    final empUsername = empUsernameController.text.trim();
    final empPassword = empPasswordController.text.trim();
    final empConfirmPassword = empConfirmPasswordController.text.trim();

    if (shopName.isEmpty) {
      _showSnackBar('Please enter shop name', isError: true);
      return;
    }
    if (phone.isEmpty || phone.length != 10) {
      _showSnackBar('Please enter valid 10-digit phone', isError: true);
      return;
    }
    if (empUsername.isEmpty) {
      _showSnackBar('Please enter username', isError: true);
      return;
    }
    if (empPassword.isNotEmpty) {
      if (empPassword.length < 6) {
        _showSnackBar('Password must be at least 6 characters', isError: true);
        return;
      }
      if (empPassword != empConfirmPassword) {
        _showSnackBar('Passwords do not match', isError: true);
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final deviceImei = deviceImeiController.text.trim();
      
      if (deviceImei.isEmpty) {
        _showSnackBar('Please enter device ID', isError: true);
        setState(() => _isLoading = false);
        return;
      }

      final updateData = {
        'shopName': shopName,
        'location': location.isEmpty ? 'N/A' : location,
        'phone': phone,
        'username': empUsername,
        'deviceImei': deviceImei,
        'updatedAt': Timestamp.now(),
      };

      if (empPassword.isNotEmpty) {
        updateData['password'] = _hashPassword(empPassword);
      }

      // Update shop_list
      await FirebaseFirestore.instance
          .collection('shop_list')
          .doc(widget.shopData['docId'])
          .update(updateData);

      // Update Credentials in shop collection
      await FirebaseFirestore.instance
          .collection(widget.shopData['collectionName'])
          .doc('Credentials')
          .update(updateData);

      _showSnackBar('Shop updated successfully');
      widget.onShopUpdated();
      Navigator.pop(context);
    } catch (e) {
      debugPrint('Error updating shop: $e');
      _showSnackBar('Error updating shop: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<String?> _getCurrentDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        final deviceId = androidInfo.id;
        debugPrint('🔍 Android Device ID retrieved: $deviceId');
        debugPrint('   Device: ${androidInfo.device}, Model: ${androidInfo.model}, Brand: ${androidInfo.brand}');
        return deviceId;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        final deviceId = iosInfo.identifierForVendor;
        debugPrint('🔍 iOS Device ID retrieved: $deviceId');
        debugPrint('   Device Name: ${iosInfo.name}, Model: ${iosInfo.model}');
        return deviceId;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      return null;
    }
  }

  Future<Map<String, String>> _getDeviceDetails() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return {
          'deviceId': androidInfo.id,
          'deviceName': androidInfo.device ?? 'Unknown',
          'model': androidInfo.model ?? 'Unknown',
          'brand': androidInfo.brand ?? 'Unknown',
          'manufacturer': androidInfo.manufacturer ?? 'Unknown',
          'platform': 'Android',
          'version': '${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})',
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return {
          'deviceId': iosInfo.identifierForVendor ?? 'Unknown',
          'deviceName': iosInfo.name ?? 'Unknown',
          'model': iosInfo.model ?? 'Unknown',
          'brand': 'Apple',
          'manufacturer': 'Apple',
          'platform': 'iOS',
          'version': '${iosInfo.systemVersion}',
        };
      }
      return {};
    } catch (e) {
      debugPrint('Error getting device details: $e');
      return {};
    }
  }

  void _showDeviceIdVerificationDialog(BuildContext context, String deviceId, Map<String, String> deviceDetails) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.phone_android, color: Color(0xFF4285F4), size: 22),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Device ID Verification',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Verify this is the correct device:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                _buildDeviceInfoRow('Platform', deviceDetails['platform'] ?? 'Unknown', Icons.phone_android),
                const SizedBox(height: 8),
                _buildDeviceInfoRow('Device Name', deviceDetails['deviceName'] ?? 'Unknown', Icons.devices),
                const SizedBox(height: 8),
                _buildDeviceInfoRow('Model', deviceDetails['model'] ?? 'Unknown', Icons.phone_iphone),
                const SizedBox(height: 8),
                _buildDeviceInfoRow('Brand', deviceDetails['brand'] ?? 'Unknown', Icons.branding_watermark),
                const SizedBox(height: 8),
                _buildDeviceInfoRow('Version', deviceDetails['version'] ?? 'Unknown', Icons.info),
                const Divider(height: 24),
                const Text(
                  'Device ID:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          deviceId,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Device ID is already in the text field'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'If the device details above match the device you want to authorize, click "Use This Device ID".',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                deviceImeiController.text = deviceId;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Device ID verified and added',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green[600],
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                minimumSize: const Size(0, 40),
              ),
              child: const Text(
                'Use Device ID',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeviceInfoRow(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '$label: ',
            style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    shopNameController.dispose();
    shopLocationController.dispose();
    shopPhoneController.dispose();
    empUsernameController.dispose();
    empPasswordController.dispose();
    empConfirmPasswordController.dispose();
    deviceImeiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: const Text('Edit Shop'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF4285F4), Color(0xFF2E7FE8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.edit, color: Colors.white, size: 40),
                      SizedBox(height: 12),
                      Text(
                        'Edit Shop',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Update shop details and employee credentials',
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                // Form
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader('Shop Details', Icons.store),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: shopNameController,
                        label: 'Shop Name',
                        hint: 'Enter shop name',
                        icon: Icons.store,
                        isRequired: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: shopLocationController,
                        label: 'Location',
                        hint: 'Enter location',
                        icon: Icons.location_on,
                        isRequired: false,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: shopPhoneController,
                        label: 'Phone Number',
                        hint: 'Enter 10-digit phone',
                        icon: Icons.phone,
                        isRequired: true,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                      ),

                      const SizedBox(height: 28),

                      _buildSectionHeader(
                        'Employee Credentials',
                        Icons.security,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: empUsernameController,
                        label: 'Username',
                        hint: 'Login username',
                        icon: Icons.account_circle,
                        isRequired: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: empPasswordController,
                        label: 'Password',
                        hint: 'Leave blank to keep current',
                        icon: Icons.lock,
                        isRequired: false,
                        obscureText: true,
                      ),
                      const SizedBox(height: 14),
                      _buildTextField(
                        controller: empConfirmPasswordController,
                        label: 'Confirm Password',
                        hint: 'Leave blank to keep current',
                        icon: Icons.lock_outline,
                        isRequired: false,
                        obscureText: true,
                      ),

                      const SizedBox(height: 20),
                      _buildSectionHeader('Device Security', Icons.phone_android),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: deviceImeiController,
                              label: 'Device ID',
                              hint: 'Enter device identifier',
                              icon: Icons.phone_android,
                              isRequired: true,
                              keyboardType: TextInputType.text,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner),
                            tooltip: 'Get Device ID from this device',
                            onPressed: () async {
                              final deviceDetails = await _getDeviceDetails();
                              final deviceId = deviceDetails['deviceId'];
                              if (deviceId != null && deviceId.isNotEmpty && mounted) {
                                _showDeviceIdVerificationDialog(context, deviceId, deviceDetails);
                              } else if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Could not get device ID'),
                                    backgroundColor: Colors.red[600],
                                  ),
                                );
                              }
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: const Color(0xFF4285F4).withOpacity(0.1),
                              padding: const EdgeInsets.all(16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Employee can only login from this device. Admin can change Device ID anytime.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[900],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.only(left: 26),
                              child: Text(
                                'How to get Device ID:\n'
                                '• Tap the QR icon to get Device ID from this device\n'
                                '• Or ask employee to login once, then check Device History page\n'
                                '• Android: Uses Android ID\n'
                                '• iOS: Uses Identifier for Vendor',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.blue[800],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // <<< EXTRA SPACE SO LAST FIELD IS ALWAYS VISIBLE >>>
                      SizedBox(height: bottomInset + 80),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // FIXED BUTTON – NEVER CUT BY NAVIGATION BAR
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: Colors.grey[200]!, width: 1),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateShop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.update, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Update Shop',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
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
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isRequired = false,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        labelStyle: const TextStyle(
          color: Color(0xFF4285F4),
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey[400],
          fontWeight: FontWeight.w400,
          fontSize: 13,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF4285F4), size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF4285F4), width: 2),
        ),
        counterText: '',
        filled: true,
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(
          vertical: 14,
          horizontal: 12,
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF4285F4), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF4285F4),
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// DEVICE HISTORY PAGE
// ─────────────────────────────────────────────────────────────────────

class DeviceHistoryPage extends StatefulWidget {
  final Map<String, dynamic> shopData;

  const DeviceHistoryPage({
    super.key,
    required this.shopData,
  });

  @override
  State<DeviceHistoryPage> createState() => _DeviceHistoryPageState();
}

class _DeviceHistoryPageState extends State<DeviceHistoryPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device History',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              widget.shopData['shopName'] ?? 'Shop',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection(widget.shopData['collectionName'])
            .doc('Credentials')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.devices_other,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No device history',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Devices will appear here after employees login',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final deviceHistory = data['deviceHistory'] as List<dynamic>? ?? [];

          if (deviceHistory.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.devices_other,
                    size: 64,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No devices logged in yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Device history will appear here after employees login',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              // StreamBuilder will automatically update
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...deviceHistory.map((device) => _buildDeviceCard(device as Map<String, dynamic>)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDeviceCard(Map<String, dynamic> device) {
    final deviceName = device['deviceName'] as String? ?? 'Unknown Device';
    final deviceModel = device['deviceModel'] as String? ?? 'Unknown';
    final platform = device['platform'] as String? ?? 'Unknown';
    final deviceId = device['deviceId'] as String? ?? '';
    final firstLoginAt = device['firstLoginAt'];
    final lastLoginAt = device['lastLoginAt'];
    final loginHistory = device['loginHistory'] as List<dynamic>? ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4).withOpacity(0.05),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.phone_android,
                    color: Color(0xFF4285F4),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deviceName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$platform • $deviceModel',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${loginHistory.length} login${loginHistory.length != 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Device Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  Icons.fingerprint,
                  'Device ID',
                  deviceId.length > 8 ? '${deviceId.substring(0, 8)}...' : deviceId,
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.calendar_today,
                  'First Login',
                  _formatTimestamp(firstLoginAt),
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.access_time,
                  'Last Login',
                  _formatTimestamp(lastLoginAt),
                ),
                // Login History Timeline
                if (loginHistory.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.history,
                        size: 18,
                        color: Color(0xFF4285F4),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Login History',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...loginHistory.asMap().entries.map((entry) {
                    final index = entry.key;
                    final timestamp = entry.value;
                    final isLast = index == loginHistory.length - 1;
                    return _buildLoginHistoryItem(timestamp, isLast, index == 0);
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginHistoryItem(dynamic timestamp, bool isLast, bool isFirst) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline indicator
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isFirst ? Colors.green : const Color(0xFF4285F4),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 30,
                color: Colors.grey[300],
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Row(
              children: [
                Icon(
                  Icons.login,
                  size: 14,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _formatTimestamp(timestamp),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isFirst)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'First',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.green,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Never';
    try {
      final ts = timestamp as Timestamp;
      return DateFormat('dd-MMM-yyyy HH:mm:ss').format(ts.toDate());
    } catch (e) {
      return 'Unknown';
    }
  }
}
