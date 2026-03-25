import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'font_loader.dart';

class PDFExportService {
  /// Get Tamil font - uses TamilFontLoader if available, otherwise null
  /// Ensures Tamil fonts are properly loaded before use
  static pw.Font? _getTamilFont({bool bold = false}) {
    try {
      // Verify fonts are initialized
      if (TamilFontLoader.tamilRegular == null) {
        debugPrint('Error: Tamil regular font is null');
        return null;
      }
      
      if (bold) {
        if (TamilFontLoader.tamilBold != null) {
          return TamilFontLoader.tamilBold;
        }
        // Fallback to regular if bold not available
        debugPrint('Warning: Tamil bold font not available, using regular');
        return TamilFontLoader.tamilRegular;
      } else {
        return TamilFontLoader.tamilRegular;
      }
    } catch (e) {
      debugPrint('Error getting Tamil font: $e');
      return null;
    }
  }

  /// Generate PDF - PRIMARY: Uses cloud function, FALLBACK: Local generation
  /// Cloud function (index.js) is the primary method for PDF generation
  /// Local generation (this method) is used as backup if cloud function fails
  static Future<Uint8List> generateLedgerPDF({
    required DateTime date,
    required String shopName,
    required double openingBalance,
    required double closingBalance,
    required double saleValue,
    required double cashOut,
    required List<Map<String, dynamic>> transactions,
    required bool isLedgerClosed,
  }) async {
    // ✅ PRIMARY: Try cloud function first
    try {
      debugPrint('🔄 Attempting to generate PDF via cloud function...');
      final pdfBytes = await _generatePDFViaCloudFunction(
        date: date,
        shopName: shopName,
        openingBalance: openingBalance,
        closingBalance: closingBalance,
        saleValue: saleValue,
        cashOut: cashOut,
        transactions: transactions,
        isLedgerClosed: isLedgerClosed,
      );
      debugPrint('✅ PDF generated successfully via cloud function');
      return pdfBytes;
    } catch (e) {
      debugPrint('⚠️ Cloud function failed, falling back to local generation: $e');
      // ✅ FALLBACK: Use local generation if cloud function fails
      return _generatePDFLocally(
        date: date,
        shopName: shopName,
        openingBalance: openingBalance,
        closingBalance: closingBalance,
        saleValue: saleValue,
        cashOut: cashOut,
        transactions: transactions,
        isLedgerClosed: isLedgerClosed,
      );
    }
  }

