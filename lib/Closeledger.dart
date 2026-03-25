import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CloseLedgerScreen extends StatefulWidget {
  final DateTime date;
  final String? shopCollection;
  final bool startInEditMode;

  const CloseLedgerScreen({
    super.key,
    required this.date,
    this.shopCollection,
    this.startInEditMode = false,
  });

  @override
  State<CloseLedgerScreen> createState() => _CloseLedgerScreenState();
}

class _CloseLedgerScreenState extends State<CloseLedgerScreen> {
  late DateTime _selectedDate;
  final List<int> denominations = [500, 100, 50, 20, 10, 1];
  late List<TextEditingController> _controllers;
  late TextEditingController _salesController;
  late TextEditingController _cashOutController;
  late List<int> _denominationTotals;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditMode = false;
  bool _isInitialLoad = true;
  Timer? _debounceTimer;

  int _openingBalance = 0;
  int _closingBalance = 0;
  bool _ledgerClosed = false;

  // Shop info
  String? _selectedShopCollection;
  String _userRole = '';
  bool _isEmployeeLogin = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.date;

    _controllers = List.generate(
      denominations.length,
      (_) => TextEditingController(),
    );
    _salesController = TextEditingController();
    _cashOutController = TextEditingController();
    _denominationTotals = List.generate(denominations.length, (_) => 0);

    for (int i = 0; i < _controllers.length; i++) {
      _controllers[i].addListener(() => _updateTotal(i));
    }

