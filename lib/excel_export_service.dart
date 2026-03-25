import 'package:excel/excel.dart' as excel_pkg;
import 'package:intl/intl.dart';

class ExcelExportService {
  static excel_pkg.Excel generateLedgerExcel({
    required DateTime date,
    required String shopName,
    required double openingBalance,
    required double closingBalance,
    required double saleValue,
    required double cashOut,
    required List<Map<String, dynamic>> transactions,
    required bool isLedgerClosed,
  }) {
    final excel = excel_pkg.Excel.createExcel();
    final sheet = excel['Ledger Report'];
    final ledgerDate = DateFormat('dd-MMM-yyyy').format(date);

    int row = 0;

    // ✅ If ledger is NOT closed, set closing balance, sales value, and cash out to 0
    final double finalClosingBalance = isLedgerClosed ? closingBalance : 0.0;
    final double finalSaleValue = isLedgerClosed ? saleValue : 0.0;
    final double finalCashOut = isLedgerClosed ? cashOut : 0.0;

    // Header (only once at the top)
    _mergeAndWriteExcel(sheet, row, 0, 4, shopName.toUpperCase());
    _styleExcelHeader(sheet, row, 0);
    row++;

    _mergeAndWriteExcel(
      sheet,
      row,
      0,
      4,
      'Ledger Report - Date: $ledgerDate',
    );
    _styleExcelSubHeader(sheet, row, 0);
    row += 2;

    // ✅ Create transaction list with opening balance as first row
    final List<Map<String, dynamic>> allTransactions = [
      // Opening balance row (first entry)
      {
        'date': DateFormat('dd-MM-yyyy').format(date),
        'particulars': 'Opening Balance',
        'type': '',
        'debit': openingBalance,
        'credit': 0.0,
      },
      // ✅ Add all actual transactions with CORRECT TRANSACTION DATE in chronological order
      ...transactions.map((t) {
        final amount = (t['amount'] ?? 0).toDouble();
        final isCredit = t['isCredit'] == true;

        return {
          'date': _getCorrectTransactionDate(t, ledgerDate),
          'particulars': _getParticulars(t),
          'type': _getTransactionTypeDisplay(t),
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
      'particulars': 'CLOSING BALANCE',
      'type': '',
      'debit': 0.0,
      'credit': finalClosingBalance,
    });

    // ✅ ADD CLOSING BALANCE AND CASH OUT TO TOTAL CREDIT FOR GRAND TOTAL CALCULATION
    // totalCredit already includes cashOut, so just add closingBalance
    double grandTotalCredit = totalCredit + finalClosingBalance;

    // ✅ Add GRAND TOTAL row (AFTER CLOSING BALANCE)
    // Grand Total Debit stays the same
    // Grand Total Credit NOW INCLUDES Closing Balance
    allTransactions.add({
      'date': '',
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
      'particulars': 'BALANCE DIFFERENCE',
      'type': '',
      'debit': balanceDifference,
      'credit': 0.0,
    });

    // Transaction Details title
    _mergeAndWriteExcel(sheet, row, 0, 4, 'Transaction Details');
    _styleExcelTableTitle(sheet, row, 0);
    row += 2;

    // ✅ Table header
    _writeExcelCell(sheet, row, 0, 'Date');
    _writeExcelCell(sheet, row, 1, 'Particulars');
    _writeExcelCell(sheet, row, 2, 'Type');
    _writeExcelCell(sheet, row, 3, 'Credit (Rs)');
    _writeExcelCell(sheet, row, 4, 'Debit (Rs)');

    for (int col = 0; col <= 4; col++) {
      _styleExcelTableHeader(sheet, row, col);
    }
    row++;

    // Transaction rows
    for (final trans in allTransactions) {
      final debitAmount = trans['debit'] as double;
      final creditAmount = trans['credit'] as double;
      final isGrandTotal = trans['particulars'] == 'GRAND TOTAL';
      final isSalesValue = trans['particulars'] == 'SALES VALUE';
      final isCashOut = trans['particulars'] == 'CASH OUT';
      final isOpeningBalance = trans['particulars'] == 'Opening Balance';
      final isBalanceDifference = trans['particulars'] == 'BALANCE DIFFERENCE';
      final isClosingBalance = trans['particulars'] == 'CLOSING BALANCE';

      _writeExcelCell(sheet, row, 0, trans['date'] ?? '');
      _writeExcelCell(sheet, row, 1, trans['particulars'] ?? '');
      _writeExcelCell(sheet, row, 2, trans['type'] ?? '');

      // ✅ CREDIT COLUMN
      if (isClosingBalance || isCashOut) {
        _writeExcelCell(
          sheet,
          row,
          3,
          creditAmount != 0
              ? 'Rs ${NumberFormat('#,##,##0.00').format(creditAmount)}'
              : 'Rs 0.00',
        );
      } else {
        _writeExcelCell(
          sheet,
          row,
          3,
          creditAmount > 0
              ? 'Rs ${NumberFormat('#,##,##0.00').format(creditAmount)}'
              : '',
        );
      }

      // ✅ DEBIT COLUMN - Balance Difference with conditional formatting
      if (isBalanceDifference) {
        _writeExcelCell(
          sheet,
          row,
          4,
          debitAmount != 0
              ? 'Rs ${debitAmount < 0 ? '-' : ''}${NumberFormat('#,##,##0.00').format(debitAmount.abs())}'
              : 'Rs 0.00',
        );
      } else {
        _writeExcelCell(
          sheet,
          row,
          4,
          debitAmount > 0
              ? 'Rs ${NumberFormat('#,##,##0.00').format(debitAmount)}'
              : '',
        );
      }

      // Style cells - highlight special rows
      final isBoldRow =
          isGrandTotal ||
          isSalesValue ||
          isCashOut ||
          isOpeningBalance ||
          isBalanceDifference ||
          isClosingBalance;

      _styleExcelCell(
        sheet,
        row,
        0,
        isCenter: true,
        isBold: isBoldRow,
        isHighlighted: isBoldRow,
      );
      _styleExcelCell(
        sheet,
        row,
        1,
        isLeft: true,
        isBold: isBoldRow,
        isHighlighted: isBoldRow,
      );
      _styleExcelCell(
        sheet,
        row,
        2,
        isCenter: true,
        isBold: isBoldRow,
        isHighlighted: isBoldRow,
      );
      _styleExcelCell(
        sheet,
        row,
        3,
        isCenter: true,
        isBold: isBoldRow,
        isHighlighted: isBoldRow,
      );
      _styleExcelCell(
        sheet,
        row,
        4,
        isCenter: true,
        isBold: isBoldRow,
        isHighlighted: isBoldRow,
      );

      row++;
    }

    row += 2;

    // Quote & Footer
    _mergeAndWriteExcel(
      sheet,
      row,
      0,
      4,
      '"Financial stability is the foundation of success. Track every rupee, plan every expense, grow exponentially."',
    );
    _styleExcelQuote(sheet, row, 0);
    row++;

    _mergeAndWriteExcel(sheet, row, 0, 4, 'Powered by Ledger System');
    _styleExcelFooter(sheet, row, 0);

    // ✅ Column widths
    sheet.setColumnWidth(0, 18); // Date
    sheet.setColumnWidth(1, 28); // Particulars
    sheet.setColumnWidth(2, 15); // Type
    sheet.setColumnWidth(3, 18); // Credit
    sheet.setColumnWidth(4, 18); // Debit

    return excel;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // HELPER FUNCTIONS
  // ═══════════════════════════════════════════════════════════════════════

  /// ✅ Get CORRECT transaction date (not today's date)
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
      } catch (e) {
        // Handle error silently
      }
    }

    if (transactionDateStr != null && transactionDateStr.isNotEmpty) {
      try {
        final date = DateFormat('dd-MMM-yyyy').parse(transactionDateStr);
        return DateFormat('dd-MM-yyyy').format(date);
      } catch (e) {
        try {
          final date = DateFormat('dd-MM-yyyy').parse(transactionDateStr);
          return DateFormat('dd-MM-yyyy').format(date);
        } catch (e) {
          // Failed to parse
        }
      }
    }

    try {
      final date = DateFormat('dd-MMM-yyyy').parse(fallbackLedgerDate);
      return DateFormat('dd-MM-yyyy').format(date);
    } catch (e) {
      return fallbackLedgerDate;
    }
  }