  /// ✅ PRIMARY METHOD: Generate PDF via cloud function
  static Future<Uint8List> _generatePDFViaCloudFunction({
    required DateTime date,
    required String shopName,
    required double openingBalance,
    required double closingBalance,
    required double saleValue,
    required double cashOut,
    required List<Map<String, dynamic>> transactions,
    required bool isLedgerClosed,
  }) async {
    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('generateLedgerPDF');

      // Prepare transaction data for cloud function
      // Convert Timestamp objects to maps for JSON serialization
      final transactionsData = transactions.map((t) {
        final Map<String, dynamic> tx = Map<String, dynamic>.from(t);
        
        // Convert Timestamp to map format for cloud function
        if (tx['createdAt'] != null) {
          final ts = tx['createdAt'];
          if (ts is Timestamp) {
            tx['createdAt'] = {
              '_seconds': ts.seconds,
              '_nanoseconds': ts.nanoseconds,
            };
          }
        }
        
        return tx;
      }).toList();

      // Call cloud function
      final result = await callable.call({
        'date': date.toIso8601String(),
        'shopName': shopName,
        'openingBalance': openingBalance,
        'closingBalance': closingBalance,
        'saleValue': saleValue,
        'cashOut': cashOut,
        'transactions': transactionsData,
        'isLedgerClosed': isLedgerClosed,
      });

      // Extract PDF base64 from response
      final responseData = result.data as Map<String, dynamic>;
      if (responseData['success'] == true && responseData['pdfBase64'] != null) {
        final pdfBase64 = responseData['pdfBase64'] as String;
        final pdfBytes = base64Decode(pdfBase64);
        return Uint8List.fromList(pdfBytes);
      } else {
        throw Exception('Cloud function returned error: ${responseData['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      debugPrint('❌ Cloud function error: $e');
      rethrow; // Re-throw to trigger fallback
    }
  }

  /// ✅ FALLBACK METHOD: Generate PDF locally (backup)
  static Future<Uint8List> _generatePDFLocally({
    required DateTime date,
    required String shopName,
    required double openingBalance,
    required double closingBalance,
    required double saleValue,
    required double cashOut,
    required List<Map<String, dynamic>> transactions,
    required bool isLedgerClosed,
  }) async {
    // Verify Tamil fonts are loaded before generating PDF
    if (TamilFontLoader.tamilRegular == null) {
      debugPrint('⚠️ WARNING: Tamil fonts not initialized! PDF may not render Tamil correctly.');
    }
    
    final pdf = pw.Document();
    final ledgerDate = DateFormat('dd-MMM-yyyy').format(date);

    // ✅ If ledger is NOT closed, set closing balance, sales value, and cash out to 0
    final double finalClosingBalance = isLedgerClosed ? closingBalance : 0.0;
    final double finalSaleValue = isLedgerClosed ? saleValue : 0.0;
    final double finalCashOut = isLedgerClosed ? cashOut : 0.0;

    // ✅ Create transaction list with opening balance as first row
    final List<Map<String, dynamic>> allTransactions = [
      // Opening balance row (first entry)
      {
        'date': DateFormat('dd-MM-yyyy').format(date),
        'time': '', // ✅ Add empty time for opening balance
        'particulars': 'Opening Balance',
        'type': '',
        'debit': openingBalance,
        'credit': 0.0,
      },
      // ✅ Add all actual transactions with CORRECT TRANSACTION DATE in chronological order
      ...transactions.map((t) {
        final amount = (t['amount'] ?? 0).toDouble();
        final isCredit = t['isCredit'] == true;
        final time = _getTransactionTime(t); // ✅ Get transaction time

        return {
          'date': _getCorrectTransactionDate(t, ledgerDate),
          'time': time, // ✅ Add time field
          'particulars': _getParticulars(t),
          'type': _getTransactionTypeDisplay(t),
          // Payment IN = DEBIT (isCredit = false) → amount in debit column
          // Payment OUT = CREDIT (isCredit = true) → amount in credit column
          'debit': !isCredit ? amount : 0.0,
          'credit': isCredit ? amount : 0.0,
        };
      }).toList(),
    ];

    // ✅ Calculate totals (including opening balance)
    double totalDebit = allTransactions.fold(
      0.0,
      (sum, t) => sum + (t['debit'] as double),
    );
    double totalCredit = allTransactions.fold(
      0.0,
      (sum, t) => sum + (t['credit'] as double),
    );

    // ✅ CONDITIONAL: Add SALES VALUE ROW only if finalSaleValue > 0
    if (finalSaleValue > 0) {
      allTransactions.add({
        'date': '',
        'time': '', // ✅ Add empty time
        'particulars': 'SALES VALUE',
        'type': '',
        'debit': finalSaleValue,
        'credit': 0.0,
      });

      // ✅ Add SALES VALUE to totals
      totalDebit += finalSaleValue;
    }

    // ✅ CONDITIONAL: Add CASH OUT ROW only if finalCashOut > 0
    if (finalCashOut > 0) {
      allTransactions.add({
        'date': '',
        'time': '', // ✅ Add empty time
        'particulars': 'CASH OUT',
        'type': '',
        'debit': 0.0,
        'credit': finalCashOut,
      });

      // ✅ Add CASH OUT to totals
      totalCredit += finalCashOut;
    }

    // ✅ Add CLOSING BALANCE row (in CREDIT column) - BEFORE GRAND TOTAL
    // Show 0 if ledger not closed, else show actual closing balance
    allTransactions.add({
      'date': '',
      'time': '', // ✅ Add empty time
      'particulars': 'CLOSING BALANCE',
      'type': '',
      'debit': 0.0,
      'credit': finalClosingBalance,
    });

    // ✅ ADD CLOSING BALANCE AND CASH OUT TO TOTAL CREDIT FOR GRAND TOTAL CALCULATION
    double grandTotalCredit = totalCredit + finalClosingBalance;

    // ✅ Add GRAND TOTAL row (AFTER CLOSING BALANCE)
    // Grand Total Debit stays the same
    // Grand Total Credit NOW INCLUDES Closing Balance
    allTransactions.add({
      'date': '',
      'time': '', // ✅ Add empty time
      'particulars': 'GRAND TOTAL',
      'type': '',
      'debit': totalDebit,
      'credit': grandTotalCredit,
    });

    // ✅ FORMULA: Balance Difference = Credit - Debit (per client request)
    // This uses the Grand Total Credit which includes Closing Balance
    double balanceDifference = grandTotalCredit - totalDebit;

    // ✅ Add BALANCE DIFFERENCE row (AFTER GRAND TOTAL, in DEBIT column)
    allTransactions.add({
      'date': '',
      'time': '', // ✅ Add empty time
      'particulars': 'BALANCE DIFFERENCE',
      'type': '',
      'debit': balanceDifference,
      'credit': 0.0,
    });

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header with pure Tamil support
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      shopName.toUpperCase(), // Pure Tamil text - no conversion
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        font: _containsTamilCharacters(shopName) 
                            ? _getTamilFont(bold: true) 
                            : null, // Use Tamil font if contains Tamil
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Ledger Report - Date: $ledgerDate',
                      style: const pw.TextStyle(fontSize: 12),
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

              // ✅ Transaction table
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
                  0: const pw.FlexColumnWidth(
                    1.8,
                  ), // ✅ Increased from 1.2 to fit AM/PM
                  1: const pw.FlexColumnWidth(2.5),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                  4: const pw.FlexColumnWidth(1.5),
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
                    ],
                  ),

