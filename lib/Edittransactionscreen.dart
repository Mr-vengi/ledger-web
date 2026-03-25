import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class EditTransactionScreen extends StatefulWidget {
  final DocumentSnapshot transactionDoc;
  final DateTime ledgerDate;

  const EditTransactionScreen({
    super.key,
    required this.transactionDoc,
    required this.ledgerDate,
  });

  @override
  State<EditTransactionScreen> createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _descriptionController;
  late TextEditingController _detailsController;
  late TextEditingController _ledgerController;
  late TextEditingController _customLedgerController;

  bool _isLoading = false;
  String? _selectedLedger;
  bool _showCustomLedgerField = false;

  // Transaction data
  late String _transactionType;
  late bool _isCredit;
  late String _customerName;

  // Predefined ledger options
  final List<String> _predefinedLedgers = [
    'Cash Ledger',
    'Tea Expense',
    'Petrol Expense',
    'Office Supplies',
    'Travel Expense',
    'Phone Bill',
    'Electricity Bill',
    'Custom (Enter your own)',
  ];

  /// 🔹 Check if device is in landscape mode
  bool _isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    final data = widget.transactionDoc.data() as Map<String, dynamic>;

    _amountController = TextEditingController(
      text: (data['amount'] ?? 0).toString(),
    );
    _descriptionController = TextEditingController(
      text: data['description']?.toString() ?? '',
    );
    _detailsController = TextEditingController(
      text: data['transactionDetails']?.toString() ?? '',
    );
    _ledgerController = TextEditingController(
      text: data['ledgerName']?.toString() ?? '',
    );
    _customLedgerController = TextEditingController();

    _transactionType = data['transactionType']?.toString() ?? '';
    _isCredit = data['isCredit'] as bool? ?? false;
    _customerName = data['customerName']?.toString() ?? '';

    // Set selected ledger for General transactions
    if (_transactionType == 'General') {
      final currentLedger = data['ledgerName']?.toString() ?? '';
      if (_predefinedLedgers.contains(currentLedger)) {
        _selectedLedger = currentLedger;
      } else if (currentLedger.isNotEmpty) {
        _selectedLedger = 'Custom (Enter your own)';
        _showCustomLedgerField = true;
        _customLedgerController.text = currentLedger;
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _detailsController.dispose();
    _ledgerController.dispose();
    _customLedgerController.dispose();
    super.dispose();
  }

  /// 🔹 Get appropriate icon for ledger type
  IconData _getLedgerIcon(String ledger) {
    switch (ledger) {
      case 'Cash Ledger':
        return Icons.money;
      case 'Tea Expense':
        return Icons.local_cafe;
      case 'Petrol Expense':
        return Icons.local_gas_station;
      case 'Office Supplies':
        return Icons.business_center;
      case 'Travel Expense':
        return Icons.directions_car;
      case 'Phone Bill':
        return Icons.phone;
      case 'Electricity Bill':
        return Icons.electric_bolt;
      default:
        return Icons.receipt;
    }
  }

  /// 🔹 Build modern text field
  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    required bool isLandscape,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isLandscape ? 13 : 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: isLandscape ? 6 : 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: TextStyle(
            fontSize: isLandscape ? 14 : 15,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
              borderSide: const BorderSide(color: Color(0xFF4285F4), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
              borderSide: const BorderSide(color: Colors.red, width: 1),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 14 : 16,
              vertical: isLandscape ? 12 : 14,
            ),
            hintStyle: TextStyle(
              color: Colors.grey[500],
              fontSize: isLandscape ? 14 : 15,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  /// 🔹 Build ledger dropdown for General transactions
  Widget _buildLedgerDropdown(bool isLandscape) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ledger Name',
          style: TextStyle(
            fontSize: isLandscape ? 13 : 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: isLandscape ? 6 : 8),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 14 : 16,
            vertical: isLandscape ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedLedger,
              isExpanded: true,
              hint: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    color: Colors.grey[500],
                    size: isLandscape ? 18 : 20,
                  ),
                  SizedBox(width: isLandscape ? 8 : 10),
                  Text(
                    'Choose ledger type',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: isLandscape ? 14 : 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              icon: Icon(
                Icons.keyboard_arrow_down,
                color: Colors.grey[600],
                size: isLandscape ? 20 : 24,
              ),
              items: _predefinedLedgers.map((String ledger) {
                return DropdownMenuItem<String>(
                  value: ledger,
                  child: Row(
                    children: [
                      if (ledger == 'Custom (Enter your own)') ...[
                        Icon(
                          Icons.edit,
                          color: const Color(0xFF4285F4),
                          size: isLandscape ? 16 : 18,
                        ),
                        SizedBox(width: isLandscape ? 6 : 8),
                      ] else ...[
                        Icon(
                          _getLedgerIcon(ledger),
                          color: Colors.grey[600],
                          size: isLandscape ? 16 : 18,
                        ),
                        SizedBox(width: isLandscape ? 6 : 8),
                      ],
                      Text(
                        ledger,
                        style: TextStyle(
                          fontSize: isLandscape ? 13 : 14,
                          fontWeight: FontWeight.w500,
                          color: ledger == 'Custom (Enter your own)'
                              ? const Color(0xFF4285F4)
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedLedger = value;
                  if (value == 'Custom (Enter your own)') {
                    _showCustomLedgerField = true;
                  } else {
                    _showCustomLedgerField = false;
                    _ledgerController.text = value ?? '';
                  }
                });
              },
            ),
          ),
        ),
        // Show custom ledger field if selected
        if (_showCustomLedgerField) ...[
          SizedBox(height: isLandscape ? 12 : 16),
          _buildTextField(
            label: 'Enter Custom Ledger Name',
            controller: _customLedgerController,
            validator: (v) =>
                v!.trim().isEmpty ? 'Custom ledger name is required' : null,
            isLandscape: isLandscape,
          ),
        ],
      ],
    );
  }

  /// 🔹 Update transaction in Firestore
  Future<void> _updateTransaction() async {
    if (!_formKey.currentState!.validate()) return;

    // Additional validation for General transactions
    if (_transactionType == 'General') {
      if (_selectedLedger == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select a ledger type'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (_showCustomLedgerField &&
          _customLedgerController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter custom ledger name'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final amount = double.parse(_amountController.text.replaceAll(',', ''));

      final updateData = <String, dynamic>{
        'amount': amount,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_transactionType == 'General') {
        final finalLedgerName = _showCustomLedgerField
            ? _customLedgerController.text.trim()
            : _selectedLedger!;

        updateData['transactionDetails'] = _detailsController.text.trim();
        updateData['ledgerName'] = finalLedgerName;
        updateData['description'] = _detailsController.text.trim();
      } else {
        updateData['description'] = _descriptionController.text.trim();
      }

      await widget.transactionDoc.reference.update(updateData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      debugPrint('Error updating transaction: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating transaction: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = _isLandscape(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: Text(
          'Edit Transaction',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isLandscape ? 20 : 22,
          ),
        ),
        actions: [
          // Save icon button in app bar
          IconButton(
            icon: _isLoading
                ? SizedBox(
                    width: isLandscape ? 20 : 24,
                    height: isLandscape ? 20 : 24,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(Icons.save, size: isLandscape ? 24 : 26),
            onPressed: _isLoading ? null : _updateTransaction,
            tooltip: 'Save Changes',
          ),
          SizedBox(width: isLandscape ? 8 : 12),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            color: Colors.white,
            child: Padding(
              padding: EdgeInsets.all(isLandscape ? 16 : 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Transaction Info Banner
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isLandscape ? 12 : 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4285F4).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(
                          isLandscape ? 10 : 12,
                        ),
                        border: Border.all(
                          color: const Color(0xFF4285F4).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _transactionType == 'Customer'
                                ? Icons.person
                                : Icons.receipt,
                            color: const Color(0xFF4285F4),
                            size: isLandscape ? 18 : 20,
                          ),
                          SizedBox(width: isLandscape ? 8 : 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$_transactionType Transaction',
                                  style: TextStyle(
                                    fontSize: isLandscape ? 14 : 15,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF4285F4),
                                  ),
                                ),
                                if (_customerName.isNotEmpty) ...[
                                  SizedBox(height: isLandscape ? 2 : 4),
                                  Text(
                                    'Customer: $_customerName',
                                    style: TextStyle(
                                      fontSize: isLandscape ? 12 : 13,
                                      color: const Color(0xFF4285F4),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isLandscape ? 8 : 10,
                              vertical: isLandscape ? 4 : 6,
                            ),
                            decoration: BoxDecoration(
                              color: _isCredit
                                  ? Colors.green[100]
                                  : Colors.red[100],
                              borderRadius: BorderRadius.circular(
                                isLandscape ? 6 : 8,
                              ),
                            ),
                            child: Text(
                              _isCredit ? 'Payment In' : 'Payment Out',
                              style: TextStyle(
                                fontSize: isLandscape ? 11 : 12,
                                fontWeight: FontWeight.w600,
                                color: _isCredit
                                    ? Colors.green[700]
                                    : Colors.red[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isLandscape ? 24 : 32),

                    // Transaction Date Info
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isLandscape ? 10 : 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(
                          isLandscape ? 8 : 10,
                        ),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: Colors.grey[600],
                            size: isLandscape ? 16 : 18,
                          ),
                          SizedBox(width: isLandscape ? 8 : 10),
                          Text(
                            'Transaction Date: ${DateFormat('dd-MMM-yyyy').format(widget.ledgerDate)}',
                            style: TextStyle(
                              fontSize: isLandscape ? 13 : 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: isLandscape ? 18 : 24),

                    // Amount Field
                    _buildTextField(
                      label: 'Amount',
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final numeric = v!.replaceAll(',', '').trim();
                        final parsed = double.tryParse(numeric);
                        if (parsed == null || parsed <= 0) {
                          return 'Enter a valid amount';
                        }
                        return null;
                      },
                      isLandscape: isLandscape,
                    ),
                    SizedBox(height: isLandscape ? 18 : 24),

                    // Conditional fields based on transaction type
                    if (_transactionType == 'Customer') ...[
                      _buildTextField(
                        label: 'Ledger Name / Description',
                        controller: _descriptionController,
                        validator: (v) => v!.trim().isEmpty
                            ? 'Description is required'
                            : null,
                        isLandscape: isLandscape,
                      ),
                    ] else if (_transactionType == 'General') ...[
                      _buildTextField(
                        label: 'Transaction Details',
                        controller: _detailsController,
                        validator: (v) => v!.trim().isEmpty
                            ? 'Transaction details are required'
                            : null,
                        isLandscape: isLandscape,
                      ),
                      SizedBox(height: isLandscape ? 18 : 24),
                      _buildLedgerDropdown(isLandscape),
                    ] else ...[
                      // Fallback for unknown transaction types
                      _buildTextField(
                        label: 'Description',
                        controller: _descriptionController,
                        validator: (v) => v!.trim().isEmpty
                            ? 'Description is required'
                            : null,
                        isLandscape: isLandscape,
                      ),
                    ],

                    // Bottom padding for comfortable scrolling
                    SizedBox(height: isLandscape ? 32 : 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
