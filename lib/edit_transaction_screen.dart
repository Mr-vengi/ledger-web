import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class EditTransactionScreen extends StatefulWidget {
  final DocumentSnapshot transactionDoc;
  final Map<String, dynamic> transactionData;
  final String shopCollection;
  final DateTime ledgerDate;

  const EditTransactionScreen({
    super.key,
    required this.transactionDoc,
    required this.transactionData,
    required this.shopCollection,
    required this.ledgerDate,
  });

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  late TextEditingController _amountController;
  late TextEditingController _nameController;
  bool _isCredit = false;
  bool _isLoading = false;

  // Original values for balance calculation
  late double _originalAmount;
  late bool _originalIsCredit;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    // Store original values
    _originalAmount = (widget.transactionData['amount'] ?? 0).toDouble();
    _originalIsCredit = widget.transactionData['isCredit'] ?? false;

    // Initialize form with current values
    _amountController = TextEditingController(text: _originalAmount.toString());
    _nameController = TextEditingController(text: _getTransactionTitle());
    _isCredit = _originalIsCredit;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Get transaction title from existing data
  String _getTransactionTitle() {
    final transactionType =
        widget.transactionData['transactionType']?.toString() ?? '';
    final customerName =
        widget.transactionData['customerName']?.toString() ?? '';
    final ledgerName = widget.transactionData['ledgerName']?.toString() ?? '';
    final description = widget.transactionData['description']?.toString() ?? '';

    if (transactionType == 'Customer' && customerName.isNotEmpty) {
      return customerName;
    } else if (transactionType == 'General' && ledgerName.isNotEmpty) {
      return ledgerName;
    } else if (customerName.isNotEmpty) {
      return customerName;
    } else if (ledgerName.isNotEmpty) {
      return ledgerName;
    } else if (description.isNotEmpty) {
      return description;
    } else {
      return 'Unnamed Transaction';
    }
  }

  /// Update transaction with correct balance calculation
  Future<void> _updateTransaction() async {
    if (_amountController.text.trim().isEmpty ||
        _nameController.text.trim().isEmpty) {
      _showSnackBar('Please fill all fields', isError: true);
      return;
    }

    double newAmount;
    try {
      newAmount = double.parse(_amountController.text.trim());
      if (newAmount <= 0) {
        _showSnackBar('Amount must be greater than 0', isError: true);
        return;
      }
    } catch (e) {
      _showSnackBar('Please enter a valid amount', isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Start a batch write for atomic updates
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // ✅ STEP 1: Update the transaction document
      Map<String, dynamic> updateData = {
        'amount': newAmount,
        'isCredit': _isCredit,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Update name field based on transaction type
      final transactionType =
          widget.transactionData['transactionType']?.toString() ?? 'General';
      if (transactionType == 'Customer') {
        updateData['customerName'] = _nameController.text.trim();
      } else if (transactionType == 'General') {
        updateData['ledgerName'] = _nameController.text.trim();
      } else {
        updateData['description'] = _nameController.text.trim();
      }

      batch.update(widget.transactionDoc.reference, updateData);

      // ✅ STEP 2: Calculate and update closing balance correctly
      await _updateClosingBalance(batch, newAmount, _isCredit);

      // Commit all changes atomically
      await batch.commit();

      if (mounted) {
        _showSnackBar('Transaction updated successfully');
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      debugPrint('Error updating transaction: $e');
      if (mounted) {
        _showSnackBar('Error updating transaction: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Calculate and update closing balance with correct logic
  Future<void> _updateClosingBalance(
    WriteBatch batch,
    double newAmount,
    bool newIsCredit,
  ) async {
    try {
      final ledgerDate = DateFormat('dd-MMM-yyyy').format(widget.ledgerDate);

      // Get the ledger document
      final ledgerQuery = await FirebaseFirestore.instance
          .collection(widget.shopCollection)
          .doc('ledgers')
          .collection('dates')
          .where('ledgerDate', isEqualTo: ledgerDate)
          .limit(1)
          .get();

      if (ledgerQuery.docs.isEmpty) {
        debugPrint('Ledger document not found');
        return;
      }

      final ledgerDoc = ledgerQuery.docs.first;
      final currentClosingBalance = (ledgerDoc.data()['closingBalance'] ?? 0)
          .toDouble();

      // ✅ CORRECT BALANCE CALCULATION LOGIC
      // Payment IN = DEBIT (isCredit = false) = subtracts from balance
      // Payment OUT = CREDIT (isCredit = true) = adds to balance
      // Step 1: Remove the impact of the original transaction
      double adjustedBalance = currentClosingBalance;

      if (_originalIsCredit) {
        // Original was Payment OUT (CREDIT) - it added to balance, so subtract it back
        adjustedBalance -= _originalAmount;
      } else {
        // Original was Payment IN (DEBIT) - it subtracted from balance, so add it back
        adjustedBalance += _originalAmount;
      }

      // Step 2: Add the impact of the new transaction
      if (newIsCredit) {
        // New is Payment OUT (CREDIT) - adds to balance
        adjustedBalance += newAmount;
      } else {
        // New is Payment IN (DEBIT) - subtracts from balance
        adjustedBalance -= newAmount;
      }

      debugPrint('Balance Calculation:');
      debugPrint('Current Closing: $currentClosingBalance');
      debugPrint('Original: ${_originalIsCredit ? "Payment OUT (CREDIT, +)" : "Payment IN (DEBIT, -)"} ₹$_originalAmount');
      debugPrint('New: ${newIsCredit ? "Payment OUT (CREDIT, +)" : "Payment IN (DEBIT, -)"} ₹$newAmount');
      debugPrint('Final Closing: $adjustedBalance');

      // Update ledger document in the batch
      batch.update(ledgerDoc.reference, {
        'closingBalance': adjustedBalance,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating closing balance: $e');
      rethrow;
    }
  }

  /// Show snackbar
  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: const Text(
          'Edit Transaction',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Original Transaction Info
            Container(
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
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Original Transaction',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    // Payment IN = DEBIT (isCredit = false)
                    // Payment OUT = CREDIT (isCredit = true)
                    '${_originalIsCredit ? "Payment Out" : "Payment In"}: ₹${_originalAmount.toStringAsFixed(2)}',
                    style: TextStyle(color: Colors.grey[700], fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Transaction Name
            const Text(
              'Transaction Name',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4285F4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'Enter transaction name',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Amount
            const Text(
              'Amount',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4285F4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Enter amount',
                  prefixText: '₹ ',
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.all(16),
                ),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Payment Type
            const Text(
              'Payment Type',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4285F4),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    // Payment IN = DEBIT (isCredit = false)
                    onTap: () => setState(() => _isCredit = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: !_isCredit ? Colors.green[50] : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !_isCredit
                              ? Colors.green[700]!
                              : Colors.grey[300]!,
                          width: !_isCredit ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.add_circle_outline,
                            color: !_isCredit
                                ? Colors.green[700]
                                : Colors.grey[600],
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Payment In',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: !_isCredit
                                  ? Colors.green[700]
                                  : Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Money received',
                            style: TextStyle(
                              color: !_isCredit
                                  ? Colors.green[600]
                                  : Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    // Payment OUT = CREDIT (isCredit = true)
                    onTap: () => setState(() => _isCredit = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _isCredit ? Colors.red[50] : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isCredit
                              ? Colors.red[700]!
                              : Colors.grey[300]!,
                          width: _isCredit ? 2 : 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.remove_circle_outline,
                            color: _isCredit
                                ? Colors.red[700]
                                : Colors.grey[600],
                            size: 32,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Payment Out',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _isCredit
                                  ? Colors.red[700]
                                  : Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Money paid',
                            style: TextStyle(
                              color: _isCredit
                                  ? Colors.red[600]
                                  : Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Update Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateTransaction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  elevation: 0,
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
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Update Transaction',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