                  // Transaction rows
                  ...allTransactions.map((tx) {
                    final debitAmount = tx['debit'] as double;
                    final creditAmount = tx['credit'] as double;
                    final isGrandTotal = tx['particulars'] == 'GRAND TOTAL';
                    final isSalesValue = tx['particulars'] == 'SALES VALUE';
                    final isCashOut = tx['particulars'] == 'CASH OUT';
                    final isOpeningBalance =
                        tx['particulars'] == 'Opening Balance';
                    final isBalanceDifference =
                        tx['particulars'] == 'BALANCE DIFFERENCE';
                    final isClosingBalance =
                        tx['particulars'] == 'CLOSING BALANCE';
                    final particulars = tx['particulars'] as String;
                    final txDate = tx['date'] as String;
                    final time = tx['time'] as String; // ✅ Get time

                    return pw.TableRow(
                      decoration:
                          (isGrandTotal ||
                              isSalesValue ||
                              isCashOut ||
                              isOpeningBalance ||
                              isBalanceDifference ||
                              isClosingBalance)
                          ? const pw.BoxDecoration(color: PdfColors.grey100)
                          : null,
                      children: [
                        // ✅ DATE COLUMN WITH TIME ON SAME LINE (with AM/PM)
                        pw.Container(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            time.isNotEmpty ? '${txDate} | $time' : txDate,
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight:
                                  (isGrandTotal ||
                                      isSalesValue ||
                                      isCashOut ||
                                      isBalanceDifference ||
                                      isClosingBalance)
                                  ? pw.FontWeight.bold
                                  : pw.FontWeight.normal,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        _buildPDFCellWithTamil(
                          particulars,
                          align: pw.TextAlign.left,
                          maxLines: 2,
                          bold:
                              isGrandTotal ||
                              isSalesValue ||
                              isCashOut ||
                              isOpeningBalance ||
                              isBalanceDifference ||
                              isClosingBalance,
                        ),
                        _buildPDFCellWithTamil(
                          tx['type'],
                          align: pw.TextAlign.center,
                          bold:
                              isGrandTotal ||
                              isSalesValue ||
                              isCashOut ||
                              isBalanceDifference ||
                              isClosingBalance,
                        ),
                        // ✅ CREDIT COLUMN
                        (isClosingBalance || isCashOut)
                            ? pw.Container(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(
                                  creditAmount != 0
                                      ? 'Rs ${NumberFormat('#,##,##0.00').format(creditAmount)}'
                                      : 'Rs 0.00',
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              )
                            : _buildPDFCell(
                                creditAmount > 0
                                    ? 'Rs ${NumberFormat('#,##,##0.00').format(creditAmount)}'
                                    : '',
                                align: pw.TextAlign.center,
                                bold: isGrandTotal || isSalesValue || isCashOut,
                              ),
                        // ✅ DEBIT COLUMN - Balance Difference with color coding
                        isBalanceDifference
                            ? pw.Container(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(
                                  debitAmount != 0
                                      ? 'Rs ${debitAmount < 0 ? '-' : ''}${NumberFormat('#,##,##0.00').format(debitAmount.abs())}'
                                      : 'Rs 0.00',
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                    color: debitAmount > 0
                                        ? PdfColors
                                              .green // ✅ GREEN if positive
                                        : debitAmount < 0
                                        ? PdfColors
                                              .red // ✅ RED if negative
                                        : PdfColors.black, // ✅ BLACK if zero
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              )
                            : _buildPDFCell(
                                debitAmount > 0
                                    ? 'Rs ${NumberFormat('#,##,##0.00').format(debitAmount)}'
                                    : '',
                                align: pw.TextAlign.center,
                                bold:
                                    isGrandTotal ||
                                    isSalesValue ||
                                    isCashOut ||
                                    isClosingBalance ||
                                    isOpeningBalance,
                              ),
                      ],
                    );
                  }).toList(),
                ],
              ),

              pw.Spacer(),

              // ✅ Footer
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

    // Convert PDF document to bytes
    return await pdf.save();
  }

