import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CreateLedgerScreen extends StatefulWidget {
  const CreateLedgerScreen({super.key});

  @override
  State<CreateLedgerScreen> createState() => _CreateLedgerScreenState();
}

class _CreateLedgerScreenState extends State<CreateLedgerScreen> {
  DateTime _selectedDate = DateTime.now();
  final List<int> denominations = [1, 10, 20, 50, 100, 500];
  late List<TextEditingController> _controllers;
  late List<int> _totals;
  final TextEditingController _noteController = TextEditingController();

  bool _isSaving = false;
  bool _isLoading = true;

  // Shop related
  List<Map<String, dynamic>> _shops = [];
  String? _selectedShopCollection;
  String? _selectedShopName;

  // User role
  String? _userRole;
  String? _userShop;
  String? _employeeShopCollection;

  // Previous ledger info
  int _previousClosing = 0;
  String _previousDate = "—";
  Map<String, dynamic>? _previousDenominations;
  bool _isPrefilled = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      denominations.length,
      (_) => TextEditingController(),
    );
    _totals = List.generate(denominations.length, (_) => 0);

    for (int i = 0; i < _controllers.length; i++) {
      _controllers[i].addListener(() {
        _updateTotal(i);
      });
    }

    _initializeScreen();
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    _noteController.dispose();
    super.dispose();
  }

  // ==================== CALCULATIONS ====================

  void _updateTotal(int index) {
    int count = int.tryParse(_controllers[index].text) ?? 0;
    setState(() {
      _totals[index] = count * denominations[index];
    });
  }

  int get _grandTotal => _totals.fold(0, (sum, item) => sum + item);

  int get _totalNotes =>
      _controllers.fold(0, (sum, c) => sum + (int.tryParse(c.text) ?? 0));

  // ==================== FIRESTORE OPERATIONS ====================

  Future<void> _initializeScreen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginType = prefs.getString('loginType');
      final shopName = prefs.getString('shopName');
      final shopCollection = prefs.getString('shopCollection');

      setState(() {
        _userRole = loginType;
        _userShop = shopName;
        _employeeShopCollection = shopCollection;
      });

      if (loginType == 'client') {
        await _fetchAllShops();
      } else if (loginType == 'employee') {
        await _loadPreviousLedgerData();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error initializing: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchAllShops() async {
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
      });
    } catch (e) {
      debugPrint('Error fetching shops: $e');
      _showSnackBar('Error loading shops', isError: true);
    }
  }

  Future<void> _loadPreviousLedgerData() async {
    try {
      final collection = _selectedShopCollection ?? _employeeShopCollection;

      if (collection == null || collection.isEmpty) return;

      // Get ledgers collection and find the latest document
      final snap = await FirebaseFirestore.instance
          .collection(collection)
          .doc('ledgers')
          .collection('dates')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        final data = snap.docs.first.data();
        _previousClosing = (data['closingBalance'] ?? 0).toInt();
        _previousDate = data['ledgerDate'] ?? "—";
        _previousDenominations = Map<String, dynamic>.from(
          data['denominations'] ?? {},
        );

        if (_previousDenominations != null &&
            _previousDenominations!.isNotEmpty &&
            !_isPrefilled) {
          for (int i = 0; i < denominations.length; i++) {
            final denomKey = denominations[i].toString();
            if (_previousDenominations!.containsKey(denomKey)) {
              _controllers[i].text = _previousDenominations![denomKey]
                  .toString();
              _updateTotal(i);
            }
          }
          _isPrefilled = true;
        }

        setState(() {});
      }
    } catch (e) {
      debugPrint("Previous ledger fetch error: $e");
    }
  }

  Future<void> _onShopSelected(String? collectionName) async {
    if (collectionName == null || collectionName.isEmpty) return;

    setState(() {
      _selectedShopCollection = collectionName;
      final shop = _shops.firstWhere(
        (s) => s['collectionName'] == collectionName,
        orElse: () => {'shopName': 'Unknown'},
      );
      _selectedShopName = shop['shopName'] as String?;
      _isPrefilled = false;
    });

    await _loadPreviousLedgerData();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4285F4),
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _saveLedger() async {
    // Validation for admin
    if (_userRole == 'client') {
      if (_selectedShopCollection == null || _selectedShopCollection!.isEmpty) {
        _showSnackBar('Please select a shop', isError: true);
        return;
      }
    }

    if (_grandTotal == 0) {
      _showSnackBar('Enter at least one denomination value', isError: true);
      return;
    }

    final selectedDateString = DateFormat('dd-MMM-yyyy').format(_selectedDate);

    setState(() => _isSaving = true);

    try {
      final collection =
          _selectedShopCollection ?? _employeeShopCollection ?? '';

      if (collection.isEmpty) {
        _showSnackBar('Shop collection not found', isError: true);
        setState(() => _isSaving = false);
        return;
      }

      // Check if ledger already exists for selected date
      final existingLedger = await FirebaseFirestore.instance
          .collection(collection)
          .doc('ledgers')
          .collection('dates')
          .doc(selectedDateString)
          .get();

      if (existingLedger.exists) {
        _showSnackBar('Ledger for $selectedDateString already exists', isError: true);
        setState(() => _isSaving = false);
        return;
      }

      // Prepare denomination map
      Map<String, int> denominationMap = {};
      for (int i = 0; i < denominations.length; i++) {
        int count = int.tryParse(_controllers[i].text) ?? 0;
        denominationMap[denominations[i].toString()] = count;
      }

      // Opening balance = Grand total from denominations
      int openingBalance = _grandTotal;

      final ledgerData = {
        'ledgerDate': selectedDateString,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _userRole == 'client' ? 'Admin' : 'Employee',
        'openingBalance': openingBalance,
        'closingBalance': openingBalance,
        'denominations': denominationMap,
        'totals': _totals,
        'note': _noteController.text.trim(),
        'status': 'Open',
      };

      // Save to Firestore: shop_collection/ledgers/dates/{date}
      await FirebaseFirestore.instance
          .collection(collection)
          .doc('ledgers')
          .collection('dates')
          .doc(selectedDateString)
          .set(ledgerData);

      if (mounted) {
        setState(() => _isSaving = false);
        _showSuccessDialog(selectedDateString);
      }
    } catch (e) {
      _showSnackBar('Error saving ledger: $e', isError: true);
      setState(() => _isSaving = false);
    }
  }

  // ==================== UI DIALOGS ====================

  void _showSuccessDialog(String ledgerDate) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle,
                    size: 60,
                    color: Colors.green[600],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Ledger Created!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Ledger created successfully for $ledgerDate',
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
                      elevation: 0,
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF4285F4),
          foregroundColor: Colors.white,
          title: const Text('Create Ledger'),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF4285F4)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create Ledger',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 2),
            Text(
              _userRole == 'client'
                  ? 'Admin - ${_selectedShopName ?? 'Select Shop'}'
                  : 'Employee - $_userShop',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Previous Ledger Info
            if (_previousDate != "—")
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
                        Icons.history,
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
                            'Previous Ledger',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _previousDate,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Closing: ₹${NumberFormat('#,##,##0').format(_previousClosing)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date Selection (for both admin and employee)
                  const SizedBox(height: 16),
                  const Text(
                    'Select Date *',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4285F4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _selectDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF4285F4),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            color: const Color(0xFF4285F4),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            DateFormat('dd-MMM-yyyy').format(_selectedDate),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_drop_down,
                            color: Colors.grey[600],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Admin: Shop Selection
                  if (_userRole == 'client') ...[
                    const Text(
                      'Select Shop *',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4285F4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedShopCollection != null
                              ? const Color(0xFF4285F4)
                              : Colors.grey[300]!,
                          width: 1.5,
                        ),
                      ),
                      child: DropdownButton<String>(
                        value: _selectedShopCollection,
                        isExpanded: true,
                        underline: const SizedBox(),
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: Colors.grey[600],
                        ),
                        hint: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.store,
                                color: Colors.grey[600],
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Choose your shop',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        items: _shops.map((shop) {
                          return DropdownMenuItem<String>(
                            value: shop['collectionName'],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.store,
                                    color: const Color(0xFF4285F4),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    shop['shopName'],
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: _onShopSelected,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Employee: Opening Balance Display
                  if (_userRole == 'employee') ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.account_balance_wallet,
                                color: Colors.blue[700],
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Opening Balance',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.blue[900],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '₹${NumberFormat('#,##,##0').format(_previousClosing)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Denomination Section
                  const Text(
                    'Denomination Count',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _userRole == 'client'
                        ? 'Enter denomination counts'
                        : 'Record denomination counts',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 12),

                  // Denomination Inputs
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
                                colors: [Colors.blue[400]!, Colors.blue[600]!],
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
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: TextField(
                              controller: _controllers[i],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                hintText: '0',
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                border: InputBorder.none,
                              ),
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
                            '₹${NumberFormat('#,##,##0').format(_totals[i])}',
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

                  const SizedBox(height: 16),

                  // Total Summary Card
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

                  const SizedBox(height: 24),

                  // Note Section
                  const Text(
                    'Note (Optional)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _noteController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Add any additional notes...',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
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
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
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
                  onPressed: _isSaving ? null : _saveLedger,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check_circle, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              _userRole == 'client'
                                  ? 'Create Ledger'
                                  : 'Create Ledger',
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