    _initializeAndLoad();
  }

  Future<void> _initializeAndLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginType = prefs.getString('loginType') ?? 'employee';
      final shopCollection =
          widget.shopCollection ??
          prefs.getString('shopCollection') ??
          'vks_retails';

      setState(() {
        _userRole = loginType;
        _isEmployeeLogin = loginType == 'employee';
        _selectedShopCollection = shopCollection;
      });

      await _loadLedgerData();
    } catch (e) {
      debugPrint('Error initializing: $e');
      setState(() => _isLoading = false);
    }
  }

  void _updateTotal(int index) {
    int count = int.tryParse(_controllers[index].text) ?? 0;
    setState(() {
      _denominationTotals[index] = count * denominations[index];
    });
  }

  int get _grandTotal {
    return _denominationTotals.fold(0, (sum, t) => sum + t);
  }

  int get _totalNotes =>
      _controllers.fold(0, (sum, c) => sum + (int.tryParse(c.text) ?? 0));

  Future<void> _loadLedgerData() async {
    setState(() => _isLoading = true);

    try {
      if (_selectedShopCollection == null) {
        throw Exception('Shop collection not available');
      }

      final firestore = FirebaseFirestore.instance;
      final ledgerDate = DateFormat('dd-MMM-yyyy').format(_selectedDate);

      // Get ledger from: shopCollection/ledgers/dates/{ledgerDate}
      final docRef = firestore
          .collection(_selectedShopCollection!)
          .doc('ledgers')
          .collection('dates')
          .doc(ledgerDate);

      final doc = await docRef.get();

      if (!doc.exists) {
        _showErrorDialog('No ledger found for this date');
        return;
      }

      final data = doc.data();

      final ob = data?['openingBalance'];
      _openingBalance = ob is int ? ob : (ob is double ? ob.toInt() : 0);

      final cb = data?['closingBalance'];
      _closingBalance = cb is int ? cb : (cb is double ? cb.toInt() : 0);

      _ledgerClosed =
          (data?['status'] ?? '').toString().toLowerCase() == 'closed';

      if (_ledgerClosed) {
        final denominationsMap = Map<String, dynamic>.from(
          data?['denominations'] ?? {},
        );

        for (int i = 0; i < denominations.length; i++) {
          final key = denominations[i].toString();
          int count = 0;

          if (denominationsMap.containsKey(key)) {
            final v = denominationsMap[key];
            count = v is int ? v : (v is double ? v.toInt() : 0);
          }

          _controllers[i].text = count.toString();
          _denominationTotals[i] = count * denominations[i];
        }
        
        _salesController.text = (data?['saleValue'] ?? 0).toString();
        _cashOutController.text = (data?['cashOut'] ?? 0).toString();

        // Auto-enter edit mode if requested (only on initial load)
        if (widget.startInEditMode && _isInitialLoad) {
          _isEditMode = true;
        }
        
        // Mark that initial load is complete
        _isInitialLoad = false;
      } else {
        // Set all denominations to 0 (removed auto-calculation)
        for (int i = 0; i < denominations.length; i++) {
          _controllers[i].text = '0';
          _denominationTotals[i] = 0;
        }
      }

    } catch (e) {
      debugPrint('Error loading ledger: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading ledger: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveLedgerToFirestore() async {
    // Prevent duplicate submissions
    // Allow saving if in edit mode (even if ledger is closed)
    if (_isSaving || (_ledgerClosed && !_isEditMode)) {
      return;
    }

    // Validate sales value
    if (_salesController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter sales value'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final double salesValue =
        double.tryParse(_salesController.text.replaceAll(',', '').trim()) ??
        0.0;

    if (salesValue <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid sales value'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate cash out value
    if (_cashOutController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter cash out value'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final double cashOut =
        double.tryParse(_cashOutController.text.replaceAll(',', '').trim()) ??
        0.0;

    if (cashOut < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid cash out value (must be >= 0)'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Cancel any existing debounce timer
    _debounceTimer?.cancel();

    // Set saving state immediately to disable button
    setState(() {
      _isSaving = true;
      _isLoading = true;
    });

    // Debounce: wait 400ms before sending the update
    _debounceTimer = Timer(const Duration(milliseconds: 400), () async {
      await _performSave(salesValue, cashOut);
    });
  }

  Future<void> _performSave(double salesValue, double cashOut) async {
    const maxRetries = 3;
    const timeoutDuration = Duration(seconds: 30);
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        if (_selectedShopCollection == null) {
          throw Exception('Shop collection not available');
        }

        final firestore = FirebaseFirestore.instance;
        final ledgerDate = DateFormat('dd-MMM-yyyy').format(_selectedDate);

        // Reference: shopCollection/ledgers/dates/{ledgerDate}
        final docRef = firestore
            .collection(_selectedShopCollection!)
            .doc('ledgers')
            .collection('dates')
            .doc(ledgerDate);

        // Store ONLY user inputs (counts), not calculated values
        // Calculate closing balance from user inputs at save time
        final Map<String, int> denominationMap = {};
        int closingBalance = 0;

        for (int i = 0; i < denominations.length; i++) {
          // Get user input count
          final count = int.tryParse(_controllers[i].text) ?? 0;
          // Ensure count is non-negative
          final safeCount = count < 0 ? 0 : count;
          
          // Store only the count (user input)
          denominationMap[denominations[i].toString()] = safeCount;
          
          // Calculate closing balance from user inputs
          closingBalance += safeCount * denominations[i];
          
          // Update _denominationTotals to keep UI in sync
          _denominationTotals[i] = safeCount * denominations[i];
        }

        // Validate closing balance is non-negative
        if (closingBalance < 0) {
          throw Exception(
              'Invalid closing balance: $closingBalance. Please check denomination counts.');
        }

        // Debug logging
        debugPrint('Saving ledger with user inputs:');
        debugPrint('  Denominations (counts): $denominationMap');
        debugPrint('  Calculated Closing Balance: $closingBalance');
        debugPrint('  Sales Value: $salesValue');

        // Use transaction with timeout to ensure atomic update
        await firestore.runTransaction(
          (transaction) async {
            // Get document with timeout handling
            final doc = await transaction.get(docRef).timeout(
              timeoutDuration,
              onTimeout: () {
                throw Exception(
                    'Network timeout. Please check your internet connection and try again.');
              },
            );

            if (!doc.exists) {
              throw Exception('Ledger document not found');
            }

            final data = doc.data();
            final existingLastUpdated = data?['lastUpdated'];

            // Check if there's a newer update already saved
            // Use server timestamp comparison to avoid client clock issues
            if (existingLastUpdated != null) {
              int existingTimestamp = 0;
              if (existingLastUpdated is int) {
                existingTimestamp = existingLastUpdated;
              } else if (existingLastUpdated is double) {
                existingTimestamp = existingLastUpdated.toInt();
              } else if (existingLastUpdated is Timestamp) {
                existingTimestamp = existingLastUpdated.millisecondsSinceEpoch;
              } else if (existingLastUpdated is Map) {
                // Handle Firestore Timestamp format (when serialized)
                final seconds = existingLastUpdated['_seconds'] as int? ?? 0;
                final nanoseconds = existingLastUpdated['_nanoseconds'] as int? ?? 0;
                existingTimestamp = (seconds * 1000) + (nanoseconds ~/ 1000000);
              }

              // Use server timestamp for comparison to avoid client clock issues
              // Get current server time for accurate comparison
              final serverTime = Timestamp.now();
              final currentServerMillis = serverTime.millisecondsSinceEpoch;

              // Allow update if our server time is newer, or if existing is more than 1 second old
              // This handles slow network where client timestamp might be slightly behind
              if (currentServerMillis <= existingTimestamp - 1000) {
                throw Exception(
                    'A newer update was already saved. Please refresh and try again.');
              }
            }

            // Update the ledger document - Store only user inputs
            // closingBalance is calculated from denominations at read time
            final updateData = <String, dynamic>{
              // Store user inputs only
              'denominations': denominationMap, // User input counts
              'saleValue': salesValue, // User input
              'cashOut': cashOut, // User input
              // Calculate and store closing balance from user inputs
              'closingBalance': closingBalance,
              // Use server timestamp to avoid client clock issues
              'lastUpdated': FieldValue.serverTimestamp(),
            };

            if (_isEditMode) {
              // In edit mode, update existing closed ledger
              updateData['updatedAt'] = FieldValue.serverTimestamp();
              updateData['status'] = 'Closed';
              // Don't update closedAt - keep original
            } else {
              // First time closing
              updateData['status'] = 'Closed';
              updateData['closedAt'] = FieldValue.serverTimestamp();
            }

            transaction.update(docRef, updateData);
          },
        ).timeout(
          timeoutDuration,
          onTimeout: () {
            throw Exception(
                'Network timeout. Please check your internet connection and try again.');
          },
        );

        // Success - update local state
        _closingBalance = closingBalance;
        _ledgerClosed = true;

        // Reset saving state
        if (mounted) {
          setState(() {
            _isSaving = false;
            // Keep _isLoading true if in edit mode (will reload after dialog)
            // Set to false if not in edit mode (will show success dialog)
            if (!_isEditMode) {
              _isLoading = false;
            }
          });
        }

        if (!mounted) return;
        if (_isEditMode) {
          _showUpdateSuccessDialog(closingBalance);
        } else {
          _showSuccessDialog(closingBalance);
        }

        // Success - exit retry loop
        return;
      } catch (e) {
        retryCount++;
        debugPrint('Error closing ledger (attempt $retryCount/$maxRetries): $e');

        // Check if it's a network-related error that we should retry
        final errorString = e.toString().toLowerCase();
        final isNetworkError = errorString.contains('network') ||
            errorString.contains('timeout') ||
            errorString.contains('connection') ||
            errorString.contains('unavailable') ||
            errorString.contains('failed host lookup') ||
            errorString.contains('socketexception');

        // Don't retry for validation errors or timestamp conflicts
        final isNonRetryableError = errorString.contains('newer update') ||
            errorString.contains('invalid') ||
            errorString.contains('not found') ||
            errorString.contains('collection not available');

        if (isNonRetryableError || retryCount >= maxRetries) {
          // Final attempt failed or non-retryable error
          if (mounted) {
            String errorMessage = _getUserFriendlyErrorMessage(e);
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
                action: isNetworkError && retryCount >= maxRetries
                    ? SnackBarAction(
                        label: 'Retry',
                        textColor: Colors.white,
                        onPressed: () {
                          _saveLedgerToFirestore();
                        },
                      )
                    : null,
              ),
            );

            // Reload data if there was a conflict
            if (errorString.contains('newer update')) {
              await _loadLedgerData();
            }
          }
          break;
        }

        // Wait before retrying (exponential backoff)
        if (retryCount < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * retryCount));
        }
      }
    }

    // If we get here, all retries failed
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isLoading = false;
      });
    }
  }

  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('network') || errorString.contains('timeout')) {
      return 'Network connection issue. Please check your internet and try again.';
    } else if (errorString.contains('connection') || errorString.contains('unavailable')) {
      return 'Unable to connect to server. Please check your internet connection.';
    } else if (errorString.contains('newer update')) {
      return 'A newer update was already saved. Please refresh and try again.';
    } else if (errorString.contains('not found')) {
      return 'Ledger document not found. Please refresh the page.';
    } else if (errorString.contains('invalid')) {
      return error.toString().replaceFirst('Exception: ', '');
    } else {
      return 'Failed to save ledger. Please try again.';
    }
  }

  void _showSuccessDialog(int closingBalance) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green[600],
                  size: 60,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Ledger Closed!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Your ledger has been closed successfully with closing balance of ₹${NumberFormat('#,##,##0').format(closingBalance)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUpdateSuccessDialog(int closingBalance) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: Colors.blue[600],
                  size: 60,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Ledger Updated!',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Your ledger has been updated successfully with closing balance of ₹${NumberFormat('#,##,##0').format(closingBalance)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    // Exit edit mode
                    setState(() {
                      _isEditMode = false;
                    });
                    // Reload ledger data to get the latest values from Firestore
                    // _loadLedgerData() will handle the loading state
                    await _loadLedgerData();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _cancelEdit() {
    setState(() {
      _isEditMode = false;
    });
    // Reload data to restore original values
    _loadLedgerData();
  }

  void _showConfirmCloseDialog() {
    if (_isSaving || (_ledgerClosed && !_isEditMode)) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange[700], size: 28),
            const SizedBox(width: 12),
            const Text('Confirm Close'),
          ],
        ),
        content: const Text(
          'Are you sure you want to close this ledger?\nThis action cannot be undone.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isSaving
                ? null
                : () {
                    Navigator.pop(context);
                    _saveLedgerToFirestore();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
            ),
            child: const Text('Close Ledger'),
          ),
        ],
      ),
    );
  }

  void _showConfirmUpdateDialog() {
    if (_isSaving || !_isEditMode) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange[700], size: 28),
            const SizedBox(width: 12),
            const Text('Confirm Update'),
          ],
        ),
        content: const Text(
          'Are you sure you want to update this closed ledger?\nThe changes will be saved with a new timestamp.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _isSaving
                ? null
                : () {
                    Navigator.pop(context);
                    _saveLedgerToFirestore();
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
              foregroundColor: Colors.white,
            ),
            child: const Text('Update Ledger'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    _salesController.dispose();
    _cashOutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Close Ledger',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('dd MMM yyyy').format(_selectedDate),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: _ledgerClosed && !_isEditMode && !_isEmployeeLogin
            ? [
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Edit Ledger',
                  onPressed: () {
                    setState(() {
                      _isEditMode = true;
                    });
                  },
                ),
              ]
            : _isEditMode
                ? [
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Cancel Edit',
                      onPressed: () {
                        _cancelEdit();
                      },
                    ),
                  ]
                : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Opening Balance Card
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue[400]!, Colors.blue[600]!],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.account_balance,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Opening Balance',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '₹${NumberFormat('#,##,##0').format(_openingBalance)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Denomination Section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Denomination Count',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _ledgerClosed && !_isEditMode
                              ? 'Ledger closed - View only'
                              : _isEditMode
                                  ? 'Editing closed ledger values'
                                  : 'Enter the count of each denomination',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 12),

                        ...List.generate(denominations.length, (i) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 55,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.blue[400]!,
                                        Colors.blue[600]!,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '₹${denominations[i]}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  '×',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  width: 70,
                                  decoration: BoxDecoration(
                                    color: (_ledgerClosed && !_isEditMode)
                                        ? Colors.grey[200]
                                        : Colors.grey[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey[300]!,
                                    ),
                                  ),
                                  child: TextField(
                                    controller: _controllers[i],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    enabled: !_ledgerClosed || _isEditMode,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: '0',
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 10,
                                      ),
                                      border: InputBorder.none,
                                    ),
                                    onTap: () {
                                      // Select all text when tapped, especially if it's "0"
                                      if (_controllers[i].text == '0' || _controllers[i].text.isEmpty) {
                                        _controllers[i].clear();
                                      } else {
                                        _controllers[i].selection = TextSelection(
                                          baseOffset: 0,
                                          extentOffset: _controllers[i].text.length,
                                        );
                                      }
                                    },
                                  ),
                                ),
                                const Spacer(),
                                const Text(
                                  '=',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '₹${NumberFormat('#,##,##0').format(_denominationTotals[i])}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[700],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        const SizedBox(height: 8),

                        // Total Cash Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.green[400]!, Colors.green[600]!],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Cash',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                    ),
                                  ),
                                  Text(
                                    '₹${NumberFormat('#,##,##0').format(_grandTotal)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Notes',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '$_totalNotes notes',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Sales Value (Required)
                        Row(
                          children: [
                            const Text(
                              'Sales Value',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '*',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _salesController,
                          keyboardType: TextInputType.number,
                          enabled: !_ledgerClosed || _isEditMode,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Enter today\'s sales value...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[400],
                            ),
                            filled: true,
                            fillColor: (_ledgerClosed && !_isEditMode)
                                ? Colors.grey[200]
                                : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFF4285F4),
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Cash Out (Required)
                        Row(
                          children: [
                            const Text(
                              'Cash Out',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '*',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red[600],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _cashOutController,
                          keyboardType: TextInputType.number,
                          enabled: !_ledgerClosed || _isEditMode,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Enter cash out amount...',
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[400],
                            ),
                            filled: true,
                            fillColor: (_ledgerClosed && !_isEditMode)
                                ? Colors.grey[200]
                                : Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                color: Color(0xFF4285F4),
                                width: 2,
                              ),
                            ),
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),

                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: (_ledgerClosed && !_isEditMode)
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextButton(
                        onPressed: _isEditMode
                            ? _cancelEdit
                            : () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          _isEditMode ? 'Cancel Edit' : 'Cancel',
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: ElevatedButton(
                        onPressed: (_isSaving || (_ledgerClosed && !_isEditMode))
                            ? null
                            : _isEditMode
                                ? _showConfirmUpdateDialog
                                : _showConfirmCloseDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4285F4),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[400],
                          disabledForegroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 2,
                        ),
                        child: _isSaving
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Saving...',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isEditMode ? Icons.save : Icons.check_circle,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _isEditMode ? 'Save Changes' : 'Close Ledger',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}