  // Helper functions

  /// ✅ Get transaction time professionally formatted (with AM/PM)
  static String _getTransactionTime(Map<String, dynamic> transaction) {
    try {
      if (transaction.containsKey('createdAt') &&
          transaction['createdAt'] != null) {
        final createdAt = transaction['createdAt'].toDate();
        return DateFormat('h:mm a').format(createdAt); // Example: 2:30 PM
      }
    } catch (e) {
      // Handle error silently
    }
    return ''; // Return empty string if time not available
  }

  /// ✅ Normalize Tamil text for proper rendering
  /// Ensures Tamil conjuncts (like "கு") render correctly by preserving Unicode composition
  /// Note: Dart doesn't have built-in Unicode normalization, so we preserve the text as-is
  /// The font itself should handle Tamil ligatures correctly if it's a proper Tamil font
  static String _normalizeTamilText(String text) {
    if (text.isEmpty) return text;
    // Return text as-is - the NotoSansTamil font should handle Tamil conjuncts correctly
    // The issue might be with font embedding or text encoding, not normalization
    return text;
  }

  /// ✅ Build PDF cell with pure Tamil support
  /// Uses Tamil fonts for Tamil text, no conversion
  static pw.Widget _buildPDFCellWithTamil(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    int maxLines = 1,
  }) {
    final isTamil = _containsTamilCharacters(text);
    final tamilFont = isTamil ? _getTamilFont(bold: bold) : null;

    // Warn if Tamil text detected but font not available
    if (isTamil && tamilFont == null) {
      debugPrint('⚠️ WARNING: Tamil text detected but Tamil font not loaded: "$text"');
      debugPrint('   Make sure TamilFontLoader.initializeFonts() is called in main()');
    }

    // Use Tamil font for Tamil text, default font for English
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text, // Pure Tamil text - no conversion
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          font: tamilFont, // Use Tamil font if available (null = default font)
        ),
        textAlign: align,
        maxLines: maxLines,
      ),
    );
  }

  /// ✅ Check if text contains Tamil Unicode characters
  /// Tamil Unicode range: U+0B80 to U+0BFF (includes all Tamil letters, numbers, and symbols)
  static bool _containsTamilCharacters(String text) {
    if (text.isEmpty) return false;
    // Tamil Unicode block: U+0B80 to U+0BFF
    // This includes: Tamil letters, vowels, consonants, numbers, and punctuation
    final tamilRegex = RegExp(r'[\u0B80-\u0BFF]');
    return tamilRegex.hasMatch(text);
  }

  /// Build PDF cell with pure Tamil support
  /// Uses Tamil fonts for Tamil text, no conversion
  static pw.Widget _buildPDFCell(
    String text, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
    int maxLines = 1,
  }) {
    // Check if text contains Tamil characters and use Tamil font
    final isTamil = _containsTamilCharacters(text);
    final tamilFont = isTamil ? _getTamilFont(bold: bold) : null;

    // Warn if Tamil text detected but font not available
    if (isTamil && tamilFont == null) {
      debugPrint('⚠️ WARNING: Tamil text detected but Tamil font not loaded: "$text"');
      debugPrint('   Make sure TamilFontLoader.initializeFonts() is called in main()');
    }

    // Use Tamil font for Tamil text, default font for English
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text, // Pure Tamil text - no conversion
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          font: tamilFont, // Use Tamil font if available (null = default font)
        ),
        textAlign: align,
        maxLines: maxLines,
      ),
    );
  }

  static String _getCorrectTransactionDate(
    Map<String, dynamic> transaction,
    String fallbackLedgerDate,
  ) {
    String? transactionDateStr;

    if (transaction.containsKey('transactionDate')) {
      transactionDateStr = transaction['transactionDate']?.toString();
    } else if (transaction.containsKey('date')) {
      transactionDateStr = transaction['date']?.toString();
    } else if (transaction.containsKey('createdAt') &&
        transaction['createdAt'] != null) {
      try {
        final createdAt = transaction['createdAt'].toDate();
        return DateFormat('dd-MM-yyyy').format(createdAt);
      } catch (e) {}
    }

    if (transactionDateStr != null && transactionDateStr.isNotEmpty) {
      try {
        final date = DateFormat('dd-MMM-yyyy').parse(transactionDateStr);
        return DateFormat('dd-MM-yyyy').format(date);
      } catch (e) {
        try {
          final date = DateFormat('dd-MM-yyyy').parse(transactionDateStr);
          return DateFormat('dd-MM-yyyy').format(date);
        } catch (e) {}
      }
    }

    try {
      final date = DateFormat('dd-MMM-yyyy').parse(fallbackLedgerDate);
      return DateFormat('dd-MM-yyyy').format(date);
    } catch (e) {
      return fallbackLedgerDate;
    }
  }

  /// Get particulars (customer name or ledger name) from transaction
  /// Note: Tamil text will be rendered using Tamil fonts in PDF via _buildPDFCellWithTamil
  static String _getParticulars(Map<String, dynamic> transaction) {
    final customerName = transaction['customerName']?.toString() ?? '';
    final ledgerName = transaction['ledgerName']?.toString() ?? '';

    if (customerName.isNotEmpty) return customerName;
    if (ledgerName.isNotEmpty) return ledgerName;
    return 'Transaction';
  }

  static String _getTransactionTypeDisplay(Map<String, dynamic> transaction) {
    final isCredit = transaction['isCredit'] == true;
    // Payment IN = DEBIT (isCredit = false) → "Payment In"
    // Payment OUT = CREDIT (isCredit = true) → "Payment Out"
    return isCredit ? 'Payment Out' : 'Payment In';
  }
}