  /// Get particulars (customer name or ledger name)
  static String _getParticulars(Map<String, dynamic> transaction) {
    final customerName = transaction['customerName']?.toString() ?? '';
    final ledgerName = transaction['ledgerName']?.toString() ?? '';

    if (customerName.isNotEmpty) return customerName;
    if (ledgerName.isNotEmpty) return ledgerName;
    return 'Transaction';
  }

  /// Get transaction type display - Payment In/Payment Out
  static String _getTransactionTypeDisplay(Map<String, dynamic> transaction) {
    final isCredit = transaction['isCredit'] == true;
    // Payment IN = DEBIT (isCredit = false) → "Payment In"
    // Payment OUT = CREDIT (isCredit = true) → "Payment Out"
    return isCredit ? 'Payment Out' : 'Payment In';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // EXCEL HELPER FUNCTIONS
  // ═══════════════════════════════════════════════════════════════════════

  static void _mergeAndWriteExcel(
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

  static void _writeExcelCell(
    excel_pkg.Sheet sheet,
    int row,
    int col,
    String text,
  ) {
    sheet
        .cell(
          excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
        )
        .value = excel_pkg.TextCellValue(
      text,
    );
  }

  static void _styleExcelHeader(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: excel_pkg.HorizontalAlign.Center,
    );
  }

  static void _styleExcelSubHeader(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      fontSize: 12,
      horizontalAlign: excel_pkg.HorizontalAlign.Center,
    );
  }

  static void _styleExcelTableTitle(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      bold: true,
      fontSize: 12,
      horizontalAlign: excel_pkg.HorizontalAlign.Left,
    );
  }

  static void _styleExcelTableHeader(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      bold: true,
      fontSize: 11,
      horizontalAlign: excel_pkg.HorizontalAlign.Center,
    );
  }

  static void _styleExcelCell(
    excel_pkg.Sheet sheet,
    int row,
    int col, {
    bool isLeft = false,
    bool isCenter = false,
    bool isRight = false,
    bool isBold = false,
    bool isHighlighted = false,
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

  static void _styleExcelQuote(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      italic: true,
      fontSize: 10,
      horizontalAlign: excel_pkg.HorizontalAlign.Center,
    );
  }

  static void _styleExcelFooter(excel_pkg.Sheet sheet, int row, int col) {
    final cell = sheet.cell(
      excel_pkg.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.cellStyle = excel_pkg.CellStyle(
      fontSize: 9,
      horizontalAlign: excel_pkg.HorizontalAlign.Center,
    );
  }
}
