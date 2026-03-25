import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _isLoading = true;
  String _currentUsername = '';
  String _storedPassword = '';

  @override
  void initState() {
    super.initState();
    _fetchAdminData();
  }

  /// Fetch current admin credentials
  Future<void> _fetchAdminData() async {
    try {
      final adminDoc = await FirebaseFirestore.instance
          .collection('adminlogin')
          .doc('gVqhngvSiXV7fHIUVL2u')
          .get();

      if (adminDoc.exists) {
        final data = adminDoc.data()!;
        setState(() {
          _currentUsername = data['username'] ?? '';
          _storedPassword = data['password'] ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching admin data: $e');
      setState(() => _isLoading = false);
    }
  }

  /// Show dialog to change username
  Future<void> _showChangeUsernameDialog() async {
    final TextEditingController usernameController = TextEditingController(
      text: _currentUsername,
    );
    final TextEditingController passwordController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Change Username'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: usernameController,
              decoration: const InputDecoration(
                labelText: 'New Username',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (usernameController.text.trim().isEmpty) {
                _showSnackBar('Please enter a username', isError: true);
                return;
              }
              if (passwordController.text != _storedPassword) {
                _showSnackBar('Incorrect password', isError: true);
                return;
              }
              if (usernameController.text.trim() == _currentUsername) {
                _showSnackBar('Username is the same', isError: true);
                return;
              }

              Navigator.pop(context, true);

              try {
                await FirebaseFirestore.instance
                    .collection('adminlogin')
                    .doc('gVqhngvSiXV7fHIUVL2u')
                    .update({'username': usernameController.text.trim()});

                setState(() {
                  _currentUsername = usernameController.text.trim();
                });

                _showSnackBar('Username updated successfully!');
              } catch (e) {
                _showSnackBar('Failed to update username', isError: true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  /// Show dialog to change password
  Future<void> _showChangePasswordDialog() async {
    final TextEditingController currentPasswordController =
        TextEditingController();
    final TextEditingController newPasswordController = TextEditingController();
    final TextEditingController confirmPasswordController =
        TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current Password',
                prefixIcon: Icon(Icons.lock_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New Password',
                prefixIcon: Icon(Icons.vpn_key),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm New Password',
                prefixIcon: Icon(Icons.check_circle_outline),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (currentPasswordController.text != _storedPassword) {
                _showSnackBar('Current password is incorrect', isError: true);
                return;
              }
              if (newPasswordController.text.length < 6) {
                _showSnackBar(
                  'Password must be at least 6 characters',
                  isError: true,
                );
                return;
              }
              if (newPasswordController.text !=
                  confirmPasswordController.text) {
                _showSnackBar('Passwords do not match', isError: true);
                return;
              }

              Navigator.pop(context, true);

              try {
                await FirebaseFirestore.instance
                    .collection('adminlogin')
                    .doc('gVqhngvSiXV7fHIUVL2u')
                    .update({'password': newPasswordController.text});

                setState(() {
                  _storedPassword = newPasswordController.text;
                });

                _showSnackBar('Password updated successfully!');
              } catch (e) {
                _showSnackBar('Failed to update password', isError: true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ],
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
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: const Text(
          'Account Settings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Current Username Display
                ListTile(
                  leading: const Icon(Icons.person, color: Colors.black54),
                  title: const Text(
                    'Username',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    _currentUsername,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey,
                  ),
                  onTap: _showChangeUsernameDialog,
                ),
                const Divider(height: 1),

                // Change Password
                ListTile(
                  leading: const Icon(Icons.lock, color: Colors.black54),
                  title: const Text(
                    'Password',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text(
                    'Tap to change your password',
                    style: TextStyle(color: Colors.black54),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey,
                  ),
                  onTap: _showChangePasswordDialog,
                ),
                const Divider(height: 1),

                // Info Section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue[700]),
                            const SizedBox(width: 12),
                            Text(
                              'Account Information',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[900],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '• Change your username anytime\n'
                          '• Update your password securely\n'
                          '• Password must be at least 6 characters\n'
                          '• Remember your new credentials',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue[900],
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
    );
  }
}
