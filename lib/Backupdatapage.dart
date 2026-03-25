import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class BackupDataPage extends StatefulWidget {
  const BackupDataPage({super.key});

  @override
  State<BackupDataPage> createState() => _BackupDataPageState();
}

class _BackupDataPageState extends State<BackupDataPage> {
  bool _isBackingUp = false;
  bool _isRestoring = false;
  bool _isLoadingBackups = true;
  bool _autoBackupEnabled = false;
  List<Map<String, dynamic>> _backupsList = [];

  @override
  void initState() {
    super.initState();
    _loadBackupsList();
    _loadAutoBackupSettings();
    _checkAndPerformAutoBackup();
  }

  /// Load auto backup settings
  Future<void> _loadAutoBackupSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoBackupEnabled = prefs.getBool('autoBackupEnabled') ?? false;
    });
  }

  /// Save auto backup settings
  Future<void> _saveAutoBackupSettings(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoBackupEnabled', enabled);
    if (enabled) {
      await prefs.setString('lastAutoBackup', DateTime.now().toIso8601String());
    }
    setState(() {
      _autoBackupEnabled = enabled;
    });
  }

  /// Check if auto backup is needed (weekly)
  Future<void> _checkAndPerformAutoBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final autoBackupEnabled = prefs.getBool('autoBackupEnabled') ?? false;

    if (!autoBackupEnabled) return;

    final lastBackupStr = prefs.getString('lastAutoBackup');
    if (lastBackupStr == null) {
      // First time, create backup
      await _createBackup(isAuto: true);
      return;
    }

    final lastBackup = DateTime.parse(lastBackupStr);
    final daysSinceLastBackup = DateTime.now().difference(lastBackup).inDays;

    // If 7 or more days have passed, create automatic backup
    if (daysSinceLastBackup >= 7) {
      await _createBackup(isAuto: true);
    }
  }

  /// Convert Timestamp objects to ISO strings recursively
  Map<String, dynamic> _convertTimestamps(Map<String, dynamic> data) {
    final Map<String, dynamic> result = {};

    data.forEach((key, value) {
      if (value is Timestamp) {
        result[key] = value.toDate().toIso8601String();
      } else if (value is Map) {
        result[key] = _convertTimestamps(Map<String, dynamic>.from(value));
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is Timestamp) {
            return item.toDate().toIso8601String();
          } else if (item is Map) {
            return _convertTimestamps(Map<String, dynamic>.from(item));
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    });

    return result;
  }

  /// Convert ISO strings back to Timestamps recursively
  Map<String, dynamic> _convertToTimestamps(Map<String, dynamic> data) {
    final Map<String, dynamic> result = {};

    data.forEach((key, value) {
      if (value is String && value.contains('T') && value.contains('Z')) {
        try {
          result[key] = Timestamp.fromDate(DateTime.parse(value));
        } catch (e) {
          result[key] = value;
        }
      } else if (value is Map) {
        result[key] = _convertToTimestamps(Map<String, dynamic>.from(value));
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is String && item.contains('T') && item.contains('Z')) {
            try {
              return Timestamp.fromDate(DateTime.parse(item));
            } catch (e) {
              return item;
            }
          } else if (item is Map) {
            return _convertToTimestamps(Map<String, dynamic>.from(item));
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    });

    return result;
  }

  /// Load list of available backups from Firebase Storage
  Future<void> _loadBackupsList() async {
    setState(() => _isLoadingBackups = true);

    try {
      final storageRef = FirebaseStorage.instance.ref().child('backups');
      final listResult = await storageRef.listAll();

      List<Map<String, dynamic>> backups = [];

      for (var item in listResult.items) {
        final metadata = await item.getMetadata();
        backups.add({
          'name': item.name,
          'path': item.fullPath,
          'size': metadata.size,
          'createdAt': metadata.timeCreated,
          'reference': item,
        });
      }

      // Sort by date (newest first)
      backups.sort(
        (a, b) =>
            (b['createdAt'] as DateTime?)?.compareTo(
              a['createdAt'] as DateTime? ?? DateTime.now(),
            ) ??
            0,
      );

      setState(() {
        _backupsList = backups;
        _isLoadingBackups = false;
      });
    } catch (e) {
      debugPrint('Error loading backups: $e');
      setState(() => _isLoadingBackups = false);
      if (mounted) {
        _showSnackBar('Failed to load backups', isError: true);
      }
    }
  }

  /// Create backup and upload to Firebase Storage
  Future<void> _createBackup({bool isAuto = false}) async {
    if (!isAuto) {
      setState(() => _isBackingUp = true);
    }

    try {
      // 1. Fetch all ledgers
      final ledgersSnapshot = await FirebaseFirestore.instance
          .collection('ledgers')
          .get();

      List<Map<String, dynamic>> allData = [];

      // 2. For each ledger, fetch its transactions
      for (var ledgerDoc in ledgersSnapshot.docs) {
        Map<String, dynamic> ledgerData = Map<String, dynamic>.from(
          ledgerDoc.data(),
        );
        ledgerData['id'] = ledgerDoc.id;

        // Fetch transactions for this ledger
        final transactionsSnapshot = await ledgerDoc.reference
            .collection('transactions')
            .get();

        List<Map<String, dynamic>> transactions = [];
        for (var transDoc in transactionsSnapshot.docs) {
          Map<String, dynamic> transData = Map<String, dynamic>.from(
            transDoc.data(),
          );
          transData['id'] = transDoc.id;
          transactions.add(transData);
        }

        ledgerData['transactions'] = transactions;
        allData.add(_convertTimestamps(ledgerData));
      }

      // 3. Create JSON backup
      final backupData = {
        'backupDate': DateTime.now().toIso8601String(),
        'totalLedgers': allData.length,
        'isAutoBackup': isAuto,
        'data': allData,
      };

      final jsonString = jsonEncode(backupData);

      // 4. Upload to Firebase Storage
      final prefix = isAuto ? 'auto_backup' : 'backup';
      final fileName =
          '${prefix}_${DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now())}.json';
      final storageRef = FirebaseStorage.instance.ref().child(
        'backups/$fileName',
      );

      await storageRef.putString(jsonString);

      // Update last auto backup time
      if (isAuto) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'lastAutoBackup',
          DateTime.now().toIso8601String(),
        );
      }

      if (mounted && !isAuto) {
        _showSnackBar('Backup created successfully!');
        _loadBackupsList();
      }
    } catch (e) {
      debugPrint('Error creating backup: $e');
      if (mounted && !isAuto) {
        _showSnackBar('Failed to create backup: $e', isError: true);
      }
    } finally {
      if (mounted && !isAuto) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  /// Restore from a backup file
  Future<void> _restoreFromBackup(Map<String, dynamic> backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Restore Backup?'),
        content: const Text(
          'This will replace all current data with the backup data. Current data will be lost!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              foregroundColor: Colors.white,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isRestoring = true);

    try {
      final storageRef = backup['reference'] as Reference;
      final downloadData = await storageRef.getData();
      final jsonString = utf8.decode(downloadData!);
      final backupData = jsonDecode(jsonString);

      final data = backupData['data'] as List;

      // Delete all existing ledgers
      final existingLedgers = await FirebaseFirestore.instance
          .collection('ledgers')
          .get();
      for (var doc in existingLedgers.docs) {
        await doc.reference.delete();
      }

      // Restore ledgers and transactions
      for (var ledgerItem in data) {
        Map<String, dynamic> ledger = Map<String, dynamic>.from(ledgerItem);
        final transactions = List<Map<String, dynamic>>.from(
          (ledger['transactions'] as List? ?? []).map(
            (e) => Map<String, dynamic>.from(e),
          ),
        );

        ledger.remove('transactions');
        ledger.remove('id');
        ledger = _convertToTimestamps(ledger);

        final ledgerRef = await FirebaseFirestore.instance
            .collection('ledgers')
            .add(ledger);

        for (var transItem in transactions) {
          Map<String, dynamic> transaction = Map<String, dynamic>.from(
            transItem,
          );
          transaction.remove('id');
          transaction = _convertToTimestamps(transaction);
          await ledgerRef.collection('transactions').add(transaction);
        }
      }

      if (mounted) {
        _showSnackBar('Data restored successfully!');
      }
    } catch (e) {
      debugPrint('Error restoring backup: $e');
      if (mounted) {
        _showSnackBar('Failed to restore backup: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isRestoring = false);
      }
    }
  }

  /// Delete a backup file
  Future<void> _deleteBackup(Map<String, dynamic> backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Backup?'),
        content: const Text(
          'Are you sure you want to delete this backup? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final storageRef = backup['reference'] as Reference;
      await storageRef.delete();
      _showSnackBar('Backup deleted successfully');
      _loadBackupsList();
    } catch (e) {
      debugPrint('Error deleting backup: $e');
      _showSnackBar('Failed to delete backup', isError: true);
    }
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

  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: const Text(
          'Backup Data',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
      body: _isLoadingBackups
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Auto Backup Toggle
                ListTile(
                  leading: const Icon(Icons.schedule, color: Colors.black54),
                  title: const Text(
                    'Automatic Weekly Backup',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    _autoBackupEnabled
                        ? 'Enabled - Backs up every 7 days'
                        : 'Disabled',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  trailing: Switch(
                    value: _autoBackupEnabled,
                    activeColor: const Color(0xFF4285F4),
                    onChanged: (value) {
                      _saveAutoBackupSettings(value);
                    },
                  ),
                ),
                const Divider(height: 1),

                // Create Backup Button
                ListTile(
                  leading: _isBackingUp
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup, color: Colors.black54),
                  title: Text(
                    _isBackingUp ? 'Creating Backup...' : 'Create New Backup',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: const Text(
                    'Manually backup all data now',
                    style: TextStyle(color: Colors.black54),
                  ),
                  trailing: _isBackingUp
                      ? null
                      : const Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: Colors.grey,
                        ),
                  enabled: !_isBackingUp,
                  onTap: _isBackingUp ? null : () => _createBackup(),
                ),
                const Divider(height: 1),

                // Available Backups Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Row(
                    children: [
                      const Text(
                        'Available Backups',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _loadBackupsList,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                ),

                // Backups List
                if (_backupsList.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.cloud_off,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No backups found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create your first backup',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...List.generate(_backupsList.length, (index) {
                    final backup = _backupsList[index];
                    final createdAt = backup['createdAt'] as DateTime?;
                    final size = backup['size'] as int?;
                    final name = backup['name'] as String;
                    final isAutoBackup = name.startsWith('auto_');

                    return Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            isAutoBackup ? Icons.schedule : Icons.folder_zip,
                            color: Colors.black54,
                          ),
                          title: Text(
                            isAutoBackup ? 'Auto Backup' : 'Manual Backup',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                createdAt != null
                                    ? DateFormat(
                                        'dd MMM yyyy, hh:mm a',
                                      ).format(createdAt)
                                    : 'Unknown date',
                                style: const TextStyle(fontSize: 13),
                              ),
                              Text(
                                _formatFileSize(size),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert),
                            onSelected: (value) {
                              if (value == 'restore') {
                                _restoreFromBackup(backup);
                              } else if (value == 'delete') {
                                _deleteBackup(backup);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'restore',
                                child: Row(
                                  children: [
                                    Icon(Icons.restore, size: 20),
                                    SizedBox(width: 12),
                                    Text('Restore'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      size: 20,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Delete',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    );
                  }),

                const SizedBox(height: 16),

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
                              'About Backups',
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
                          '• Auto backup creates weekly backups\n'
                          '• Manual backups can be created anytime\n'
                          '• All ledgers and transactions included\n'
                          '• Restore replaces current data\n'
                          '• Stored securely in Firebase Cloud',
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
