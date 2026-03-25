import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'font_loader.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// Conditional import for web - only used when on web
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html if (dart.library.html) 'dart:html';

class PDFExportService {
/// Helper to detect if running on web (using kIsWeb)
static bool get _isWeb => kIsWeb;

/// Get Tamil font - uses TamilFontLoader if available, otherwise null
static pw.Font? _getTamilFont({bool bold = false}) {
try {
if (TamilFontLoader.tamilRegular == null) {
debugPrint('Error: Tamil regular font is null');
return null;
}

if (bold) {
if (TamilFontLoader.tamilBold != null) {
return TamilFontLoader.tamilBold;
}
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

final transactionsData = transactions.map((t) {
final Map<String, dynamic> tx = Map<String, dynamic>.from(t);

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
rethrow;
}
}

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
if (TamilFontLoader.tamilRegular == null) {
debugPrint('⚠️ WARNING: Tamil fonts not initialized! PDF may not render Tamil correctly.');
}

final pdf = pw.Document();
final ledgerDate = DateFormat('dd-MMM-yyyy').format(date);

final double finalClosingBalance = isLedgerClosed ? closingBalance : 0.0;
final double finalSaleValue = isLedgerClosed ? saleValue : 0.0;
final double finalCashOut = isLedgerClosed ? cashOut : 0.0;

final List<Map<String, dynamic>> allTransactions = [
{
'date': DateFormat('dd-MM-yyyy').format(date),
'time': '',
'particulars': 'Opening Balance',
'type': '',
'debit': openingBalance,
'credit': 0.0,
},
...transactions.map((t) {
final amount = (t['amount'] ?? 0).toDouble();
final isCredit = t['isCredit'] == true;
final time = _getTransactionTime(t);

return {
'date': _getCorrectTransactionDate(t, ledgerDate),
'time': time,
'particulars': _getParticulars(t),
'type': _getTransactionTypeDisplay(t),
'debit': !isCredit ? amount : 0.0,
'credit': isCredit ? amount : 0.0,
};
}).toList(),
];

double totalDebit = allTransactions.fold(0.0, (sum, t) => sum + (t['debit'] as double));
double totalCredit = allTransactions.fold(0.0, (sum, t) => sum + (t['credit'] as double));

if (finalSaleValue > 0) {
allTransactions.add({
'date': '',
'time': '',
'particulars': 'SALES VALUE',
'type': '',
'debit': finalSaleValue,
'credit': 0.0,
});
totalDebit += finalSaleValue;
}

if (finalCashOut > 0) {
allTransactions.add({
'date': '',
'time': '',
'particulars': 'CASH OUT',
'type': '',
'debit': 0.0,
'credit': finalCashOut,
});
totalCredit += finalCashOut;
}

allTransactions.add({
'date': '',
'time': '',
'particulars': 'CLOSING BALANCE',
'type': '',
'debit': 0.0,
'credit': finalClosingBalance,
});

double grandTotalCredit = totalCredit + finalClosingBalance;

allTransactions.add({
'date': '',
'time': '',
'particulars': 'GRAND TOTAL',
'type': '',
'debit': totalDebit,
'credit': grandTotalCredit,
});

double balanceDifference = grandTotalCredit - totalDebit;

allTransactions.add({
'date': '',
'time': '',
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
pw.Center(
child: pw.Column(
children: [
pw.Text(
shopName.toUpperCase(),
style: pw.TextStyle(
fontSize: 16,
fontWeight: pw.FontWeight.bold,
font: _containsTamilCharacters(shopName)
? _getTamilFont(bold: true)
    : null,
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

pw.Text(
'Transaction Details',
style: pw.TextStyle(
fontSize: 12,
fontWeight: pw.FontWeight.bold,
),
),
pw.SizedBox(height: 8),

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
0: const pw.FlexColumnWidth(1.8),
1: const pw.FlexColumnWidth(2.5),
2: const pw.FlexColumnWidth(1.5),
3: const pw.FlexColumnWidth(1.5),
4: const pw.FlexColumnWidth(1.5),
},
children: [
pw.TableRow(
decoration: const pw.BoxDecoration(
color: PdfColors.grey200,
),
children: [
_buildPDFCell('Date', bold: true, align: pw.TextAlign.center),
_buildPDFCell('Particulars', bold: true, align: pw.TextAlign.center),
_buildPDFCell('Type', bold: true, align: pw.TextAlign.center),
_buildPDFCell('Credit (Rs)', bold: true, align: pw.TextAlign.center),
_buildPDFCell('Debit (Rs)', bold: true, align: pw.TextAlign.center),
],
),
...allTransactions.map((tx) {
final debitAmount = tx['debit'] as double;
final creditAmount = tx['credit'] as double;
final isGrandTotal = tx['particulars'] == 'GRAND TOTAL';
final isSalesValue = tx['particulars'] == 'SALES VALUE';
final isCashOut = tx['particulars'] == 'CASH OUT';
final isOpeningBalance = tx['particulars'] == 'Opening Balance';
final isBalanceDifference = tx['particulars'] == 'BALANCE DIFFERENCE';
final isClosingBalance = tx['particulars'] == 'CLOSING BALANCE';
final particulars = tx['particulars'] as String;
final txDate = tx['date'] as String;
final time = tx['time'] as String;

return pw.TableRow(
decoration: (isGrandTotal ||
isSalesValue ||
isCashOut ||
isOpeningBalance ||
isBalanceDifference ||
isClosingBalance)
? const pw.BoxDecoration(color: PdfColors.grey100)
    : null,
children: [
pw.Container(
padding: const pw.EdgeInsets.all(6),
child: pw.Text(
time.isNotEmpty ? '${txDate} | $time' : txDate,
style: pw.TextStyle(
fontSize: 8,
fontWeight: (isGrandTotal ||
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
bold: isGrandTotal ||
isSalesValue ||
isCashOut ||
isOpeningBalance ||
isBalanceDifference ||
isClosingBalance,
),
_buildPDFCellWithTamil(
tx['type'],
align: pw.TextAlign.center,
bold: isGrandTotal ||
isSalesValue ||
isCashOut ||
isBalanceDifference ||
isClosingBalance,
),
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
? PdfColors.green
    : debitAmount < 0
? PdfColors.red
    : PdfColors.black,
),
textAlign: pw.TextAlign.center,
),
)
    : _buildPDFCell(
debitAmount > 0
? 'Rs ${NumberFormat('#,##,##0.00').format(debitAmount)}'
    : '',
align: pw.TextAlign.center,
bold: isGrandTotal ||
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

return await pdf.save();
}

/// ✅ Save/Share PDF (Works on Web + Mobile)
static Future<void> saveOrSharePDF({
required Uint8List pdfBytes,
required String fileName,
required BuildContext context,
}) async {
try {
if (_isWeb) {
// ✅ WEB: Download directly
await _downloadPDFOnWeb(pdfBytes, fileName);
_showSuccessMessage(context, 'PDF downloaded successfully!');
} else {
// ✅ MOBILE: Save and share
await _saveAndSharePDFOnMobile(pdfBytes, fileName, context);
}
} catch (e) {
debugPrint('Error saving/sharing PDF: $e');
_showErrorMessage(context, 'Failed to save PDF: ${e.toString()}');
}
}

/// ✅ Web download helper
static Future<void> _downloadPDFOnWeb(Uint8List pdfBytes, String fileName) async {
try {
// Only execute on web
if (!_isWeb) return;

// Use the html library (only available on web)
// ignore: undefined_prefixed_name
final blob = html.Blob([pdfBytes], 'application/pdf');
final url = html.Url.createObjectUrlFromBlob(blob);

final anchor = html.document.createElement('a') as html.AnchorElement;
anchor.href = url;
anchor.download = fileName;
anchor.style.display = 'none';

html.document.body?.children.add(anchor);
anchor.click();

html.document.body?.children.remove(anchor);
html.Url.revokeObjectUrl(url);

debugPrint('✅ PDF downloaded on web: $fileName');
} catch (e) {
debugPrint('❌ Web download error: $e');
rethrow;
}
}

/// ✅ Mobile save and share helper
static Future<void> _saveAndSharePDFOnMobile(
Uint8List pdfBytes,
String fileName,
BuildContext context,
) async {
try {
final directory = await getTemporaryDirectory();
final filePath = '${directory.path}/$fileName';
final file = File(filePath);

await file.writeAsBytes(pdfBytes);
debugPrint('✅ PDF saved temporarily: $filePath');

await Share.shareXFiles(
[XFile(filePath)],
text: 'Ledger Report - $fileName',
);

debugPrint('✅ PDF shared successfully');

Future.delayed(const Duration(seconds: 5), () async {
try {
if (await file.exists()) {
await file.delete();
debugPrint('✅ Temporary PDF deleted');
}
} catch (e) {
debugPrint('Error deleting temp file: $e');
}
});
} catch (e) {
debugPrint('❌ Mobile save/share error: $e');
rethrow;
}
}

/// ✅ Show success message
static void _showSuccessMessage(BuildContext context, String message) {
if (context.mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Row(
children: [
const Icon(Icons.check_circle, color: Colors.white, size: 20),
const SizedBox(width: 12),
Expanded(child: Text(message)),
],
),
backgroundColor: Colors.green,
behavior: SnackBarBehavior.floating,
duration: const Duration(seconds: 2),
),
);
}
}

/// ✅ Show error message
static void _showErrorMessage(BuildContext context, String message) {
if (context.mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(
content: Row(
children: [
const Icon(Icons.error_outline, color: Colors.white, size: 20),
const SizedBox(width: 12),
Expanded(child: Text(message)),
],
),
backgroundColor: Colors.red,
behavior: SnackBarBehavior.floating,
duration: const Duration(seconds: 3),
),
);
}
}

// Helper functions
static String _getTransactionTime(Map<String, dynamic> transaction) {
try {
if (transaction.containsKey('createdAt') && transaction['createdAt'] != null) {
final createdAt = transaction['createdAt'].toDate();
return DateFormat('h:mm a').format(createdAt);
}
} catch (e) {}
return '';
}

static pw.Widget _buildPDFCellWithTamil(
String text, {
bool bold = false,
pw.TextAlign align = pw.TextAlign.left,
int maxLines = 1,
}) {
final isTamil = _containsTamilCharacters(text);
final tamilFont = isTamil ? _getTamilFont(bold: bold) : null;

if (isTamil && tamilFont == null) {
debugPrint('⚠️ WARNING: Tamil text detected but Tamil font not loaded: "$text"');
}

return pw.Container(
padding: const pw.EdgeInsets.all(6),
child: pw.Text(
text,
style: pw.TextStyle(
fontSize: 9,
fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
font: tamilFont,
),
textAlign: align,
maxLines: maxLines,
),
);
}

static bool _containsTamilCharacters(String text) {
if (text.isEmpty) return false;
final tamilRegex = RegExp(r'[\u0B80-\u0BFF]');
return tamilRegex.hasMatch(text);
}

static pw.Widget _buildPDFCell(
String text, {
bool bold = false,
pw.TextAlign align = pw.TextAlign.left,
int maxLines = 1,
}) {
final isTamil = _containsTamilCharacters(text);
final tamilFont = isTamil ? _getTamilFont(bold: bold) : null;

if (isTamil && tamilFont == null) {
debugPrint('⚠️ WARNING: Tamil text detected but Tamil font not loaded: "$text"');
}

return pw.Container(
padding: const pw.EdgeInsets.all(6),
child: pw.Text(
text,
style: pw.TextStyle(
fontSize: 9,
fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
font: tamilFont,
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
} else if (transaction.containsKey('createdAt') && transaction['createdAt'] != null) {
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

static String _getParticulars(Map<String, dynamic> transaction) {
final customerName = transaction['customerName']?.toString() ?? '';
final ledgerName = transaction['ledgerName']?.toString() ?? '';

if (customerName.isNotEmpty) return customerName;
if (ledgerName.isNotEmpty) return ledgerName;
return 'Transaction';
}

static String _getTransactionTypeDisplay(Map<String, dynamic> transaction) {
final isCredit = transaction['isCredit'] == true;
return isCredit ? 'Payment Out' : 'Payment In';
}
}