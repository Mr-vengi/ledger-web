import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as excel_pkg;
import 'package:open_file/open_file.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExportLedgerPage extends StatefulWidget {
  const ExportLedgerPage({super.key});

  @override
  State<ExportLedgerPage> createState() => _ExportLedgerPageState();
}

class _ExportLedgerPageState extends State<ExportLedgerPage> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedFormat = 'PDF';
  bool _isExporting = false;
  String? _selectedShop;
  List<Map<String, dynamic>> _shops = [];
  bool _isLoadingShops = true;
  String _userRole = '';
  String _userShop = '';

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  Future<void> _initializeUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginType = prefs.getString('loginType') ?? 'employee';
      final shopCollection = prefs.getString('shopCollection') ?? '';
      final shopName = prefs.getString('shopName') ?? shopCollection;

      setState(() {
        _userRole = loginType;
        _userShop = shopCollection;
      });

      debugPrint('🔍 USER INIT: Role=$loginType, Shop=$shopCollection');

      if (loginType == 'client') {
        await _loadShops();
      } else {
        setState(() {
          _selectedShop = shopCollection;
          _isLoadingShops = false;
        });
        debugPrint('🔍 EMPLOYEE: Set selected shop to $shopCollection');
      }
    } catch (e) {
      debugPrint('❌ Error initializing user: $e');
      setState(() {
        _userRole = 'employee';
        _userShop = 'vks_retails';
        _selectedShop = 'vks_retails';
        _isLoadingShops = false;
      });
    }
  }

  /// ✅ Load shops from shop_list collection
  Future<void> _loadShops() async {
    try {
      debugPrint('🔍 Loading shops from shop_list collection...');

      final snapshot = await FirebaseFirestore.instance
          .collection('shop_list')
          .get();

      List<Map<String, dynamic>> shopsList = [];

      debugPrint('🔍 Found ${snapshot.docs.length} documents in shop_list');

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final collectionName = data['collectionName'] ?? '';
        final shopName = data['shopName'] ?? 'Unknown Shop';

        debugPrint('🔍 Shop: $shopName → Collection: $collectionName');

        if (collectionName.isNotEmpty) {
          shopsList.add({'id': collectionName, 'name': shopName});
        }
      }

      debugPrint('🔍 Loaded shops: $shopsList');

      setState(() {
        _shops = shopsList;
        _isLoadingShops = false;
        if (_shops.isNotEmpty && _selectedShop == null) {
          _selectedShop = _shops.first['id'];
          debugPrint('🔍 Auto-selected first shop: $_selectedShop');
        }
      });
    } catch (e) {
      debugPrint('❌ Error loading shops from shop_list: $e');

      // ✅ Fallback: manually check for known shops by testing their existence
      List<Map<String, dynamic>> fallbackShops = [];
      List<String> knownShopCollections = [
        'vks_retails',
        'abc_retails',
        'sgk_retails',
      ];

      for (String shopId in knownShopCollections) {
        try {
          final testDoc = await FirebaseFirestore.instance
              .collection(shopId)
              .limit(1)
              .get();

          if (testDoc.docs.isNotEmpty) {
            fallbackShops.add({
              'id': shopId,
              'name': shopId.replaceAll('_', ' ').toUpperCase(),
            });
            debugPrint('🔍 Found existing shop collection: $shopId');
          }
        } catch (e) {
          debugPrint('❌ Shop collection $shopId does not exist');
        }
      }

      setState(() {
        _shops = fallbackShops;
        _isLoadingShops = false;
        if (fallbackShops.isNotEmpty && _selectedShop == null) {
          _selectedShop = fallbackShops.first['id'];
        }
      });
    }
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF4285F4)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = null;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFF4285F4)),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() => _endDate = picked);
    }
  }

  Future<void> _exportData() async {
    if (_selectedShop == null || _selectedShop!.isEmpty) {
      _showSnackBar('Please select a shop', isError: true);
      return;
    }

    if (_startDate == null || _endDate == null) {
      _showSnackBar('Please select both start and end dates', isError: true);
      return;
    }

    setState(() => _isExporting = true);

    try {
      debugPrint('🔍 ================================');
      debugPrint('🔍 EXPORT DEBUG INFO:');
      debugPrint('🔍 Selected Shop: $_selectedShop');
      debugPrint(
        '🔍 Date Range: ${DateFormat('dd-MMM-yyyy').format(_startDate!)} to ${DateFormat('dd-MMM-yyyy').format(_endDate!)}',
      );
      debugPrint('🔍 User Role: $_userRole');
      debugPrint('🔍 ================================');

      List<Map<String, dynamic>> ledgersData = [];

      // ✅ First check if the shop collection exists
      try {
        final shopCollectionTest = await FirebaseFirestore.instance
            .collection(_selectedShop!)
            .limit(1)
            .get();
        debugPrint(
          '🔍 Shop collection $_selectedShop exists: ${shopCollectionTest.docs.isNotEmpty}',
        );
      } catch (e) {
        debugPrint('❌ Error accessing shop collection $_selectedShop: $e');
        _showSnackBar(
          'Shop collection $_selectedShop not found in Firestore',
          isError: true,
        );
        setState(() => _isExporting = false);
        return;
      }

      // ✅ Check if ledgers document exists
      try {
        final ledgersDoc = await FirebaseFirestore.instance
            .collection(_selectedShop!)
            .doc('ledgers')
            .get();
        debugPrint('🔍 Ledgers document exists: ${ledgersDoc.exists}');
      } catch (e) {
        debugPrint('❌ Error accessing ledgers document: $e');
      }

      // ✅ Get all ledger dates from the selected shop collection
      final datesSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShop!)
          .doc('ledgers')
          .collection('dates')
          .get();

      debugPrint(
        '🔍 Found ${datesSnapshot.docs.length} ledger documents in $_selectedShop/ledgers/dates',
      );

      // ✅ List all available dates for debugging
      List<String> availableDates = [];
      for (var doc in datesSnapshot.docs) {
        availableDates.add(doc.id);
      }
      debugPrint('🔍 Available ledger dates: $availableDates');

      for (var dateDoc in datesSnapshot.docs) {
        final ledgerDate = dateDoc.id;

        try {
          final parsedDate = DateFormat('dd-MMM-yyyy').parse(ledgerDate);
          debugPrint('🔍 Checking date: $ledgerDate → $parsedDate');
          debugPrint('🔍 Start: ${_startDate!}, End: ${_endDate!}');

          // Compare dates without time component
          final startDateOnly = DateTime(
            _startDate!.year,
            _startDate!.month,
            _startDate!.day,
          );
          final endDateOnly = DateTime(
            _endDate!.year,
            _endDate!.month,
            _endDate!.day,
          );
          final ledgerDateOnly = DateTime(
            parsedDate.year,
            parsedDate.month,
            parsedDate.day,
          );

          debugPrint('🔍 Date comparison (date only):');
          debugPrint('🔍   Start: $startDateOnly');
          debugPrint('🔍   Ledger: $ledgerDateOnly');
          debugPrint('🔍   End: $endDateOnly');

          // ✅ FIXED: Proper date range check
          if ((ledgerDateOnly.isAtSameMomentAs(startDateOnly) ||
                  ledgerDateOnly.isAfter(startDateOnly)) &&
              (ledgerDateOnly.isAtSameMomentAs(endDateOnly) ||
                  ledgerDateOnly.isBefore(endDateOnly))) {
            debugPrint('✅ INCLUDING ledger date: $ledgerDate');

            final ledgerData = dateDoc.data();
            debugPrint('🔍 Ledger data fields: ${ledgerData.keys.toList()}');

            // ✅ Get transactions for this specific ledger date
            final transactionsSnapshot = await FirebaseFirestore.instance
                .collection(_selectedShop!)
                .doc('ledgers')
                .collection('transactions')
                .where('ledgerDate', isEqualTo: ledgerDate)
                .get();

            List<Map<String, dynamic>> transactions = [];
            for (var transDoc in transactionsSnapshot.docs) {
              transactions.add(transDoc.data());
            }

            debugPrint(
              '🔍 Found ${transactions.length} transactions for $ledgerDate',
            );

            ledgersData.add({
              'ledger': ledgerData,
              'transactions': transactions,
              'ledgerDate': ledgerDate,
            });
          } else {
            debugPrint('❌ EXCLUDING ledger date: $ledgerDate - outside range');
          }
        } catch (e) {
          debugPrint('❌ Error parsing date $ledgerDate: $e');
          continue;
        }
      }

      debugPrint('🔍 Final ledgers to export: ${ledgersData.length}');

      if (ledgersData.isEmpty) {
        String errorMsg = 'No ledgers found in selected date range.\n\n';
        errorMsg += 'Debug info:\n';
        errorMsg += '• Shop: $_selectedShop\n';
        errorMsg += '• Available dates: $availableDates\n';
        errorMsg +=
            '• Selected range: ${DateFormat('dd-MMM-yyyy').format(_startDate!)} to ${DateFormat('dd-MMM-yyyy').format(_endDate!)}\n';
        errorMsg += '• Expected date format: dd-MMM-yyyy (e.g., 10-Nov-2025)';

        debugPrint('❌ $errorMsg');
        _showSnackBar(errorMsg, isError: true);
        setState(() => _isExporting = false);
        return;
      }

      // Sort ledgersData by date
      ledgersData.sort((a, b) {
        final dateA = DateFormat('dd-MMM-yyyy').parse(a['ledgerDate']);
        final dateB = DateFormat('dd-MMM-yyyy').parse(b['ledgerDate']);
        return dateA.compareTo(dateB);
      });

      final shopName = _getShopName();

      debugPrint(
        '✅ Exporting ${ledgersData.length} ledgers for $shopName in $_selectedFormat format',
      );

      if (_selectedFormat == 'PDF') {
        await _exportToPDF(ledgersData, shopName);
      } else {
        await _exportToExcel(ledgersData, shopName);
      }
    } catch (e) {
      debugPrint('❌ Error exporting data: $e');
      _showSnackBar('Failed to export: $e', isError: true);
    } finally {
      setState(() => _isExporting = false);
    }
  }

  String _getShopName() {
    if (_userRole == 'client' && _selectedShop != null) {
      final shop = _shops.firstWhere(
        (s) => s['id'] == _selectedShop,
        orElse: () => {'name': _selectedShop},
      );
      return shop['name'] ?? _selectedShop!;
    }
    return _userShop.replaceAll('_', ' ').toUpperCase();
  }

  /// ✅ Export to PDF with Sales Value in Debit column
  Future<void> _exportToPDF(
    List<Map<String, dynamic>> ledgersData,
    String shopName,
  ) async {
    final pdf = pw.Document();

    for (var data in ledgersData) {
      final ledger = data['ledger'];
      final transactions = (data['transactions'] as List)
          .cast<Map<String, dynamic>>();
      final ledgerDate = data['ledgerDate'];

      final openingBalance = (ledger['openingBalance'] ?? 0).toDouble();
      final closingBalance = (ledger['closingBalance'] ?? 0).toDouble();
      final saleValue = (ledger['saleValue'] ?? 0).toDouble();

      // Create transaction list with opening balance as first row
      final List<Map<String, dynamic>> allTransactions = [
        // Opening balance row (first entry)
        {
          'date': ledgerDate,
          'particulars': 'Opening Balance',
          'description': '',
          'type': '',
          'debit': 0.0,
          'credit': 0.0,
          'closing': openingBalance,
        },
        // Add all actual transactions with running balance
        ...transactions.map((t) {
          final amount = (t['amount'] ?? 0).toDouble();
          final isCredit = t['isCredit'] == true;
          final runningBalance = _calculateRunningBalance(
            transactions,
            t,
            openingBalance,
          );

          return {
            'date': _formatTransactionDate(t, ledgerDate),
            'particulars': _getParticulars(t),
            'description': t['description'] ?? '',
            'type': _getTransactionTypeDisplay(t),
            'debit': !isCredit ? amount : 0.0,
            'credit': isCredit ? amount : 0.0,
            'closing': runningBalance,
          };
        }).toList(),
      ];

      // Calculate totals
      double totalDebit = allTransactions.fold(
        0.0,
        (sum, t) => sum + (t['debit'] as double),
      );
      double totalCredit = allTransactions.fold(
        0.0,
        (sum, t) => sum + (t['credit'] as double),
      );

      // Add grand total row
      allTransactions.add({
        'date': '',
        'particulars': 'GRAND TOTAL',
        'description': '',
        'type': '',
        'debit': totalDebit,
        'credit': totalCredit,
        'closing': closingBalance,
      });

      // ✅ ADD SALES VALUE ROW AFTER GRAND TOTAL
      allTransactions.add({
        'date': '',
        'particulars': 'SALES VALUE',
        'description': 'Total sales for the day',
        'type': '',
        'debit': saleValue, // ✅ Sales value in DEBIT column
        'credit': 0.0,
        'closing': 0.0,
      });

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        shopName.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Ledger Report - Date: $ledgerDate',
                        style: const pw.TextStyle(fontSize: 12),
                      ),
                      pw.Text(
                        'Generated: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}',
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // Transaction Details title
                pw.Text(
                  'Transaction Details',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),

                // Transaction table - ONLY HORIZONTAL LINES
                pw.Table(
                  border: pw.TableBorder(
                    top: pw.BorderSide(color: PdfColors.black, width: 0.8),
                    bottom: pw.BorderSide(color: PdfColors.black, width: 0.8),
                    horizontalInside: pw.BorderSide(
                      color: PdfColors.grey400,
                      width: 0.3,
                    ),
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.0), // Date
                    1: const pw.FlexColumnWidth(2.0), // Particulars
                    2: const pw.FlexColumnWidth(2.0), // Description
                    3: const pw.FlexColumnWidth(1.3), // Type
                    4: const pw.FlexColumnWidth(1.2), // Credit
                    5: const pw.FlexColumnWidth(1.2), // Debit
                    6: const pw.FlexColumnWidth(1.3), // Closing
                  },
                  children: [
                    // Header row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey200,
                      ),
                      children: [
                        _buildPDFCell(
                          'Date',
                          bold: true,
                          align: pw.TextAlign.center,
                        ),
                        _buildPDFCell(
                          'Particulars',
                          bold: true,
                          align: pw.TextAlign.center,
                        ),
                        _buildPDFCell(
                          'Description',
                          bold: true,
                          align: pw.TextAlign.center,
                        ),
                        _buildPDFCell(
                          'Type',
                          bold: true,
                          align: pw.TextAlign.center,
                        ),
                        _buildPDFCell(
                          'Credit (Rs)',
                          bold: true,
                          align: pw.TextAlign.center,
                        ),
                        _buildPDFCell(
                          'Debit (Rs)',
                          bold: true,
                          align: pw.TextAlign.center,
                        ),
                        _buildPDFCell(
                          'Closing (Rs)',
                          bold: true,
                          align: pw.TextAlign.center,
                        ),
                      ],
                    ),

                    // Transaction rows
                    ...allTransactions.map((tx) {
                      final debitAmount = tx['debit'] as double;
                      final creditAmount = tx['credit'] as double;
                      final closingAmount = tx['closing'] as double;
                      final isGrandTotal = tx['particulars'] == 'GRAND TOTAL';
                      final isSalesValue = tx['particulars'] == 'SALES VALUE';
                      final isOpeningBalance =
                          tx['particulars'] == 'Opening Balance';

                      return pw.TableRow(
                        decoration: (isGrandTotal || isSalesValue)
                            ? const pw.BoxDecoration(color: PdfColors.grey100)
                            : null,
                        children: [
                          _buildPDFCell(
                            tx['date'],
                            align: pw.TextAlign.center,
                            bold: isGrandTotal || isSalesValue,
                          ),
                          _buildPDFCell(
                            tx['particulars'],
                            align: pw.TextAlign.left,
                            maxLines: 2,
                            bold:
                                isGrandTotal ||
                                isSalesValue ||
                                isOpeningBalance,
                          ),
                          _buildPDFCell(
                            tx['description'],
                            align: pw.TextAlign.left,
                            maxLines: 2,
                            bold: isGrandTotal || isSalesValue,
                          ),
                          _buildPDFCell(
                            tx['type'],
                            align: pw.TextAlign.center,
                            bold: isGrandTotal || isSalesValue,
                          ),
                          _buildPDFCell(
                            creditAmount > 0
                                ? 'Rs ${NumberFormat('#,##,##0.00').format(creditAmount)}'
                                : '',
                            align: pw.TextAlign.right,
                            bold: isGrandTotal || isSalesValue,
                          ),
                          _buildPDFCell(
                            debitAmount > 0
                                ? 'Rs ${NumberFormat('#,##,##0.00').format(debitAmount)}'
                                : '',
                            align: pw.TextAlign.right,
                            bold: isGrandTotal || isSalesValue,
                          ),
                          _buildPDFCell(
                            isSalesValue
                                ? '' // No closing balance for sales value row
                                : 'Rs ${NumberFormat('#,##,##0.00').format(closingAmount)}',
                            align: pw.TextAlign.right,
                            bold: isGrandTotal || isOpeningBalance,
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),

                pw.Spacer(),

                // Footer
                pw.Container(
                  alignment: pw.Alignment.center,
                  margin: const pw.EdgeInsets.only(top: 15),
                  child: pw.Column(
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(
                            top: pw.BorderSide(color: PdfColors.grey300),
                            bottom: pw.BorderSide(color: PdfColors.grey300),
                          ),
                        ),
                        child: pw.Text(
                          '"Financial stability is the foundation of success. Track every rupee, plan every expense, grow exponentially."',
                          style: pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                            fontStyle: pw.FontStyle.italic,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Powered by Ledger System',
                        style: const pw.TextStyle(
                          fontSize: 9,
                          color: PdfColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    final output = await getExternalStorageDirectory();
    final fileName =
        'ledger_${shopName.toLowerCase().replaceAll(' ', '_')}_${DateFormat('dd-MMM-yyyy').format(_startDate!)}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final filePath = '${output!.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    debugPrint('✅ PDF saved to: $filePath');

    if (mounted) {
      _showSuccessNotification(
        'PDF exported successfully!',
        filePath,
        fileName,
      );
    }
  }

  /// ✅ Export to Excel with Sales Value in Debit column
  Future<void> _exportToExcel(
    List<Map<String, dynamic>> ledgersData,
    String shopName,
  ) async {
    final excel = excel_pkg.Excel.createExcel();
    final sheet = excel['Ledger Report'];

    int row = 0;

    // Header (only once at the top)
    _mergeAndWriteExcel(sheet, row, 0, 6, shopName.toUpperCase());
    _styleExcelHeader(sheet, row, 0);
    row++;

    _mergeAndWriteExcel(
      sheet,
      row,
      0,
      6,
      'Ledger Report - Date Range: ${DateFormat('dd-MMM-yyyy').format(_startDate!)} to ${DateFormat('dd-MMM-yyyy').format(_endDate!)}',
    );
    _styleExcelSubHeader(sheet, row, 0);
    row++;

    _mergeAndWriteExcel(
      sheet,
      row,
      0,
      6,
      'Generated: ${DateFormat('dd-MM-yyyy HH:mm').format(DateTime.now())}',
    );
    _styleExcelSubHeader(sheet, row, 0);
    row += 2;

    for (var data in ledgersData) {
      final ledger = data['ledger'];
      final transactions = (data['transactions'] as List)
          .cast<Map<String, dynamic>>();
      final ledgerDate = data['ledgerDate'];

      final openingBalance = (ledger['openingBalance'] ?? 0).toDouble();
      final closingBalance = (ledger['closingBalance'] ?? 0).toDouble();
      final saleValue = (ledger['saleValue'] ?? 0).toDouble();

      // Create transaction list with opening balance as first row
      final List<Map<String, dynamic>> allTransactions = [
        // Opening balance row
        {
          'date': ledgerDate,
          'particulars': 'Opening Balance',
          'description': '',
          'type': '',
          'debit': 0.0,
          'credit': 0.0,
          'closing': openingBalance,
        },
        // Add all actual transactions with running balance
        ...transactions.map((t) {
          final amount = (t['amount'] ?? 0).toDouble();
          final isCredit = t['isCredit'] == true;
          final runningBalance = _calculateRunningBalance(
            transactions,
            t,
            openingBalance,
          );

          return {
            'date': _formatTransactionDate(t, ledgerDate),
            'particulars': _getParticulars(t),
            'description': t['description'] ?? '',
            'type': _getTransactionTypeDisplay(t),
            'debit': !isCredit ? amount : 0.0,
            'credit': isCredit ? amount : 0.0,
            'closing': runningBalance,
          };
        }).toList(),
      ];

      // Calculate totals
      double totalDebit = allTransactions.fold(
        0.0,
        (sum, t) => sum + (t['debit'] as double),
      );
      double totalCredit = allTransactions.fold(
        0.0,
        (sum, t) => sum + (t['credit'] as double),
      );

      // Add grand total row
      allTransactions.add({
        'date': '',
        'particulars': 'GRAND TOTAL',
        'description': '',
        'type': '',
        'debit': totalDebit,
        'credit': totalCredit,
        'closing': closingBalance,
      });

      // ✅ ADD SALES VALUE ROW AFTER GRAND TOTAL
      allTransactions.add({
        'date': '',
        'particulars': 'SALES VALUE',
        'description': 'Total sales for the day',
        'type': '',
        'debit': saleValue, // ✅ Sales value in DEBIT column
        'credit': 0.0,
        'closing': 0.0,
      });

      // Transaction Details title
      _mergeAndWriteExcel(
        sheet,
        row,
        0,
        6,
        'Transaction Details - $ledgerDate',
      );
      _styleExcelTableTitle(sheet, row, 0);
      row += 2;

      // Table header
      _writeExcelCell(sheet, row, 0, 'Date');
      _writeExcelCell(sheet, row, 1, 'Particulars');
      _writeExcelCell(sheet, row, 2, 'Description');
      _writeExcelCell(sheet, row, 3, 'Type');
      _writeExcelCell(sheet, row, 4, 'Credit (Rs)');
      _writeExcelCell(sheet, row, 5, 'Debit (Rs)');
      _writeExcelCell(sheet, row, 6, 'Closing (Rs)');

      for (int col = 0; col <= 6; col++) {
        _styleExcelTableHeader(sheet, row, col);
      }
      row++;

      // Transaction rows
      for (final trans in allTransactions) {
        final debitAmount = trans['debit'] as double;
        final creditAmount = trans['credit'] as double;
        final closingAmount = trans['closing'] as double;
        final isGrandTotal = trans['particulars'] == 'GRAND TOTAL';
        final isSalesValue = trans['particulars'] == 'SALES VALUE';
        final isOpeningBalance = trans['particulars'] == 'Opening Balance';

        _writeExcelCell(sheet, row, 0, trans['date']);
        _writeExcelCell(sheet, row, 1, trans['particulars']);
        _writeExcelCell(sheet, row, 2, trans['description']);
        _writeExcelCell(sheet, row, 3, trans['type']);
        _writeExcelCell(
          sheet,
          row,
          4,
          creditAmount > 0
              ? 'Rs ${NumberFormat('#,##,##0.00').format(creditAmount)}'
              : '',
        );
        _writeExcelCell(
          sheet,
          row,
          5,
          debitAmount > 0
              ? 'Rs ${NumberFormat('#,##,##0.00').format(debitAmount)}'
              : '',
        );
        _writeExcelCell(
          sheet,
          row,
          6,
          isSalesValue
              ? '' // No closing balance for sales value row
              : 'Rs ${NumberFormat('#,##,##0.00').format(closingAmount)}',
        );

        // Style cells
        _styleExcelCell(
          sheet,
          row,
          0,
          isCenter: true,
          isBold: isGrandTotal || isSalesValue,
        );
        _styleExcelCell(
          sheet,
          row,
          1,
          isLeft: true,
          isBold: isGrandTotal || isSalesValue || isOpeningBalance,
        );
        _styleExcelCell(
          sheet,
          row,
          2,
          isLeft: true,
          isBold: isGrandTotal || isSalesValue,
        );
        _styleExcelCell(
          sheet,
          row,
          3,
          isCenter: true,
          isBold: isGrandTotal || isSalesValue,
        );
        _styleExcelCell(
          sheet,
          row,
          4,
          isRight: true,
          isBold: isGrandTotal || isSalesValue,
        );
        _styleExcelCell(
          sheet,
          row,
          5,
          isRight: true,
          isBold: isGrandTotal || isSalesValue,
        );
        _styleExcelCell(
          sheet,
          row,
          6,
          isRight: true,
          isBold: isGrandTotal || isOpeningBalance,
        );

        row++;
      }

      row += 2;
    }

    // Quote & Footer
    _mergeAndWriteExcel(
      sheet,
      row,
      0,
      6,
      '"Financial stability is the foundation of success. Track every rupee, plan every expense, grow exponentially."',
    );
    _styleExcelQuote(sheet, row, 0);
    row++;

    _mergeAndWriteExcel(sheet, row, 0, 6, 'Powered by Ledger System');
    _styleExcelFooter(sheet, row, 0);

    // Column widths
    sheet.setColumnWidth(0, 12); // Date
    sheet.setColumnWidth(1, 25); // Particulars
    sheet.setColumnWidth(2, 25); // Description
    sheet.setColumnWidth(3, 15); // Type
    sheet.setColumnWidth(4, 18); // Credit
    sheet.setColumnWidth(5, 18); // Debit
    sheet.setColumnWidth(6, 18); // Closing

    final output = await getExternalStorageDirectory();
    final fileName =
        'ledger_${shopName.toLowerCase().replaceAll(' ', '_')}_${DateFormat('dd-MMM-yyyy').format(_startDate!)}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    final filePath = '${output!.path}/$fileName';
    final fileBytes = excel.encode();
    final file = File(filePath);
    await file.writeAsBytes(fileBytes!);

    debugPrint('✅ Excel saved to: $filePath');

    if (mounted) {
      _showSuccessNotification(
        'Excel exported successfully!',
        filePath,
        fileName,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPER FUNCTIONS FOR NEW FORMAT
  // ═══════════════════════════════════════════════════════════════════════

  /// Calculate running balance for each transaction
  double _calculateRunningBalance(
    List<Map<String, dynamic>> transactions,
    Map<String, dynamic> currentTransaction,
    double openingBalance,
  ) {
    double runningBalance = openingBalance;
    final currentIndex = transactions.indexOf(currentTransaction);

    for (int i = 0; i <= currentIndex; i++) {
      final t = transactions[i];
      final amount = (t['amount'] ?? 0).toDouble();
      final isCredit = t['isCredit'] == true;

      // Payment IN = DEBIT (isCredit = false) → money coming in → increases balance
      // Payment OUT = CREDIT (isCredit = true) → money going out → decreases balance
      if (isCredit) {
        runningBalance -= amount; // Payment OUT (CREDIT) decreases balance
      } else {
        runningBalance += amount; // Payment IN (DEBIT) increases balance
      }
    }

    return runningBalance;
  }

  /// Get particulars (customer name or ledger name)
  String _getParticulars(Map<String, dynamic> transaction) {
    final customerName = transaction['customerName']?.toString() ?? '';
    final ledgerName = transaction['ledgerName']?.toString() ?? '';

    if (customerName.isNotEmpty) return customerName;
    if (ledgerName.isNotEmpty) return ledgerName;
    return 'Transaction';
  }

  /// Get transaction type display - Payment In/Payment Out
  String _getTransactionTypeDisplay(Map<String, dynamic> transaction) {
    final isCredit = transaction['isCredit'] == true;
    // Payment IN = DEBIT (isCredit = false) → "Payment In"
    // Payment OUT = CREDIT (isCredit = true) → "Payment Out"
    return isCredit ? 'Payment Out' : 'Payment In';
  }

  /// Format transaction date
  String _formatTransactionDate(
    Map<String, dynamic> transaction,
    String fallbackDate,
  ) {
    final dateStr =
        transaction['transactionDate'] ?? transaction['date'] ?? fallbackDate;
    if (dateStr.isNotEmpty) {
      try {
        final date = DateFormat('dd-MMM-yyyy').parse(dateStr);
        return DateFormat('dd-MM-yyyy').format(date);
      } catch (e) {
        return dateStr;
      }
    }
    return DateFormat('dd-MM-yyyy').format(DateTime.now());
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PDF HELPER FUNCTIONS
  // ═══════════════════════════════════════════════════════════════════════

  pw.Widget _buildPDFCell(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    int maxLines = 1,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: align,
        maxLines: maxLines,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // EXCEL HELPER FUNCTIONS
  // ═══════════════════════════════════════════════════════════════════════

  void _mergeAndWriteExcel(
    excel_pkg.Sheet sheet,
    int row,
    int colStart,
    int colEnd,
    String text,
  ) {
    if (colStart != colEnd) {
      sheet.merge(
        excel_pkg.CellIndex.indexByColumnRow(
          columnIndex: colStart,
          rowIndex: row,
        ),
        excel_pkg.CellIndex.indexByColumnRow(
          columnIndex: colEnd,
          rowIndex: row,
        ),
      );
    }
    _writeExcelCell(sheet, row, colStart, text);
  }

  void _writeExcelCell(excel_pkg.Sheet sheet, int row, int col, String text) {
    sheet
        .cell(
          excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        )
        .value = excel_pkg.TextCellValue(
      text,
    );
  }

  void _styleExcelHeader(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: excel_pkg.HorizontalAlign.Center,
    );
  }

  void _styleExcelSubHeader(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      fontSize: 12,
      horizontalAlign: excel_pkg.HorizontalAlign.Center,
    );
  }

  void _styleExcelTableTitle(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      bold: true,
      fontSize: 12,
      horizontalAlign: excel_pkg.HorizontalAlign.Left,
    );
  }

  void _styleExcelTableHeader(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      bold: true,
      fontSize: 11,
      horizontalAlign: excel_pkg.HorizontalAlign.Center,
    );
  }

  void _styleExcelCell(
    excel_pkg.Sheet sheet,
    int row,
    int col, {
    bool isLeft = false,
    bool isCenter = false,
    bool isRight = false,
    bool isBold = false,
  }) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );

    excel_pkg.HorizontalAlign alignment = excel_pkg.HorizontalAlign.Left;
    if (isCenter) alignment = excel_pkg.HorizontalAlign.Center;
    if (isRight) alignment = excel_pkg.HorizontalAlign.Right;

    cell.cellStyle = excel_pkg.CellStyle(
      fontSize: 10,
      horizontalAlign: alignment,
      bold: isBold,
    );
  }

  void _styleExcelQuote(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      italic: true,
      fontSize: 10,
      horizontalAlign: excel_pkg.HorizontalAlign.Center,
    );
  }

  void _styleExcelFooter(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      fontSize: 9,
      horizontalAlign: excel_pkg.HorizontalAlign.Center,
    );
  }

  void _showSuccessNotification(
    String message,
    String filePath,
    String fileName,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('File: $fileName', style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: Colors.green[600],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'OPEN',
          textColor: Colors.white,
          onPressed: () => OpenFile.open(filePath),
        ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 5),
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
          'Export Ledger',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: _isLoadingShops
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF4285F4)),
                  SizedBox(height: 16),
                  Text('Loading shops...'),
                ],
              ),
            )
          : ListView(
              children: [
                // ✅ Shop Selection with improved dropdown design
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Shop',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_userRole == 'client')
                        _shops.isEmpty
                            ? Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  border: Border.all(color: Colors.red[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'No shops found',
                                      style: TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Please check shop_list collection in Firestore',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _selectedShop,
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
                                          'Choose shop to export',
                                          style: TextStyle(
                                            fontSize: 15,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  items: _shops
                                      .map(
                                        (shop) => DropdownMenuItem<String>(
                                          value: shop['id'],
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.store,
                                                  color: Color(0xFF4285F4),
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  shop['name'],
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() => _selectedShop = value);
                                    debugPrint('🔍 Selected shop: $value');
                                  },
                                ),
                              )
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            border: Border.all(color: Colors.blue[200]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.store,
                                color: Colors.blue[700],
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _userShop.replaceAll('_', ' ').toUpperCase(),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.blue[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Start Date
                ListTile(
                  leading: const Icon(
                    Icons.calendar_today,
                    color: Colors.black54,
                  ),
                  title: const Text(
                    'Start Date',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    _startDate != null
                        ? DateFormat('dd MMM yyyy').format(_startDate!)
                        : 'Select start date',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  onTap: _selectStartDate,
                ),
                const Divider(height: 1),

                // End Date
                ListTile(
                  leading: const Icon(Icons.event, color: Colors.black54),
                  title: const Text(
                    'End Date',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    _endDate != null
                        ? DateFormat('dd MMM yyyy').format(_endDate!)
                        : 'Select end date',
                    style: const TextStyle(color: Colors.black54),
                  ),
                  onTap: _selectEndDate,
                ),
                const Divider(height: 1),

                // Format Selection
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    'Export Format',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),

                RadioListTile<String>(
                  value: 'PDF',
                  groupValue: _selectedFormat,
                  onChanged: (value) {
                    setState(() => _selectedFormat = value!);
                  },
                  activeColor: const Color(0xFF4285F4),
                  title: const Text('PDF'),
                  subtitle: const Text('Best for printing and sharing'),
                  secondary: Icon(
                    Icons.picture_as_pdf,
                    color: _selectedFormat == 'PDF'
                        ? Colors.red[700]
                        : Colors.grey[400],
                  ),
                ),

                RadioListTile<String>(
                  value: 'Excel',
                  groupValue: _selectedFormat,
                  onChanged: (value) {
                    setState(() => _selectedFormat = value!);
                  },
                  activeColor: const Color(0xFF4285F4),
                  title: const Text('Excel'),
                  subtitle: const Text('Best for data analysis'),
                  secondary: Icon(
                    Icons.table_chart,
                    color: _selectedFormat == 'Excel'
                        ? Colors.green[700]
                        : Colors.grey[400],
                  ),
                ),

                const Divider(height: 1),

                // Export Button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: _isExporting ? null : _exportData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isExporting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Exporting...'),
                            ],
                          )
                        : const Text(
                            'Export Ledger',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
    );
  }
}
