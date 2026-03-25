import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:excel/excel.dart' as excel;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'balance_details_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String? shopCollection; // ✅ ADD THIS LINE

  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.shopCollection, // ✅ ADD THIS LINE
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  bool _isDownloading = false;
  String? _selectedShopCollection;
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initializeShop();
  }

  Future<void> _initializeShop() async {
    try {
      String? shopCollection =
          widget.shopCollection; // ✅ Use widget.shopCollection
      print('DEBUG: Initial shopCollection from widget: $shopCollection');

      // If not passed, try to get from SharedPreferences
      if (shopCollection == null || shopCollection.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        shopCollection = prefs.getString('shopCollection');
        print('DEBUG: shopCollection from SharedPreferences: $shopCollection');
      }

      print('DEBUG: Final shopCollection before validation: $shopCollection');

      // Validate before setting state
      if (shopCollection != null && shopCollection.isNotEmpty) {
        if (mounted) {
          setState(() {
            _selectedShopCollection = shopCollection;
          });
          print(
            'DEBUG: shopCollection set successfully: $_selectedShopCollection',
          );
        }
      } else {
        // Show error if no shop collection found
        print('DEBUG: shopCollection is null or empty');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Error: Shop information not available. Please pass shopCollection parameter.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('DEBUG: Error in _initializeShop: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing shop: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 🔹 Check if device is in landscape mode
  bool _isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  Future<Map<String, dynamic>> _getCustomerData() async {
    if (_selectedShopCollection == null || _selectedShopCollection!.isEmpty) {
      return {};
    }

    try {
      final customerDoc = await FirebaseFirestore.instance
          .collection(_selectedShopCollection!)
          .doc('customers')
          .collection('list')
          .doc(widget.customerId)
          .get();

      final data = customerDoc.data() ?? {};
      final openingAmount = (data['openingAmount'] ?? 0).toDouble();
      final openingDate = data['openingDate'] ?? '';

      return {
        'openingAmount': openingAmount,
        'openingDate': openingDate,
        'customerType': data['customerType'] ?? '',
        'mobile': data['mobile'] ?? '',
        'createdBy': data['createdBy'] ?? 'Unknown',
        'status': data['status'] ?? 'Active',
      };
    } catch (e) {
      print('Error fetching customer data: $e');
      return {};
    }
  }

  String _formatAmount(double amount) {
    return NumberFormat('#,##,##0.00').format(amount);
  }

  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return DateFormat('dd-MMM-yyyy').format(date);
  }

  String _formatTime(Timestamp timestamp) {
    final date = timestamp.toDate();
    return DateFormat('h:mm a').format(date);
  }

  Future<void> _makePhoneCall(String phoneNumber, BuildContext context) async {
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Phone number not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final Uri phoneUri = Uri(scheme: 'tel', path: cleanNumber);

    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot make phone calls on this device'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error making call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 🔹 Show Download Dialog
  void _showDownloadDialog(List<QueryDocumentSnapshot> docs) {
    final isLandscape = _isLandscape(context);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: EdgeInsets.all(isLandscape ? 20 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1976D2), Color(0xFF4285F4)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.download,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Download Report',
                            style: TextStyle(
                              fontSize: isLandscape ? 18 : 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            'Choose format',
                            style: TextStyle(
                              fontSize: isLandscape ? 13 : 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isLandscape ? 20 : 24),

                // Download Options
                _buildDownloadOption(
                  context,
                  icon: Icons.picture_as_pdf,
                  iconColor: Colors.red,
                  title: 'Download as PDF',
                  subtitle: 'Portable document format',
                  onTap: () {
                    Navigator.pop(context);
                    _downloadAsPDF(docs);
                  },
                  isLandscape: isLandscape,
                ),
                SizedBox(height: isLandscape ? 12 : 16),
                _buildDownloadOption(
                  context,
                  icon: Icons.table_chart,
                  iconColor: Colors.green,
                  title: 'Download as Excel',
                  subtitle: 'Spreadsheet format',
                  onTap: () {
                    Navigator.pop(context);
                    _downloadAsExcel(docs);
                  },
                  isLandscape: isLandscape,
                ),
                SizedBox(height: isLandscape ? 16 : 20),

                // Cancel Button
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isLandscape ? 24 : 32,
                      vertical: isLandscape ? 10 : 12,
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: isLandscape ? 14 : 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
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

  Widget _buildDownloadOption(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isLandscape,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(isLandscape ? 14 : 16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: isLandscape ? 26 : 28),
            ),
            SizedBox(width: isLandscape ? 14 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: isLandscape ? 15 : 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: isLandscape ? 12 : 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: isLandscape ? 16 : 18,
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  /// 🔹 Download as PDF (Optimized)
  Future<void> _downloadAsPDF(List<QueryDocumentSnapshot> docs) async {
    setState(() => _isDownloading = true);

    try {
      // Get customer data
      final customerData = await _getCustomerData();
      final openingAmount = customerData['openingAmount'] as double;
      final mobile = customerData['mobile'] as String;

      // Calculate transactions and balance
      // Payment IN = DEBIT (isCredit = false) → money received from customer → REDUCE balance (subtract)
      // Payment OUT = CREDIT (isCredit = true) → money given to customer → INCREASE balance (add)
      double runningBalance = openingAmount;
      final transactions = <Map<String, dynamic>>[];

      for (var doc in docs.reversed) {
        final data = doc.data() as Map<String, dynamic>;
        final amount = (data['amount'] ?? 0).toDouble();
        final isCredit = data['isCredit'] ?? false;

        if (isCredit) {
          runningBalance += amount; // Payment OUT increases what customer owes
        } else {
          runningBalance -= amount; // Payment IN reduces what customer owes
        }

        transactions.add({...data, 'balance': runningBalance});
      }

      // Create PDF
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              // Header
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.blue50,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Customer Transaction Report',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Customer: ${widget.customerName}',
                      style: const pw.TextStyle(fontSize: 16),
                    ),
                    pw.Text(
                      'Mobile: $mobile',
                      style: const pw.TextStyle(fontSize: 14),
                    ),
                    pw.Text(
                      'Generated: ${DateFormat('dd-MMM-yyyy HH:mm').format(DateTime.now())}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Opening Balance
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Opening Balance:',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Rs. ${_formatAmount(openingAmount)}',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.red,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Transactions Table
              if (transactions.isNotEmpty)
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey400),
                  children: [
                    // Header Row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.blue100,
                      ),
                      children: [
                        _buildTableCell('Date', isHeader: true),
                        _buildTableCell('Description', isHeader: true),
                        _buildTableCell('Type', isHeader: true),
                        _buildTableCell('Amount', isHeader: true),
                        _buildTableCell('Balance', isHeader: true),
                      ],
                    ),
                    // Data Rows
                    ...transactions.map((data) {
                      final createdAt = data['createdAt'] as Timestamp?;
                      final amount = (data['amount'] ?? 0).toDouble();
                      final isCredit = data['isCredit'] ?? false;
                      final balance = data['balance'] as double;

                      return pw.TableRow(
                        children: [
                          _buildTableCell(
                            createdAt != null ? _formatDate(createdAt) : 'N/A',
                          ),
                          _buildTableCell(
                            data['description'] ?? 'No description',
                          ),
                          _buildTableCell(
                            // Payment IN = DEBIT (isCredit = false) → "Payment In"
                            // Payment OUT = CREDIT (isCredit = true) → "Payment Out"
                            isCredit ? 'Payment Out' : 'Payment In',
                          ),
                          _buildTableCell('Rs. ${_formatAmount(amount)}'),
                          _buildTableCell('Rs. ${_formatAmount(balance)}'),
                        ],
                      );
                    }),
                  ],
                )
              else
                pw.Center(
                  child: pw.Text(
                    'No transactions found',
                    style: pw.TextStyle(fontSize: 14, color: PdfColors.grey),
                  ),
                ),
              pw.SizedBox(height: 20),

              // Final Balance
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  border: pw.Border.all(color: PdfColors.green200),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Current Balance:',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Rs. ${_formatAmount(runningBalance)}',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: runningBalance >= 0
                            ? PdfColors.red
                            : PdfColors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ];
          },
        ),
      );

      // Save and open PDF
      final output = await getApplicationDocumentsDirectory();
      final fileName =
          '${widget.customerName.replaceAll(' ', '_')}_transactions_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      setState(() => _isDownloading = false);

      if (mounted) {
        _showSuccessDialog('PDF', file.path);
      }
    } catch (e) {
      setState(() => _isDownloading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 🔹 Download as Excel (Optimized)
  Future<void> _downloadAsExcel(List<QueryDocumentSnapshot> docs) async {
    setState(() => _isDownloading = true);

    try {
      // Get customer data
      final customerData = await _getCustomerData();
      final openingAmount = customerData['openingAmount'] as double;
      final mobile = customerData['mobile'] as String;

      var excelFile = excel.Excel.createExcel();
      excel.Sheet sheetObject = excelFile['Transactions'];

      // Set column widths
      sheetObject.setColumnWidth(0, 15);
      sheetObject.setColumnWidth(1, 12);
      sheetObject.setColumnWidth(2, 30);
      sheetObject.setColumnWidth(3, 15);
      sheetObject.setColumnWidth(4, 15);
      sheetObject.setColumnWidth(5, 15);

      // Add title
      sheetObject.merge(
        excel.CellIndex.indexByString('A1'),
        excel.CellIndex.indexByString('F1'),
      );
      var titleCell = sheetObject.cell(excel.CellIndex.indexByString('A1'));
      titleCell.value = excel.TextCellValue(
        'Customer Transaction Report - ${widget.customerName}',
      );
      titleCell.cellStyle = excel.CellStyle(
        bold: true,
        fontSize: 16,
        horizontalAlign: excel.HorizontalAlign.Center,
        backgroundColorHex: excel.ExcelColor.blue,
        fontColorHex: excel.ExcelColor.white,
      );

      // Add customer info
      int row = 2;
      sheetObject
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = excel.TextCellValue(
        'Customer:',
      );
      sheetObject
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = excel.TextCellValue(
        widget.customerName,
      );

      row++;
      sheetObject
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = excel.TextCellValue(
        'Mobile:',
      );
      sheetObject
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = excel.TextCellValue(
        mobile,
      );

      row++;
      sheetObject
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = excel.TextCellValue(
        'Generated:',
      );
      sheetObject
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
          .value = excel.TextCellValue(
        DateFormat('dd-MMM-yyyy HH:mm').format(DateTime.now()),
      );

      // Add opening balance
      row += 2;
      sheetObject
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = excel.TextCellValue(
        'Opening Balance:',
      );
      var openingCell = sheetObject.cell(
        excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
      );
      openingCell.value = excel.DoubleCellValue(openingAmount);
      openingCell.cellStyle = excel.CellStyle(
        bold: true,
        fontColorHex: excel.ExcelColor.red,
      );

      // Add table headers
      row += 2;
      final headers = [
        'Date',
        'Time',
        'Description',
        'Type',
        'Amount',
        'Balance',
      ];
      for (int i = 0; i < headers.length; i++) {
        var cell = sheetObject.cell(
          excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row),
        );
        cell.value = excel.TextCellValue(headers[i]);
        cell.cellStyle = excel.CellStyle(
          bold: true,
          backgroundColorHex: excel.ExcelColor.blue,
          fontColorHex: excel.ExcelColor.white,
          horizontalAlign: excel.HorizontalAlign.Center,
        );
      }

      // Add transaction data
      // Payment IN = DEBIT (isCredit = false) → money received from customer → REDUCE balance (subtract)
      // Payment OUT = CREDIT (isCredit = true) → money given to customer → INCREASE balance (add)
      double runningBalance = openingAmount;
      for (var doc in docs.reversed) {
        row++;
        final data = doc.data() as Map<String, dynamic>;
        final createdAt = data['createdAt'] as Timestamp?;
        final amount = (data['amount'] ?? 0).toDouble();
        final isCredit = data['isCredit'] ?? false;
        final description = data['description'] ?? 'No description';

        if (isCredit) {
          runningBalance += amount; // Payment OUT increases what customer owes
        } else {
          runningBalance -= amount; // Payment IN reduces what customer owes
        }

        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
            )
            .value = excel.TextCellValue(
          createdAt != null ? _formatDate(createdAt) : 'N/A',
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
            )
            .value = excel.TextCellValue(
          createdAt != null ? _formatTime(createdAt) : 'N/A',
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row),
            )
            .value = excel.TextCellValue(
          description,
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row),
            )
            .value = excel.TextCellValue(
          // Payment IN = DEBIT (isCredit = false) → "Payment In"
          // Payment OUT = CREDIT (isCredit = true) → "Payment Out"
          isCredit ? 'Payment Out' : 'Payment In',
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row),
            )
            .value = excel.DoubleCellValue(
          amount,
        );
        sheetObject
            .cell(
              excel.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row),
            )
            .value = excel.DoubleCellValue(
          runningBalance,
        );
      }

      // Add final balance
      row += 2;
      sheetObject
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
          .value = excel.TextCellValue(
        'Current Balance:',
      );
      var balanceCell = sheetObject.cell(
        excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row),
      );
      balanceCell.value = excel.DoubleCellValue(runningBalance);
      balanceCell.cellStyle = excel.CellStyle(
        bold: true,
        fontColorHex: runningBalance >= 0
            ? excel.ExcelColor.red
            : excel.ExcelColor.green,
      );

      // Save Excel file
      final output = await getApplicationDocumentsDirectory();
      final fileName =
          '${widget.customerName.replaceAll(' ', '_')}_transactions_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(excelFile.encode()!);

      setState(() => _isDownloading = false);

      if (mounted) {
        _showSuccessDialog('Excel', file.path);
      }
    } catch (e) {
      setState(() => _isDownloading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating Excel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 12 : 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  /// 🔹 Show Success Dialog (Open and Share)
  void _showSuccessDialog(String fileType, String filePath) async {
    final isLandscape = _isLandscape(context);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: EdgeInsets.all(isLandscape ? 20 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Success Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 48,
                  ),
                ),
                SizedBox(height: isLandscape ? 16 : 20),

                // Success Message
                Text(
                  '$fileType Downloaded Successfully!',
                  style: TextStyle(
                    fontSize: isLandscape ? 18 : 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: isLandscape ? 6 : 8),
                Text(
                  'Your file has been saved',
                  style: TextStyle(
                    fontSize: isLandscape ? 13 : 14,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: isLandscape ? 20 : 24),

                // Action Buttons Row
                Row(
                  children: [
                    // Open Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await OpenFile.open(filePath);
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4285F4),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: isLandscape ? 12 : 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: isLandscape ? 10 : 12),
                    // Share Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.pop(context);
                          await Share.shareXFiles([
                            XFile(filePath),
                          ], text: '${widget.customerName} Transaction Report');
                        },
                        icon: const Icon(Icons.share),
                        label: const Text('Share'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF4285F4),
                          padding: EdgeInsets.symmetric(
                            vertical: isLandscape ? 12 : 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(
                              color: Color(0xFF4285F4),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isLandscape ? 10 : 12),

                // Close Button
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isLandscape ? 24 : 32,
                      vertical: isLandscape ? 10 : 12,
                    ),
                  ),
                  child: Text(
                    'Close',
                    style: TextStyle(
                      fontSize: isLandscape ? 14 : 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
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

  /// 🔹 Show modern customer details bottom sheet
  void _showCustomerDetailsBottomSheet(BuildContext context) {
    final isLandscape = _isLandscape(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.5,
        maxChildSize: 0.8,
        builder: (context, scrollController) => SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isLandscape ? 20 : 24,
                    vertical: isLandscape ? 12 : 16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: isLandscape ? 40 : 44,
                        height: isLandscape ? 40 : 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1976D2), Color(0xFF4285F4)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: isLandscape ? 20 : 22,
                        ),
                      ),
                      SizedBox(width: isLandscape ? 12 : 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.customerName,
                              style: TextStyle(
                                fontSize: isLandscape ? 17 : 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              'Customer Details',
                              style: TextStyle(
                                fontSize: isLandscape ? 12 : 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Divider
                Container(
                  height: 1,
                  margin: EdgeInsets.symmetric(horizontal: isLandscape ? 20 : 24),
                  color: Colors.grey[200],
                ),
                // Content
                Expanded(
                  child: FutureBuilder<DocumentSnapshot>(
                    future:
                        _selectedShopCollection != null &&
                            _selectedShopCollection!.isNotEmpty
                        ? FirebaseFirestore.instance
                              .collection(_selectedShopCollection!)
                              .doc('customers')
                              .collection('list')
                              .doc(widget.customerId)
                              .get()
                        : Future.error('Shop collection not available'),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF4285F4),
                          ),
                        );
                      }

                      if (snapshot.hasError ||
                          !snapshot.hasData ||
                          !snapshot.data!.exists) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: isLandscape ? 40 : 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Customer details not found',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: isLandscape ? 14 : 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final data = snapshot.data!.data() as Map<String, dynamic>?;
                      if (data == null) {
                        return const Center(child: Text('No data available'));
                      }

                      // Format timestamps
                      String formatTimestamp(dynamic timestamp) {
                        if (timestamp == null) return 'Not available';
                        if (timestamp is Timestamp) {
                          final date = timestamp.toDate();
                          return DateFormat('dd MMM yyyy, hh:mm a').format(date);
                        }
                        return timestamp.toString();
                      }

                      return SingleChildScrollView(
                        controller: scrollController,
                        padding: EdgeInsets.only(
                          left: isLandscape ? 20 : 24,
                          right: isLandscape ? 20 : 24,
                          top: isLandscape ? 12 : 16,
                          bottom: isLandscape ? 16 : 20, // ✅ Extra bottom padding
                        ),
                        child: Column(
                          children: [
                            _buildCompactDetailRow(
                              'Mobile',
                              data['mobile'] ?? 'Not provided',
                              Icons.phone,
                              isLandscape,
                            ),
                            _buildCompactDetailRow(
                              'Type',
                              data['customerType'] ?? 'Not specified',
                              Icons.category,
                              isLandscape,
                            ),
                            _buildCompactDetailRow(
                              'Status',
                              data['status'] ?? 'Active',
                              Icons.info_outline,
                              isLandscape,
                            ),
                            _buildCompactDetailRow(
                              'Opening Amount',
                              '₹${_formatAmount((data['openingAmount'] ?? 0).toDouble())}',
                              Icons.account_balance_wallet,
                              isLandscape,
                            ),
                            _buildCompactDetailRow(
                              'Opening Date',
                              data['openingDate'] ?? 'Not available',
                              Icons.calendar_today,
                              isLandscape,
                            ),
                            _buildCompactDetailRow(
                              'Created By',
                              data['createdBy'] ?? 'Unknown',
                              Icons.person_add,
                              isLandscape,
                            ),
                            _buildCompactDetailRow(
                              'Created',
                              formatTimestamp(data['createdAt']),
                              Icons.access_time,
                              isLandscape,
                            ),
                            _buildCompactDetailRow(
                              'Last Transaction',
                              formatTimestamp(data['lastTransaction']),
                              Icons.receipt_long,
                              isLandscape,
                              isLast: true,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactDetailRow(
    String label,
    String value,
    IconData icon,
    bool isLandscape, {
    bool isLast = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: isLandscape ? 10 : 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: isLast
              ? BorderSide.none
              : BorderSide(color: Colors.grey[200]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF4285F4),
              size: isLandscape ? 16 : 18,
            ),
          ),
          SizedBox(width: isLandscape ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: isLandscape ? 11 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: isLandscape ? 13 : 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerInfoSection(
    bool isLandscape,
    double balance,
    String mobile,
    BuildContext context,
  ) {
    final bool isPositive = balance >= 0;
    final Color primaryColor =
        isPositive ? (Colors.red[700]!) : Colors.green[700]!;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.zero,
      padding: EdgeInsets.all(isLandscape ? 18 : 20),
      decoration: BoxDecoration(
        color: isPositive ? Colors.red[50] : Colors.green[50],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Outstanding Amount',
            style: TextStyle(
              fontSize: isLandscape ? 14 : 15,
              fontWeight: FontWeight.w600,
              color: primaryColor,
            ),
          ),
          Text(
            '₹${_formatAmount(balance.abs())}',
            style: TextStyle(
              fontSize: isLandscape ? 24 : 28,
              fontWeight: FontWeight.w800,
              color: primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfessionalShimmer(bool isLandscape) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Column(
        children: [
          Container(
            margin: EdgeInsets.all(isLandscape ? 14 : 16),
            height: isLandscape ? 90 : 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: 8,
              itemBuilder: (context, index) {
                return Container(
                  margin: EdgeInsets.symmetric(
                    horizontal: isLandscape ? 14 : 16,
                    vertical: isLandscape ? 6 : 8,
                  ),
                  height: isLandscape ? 65 : 75,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionItem(
    Map<String, dynamic> data,
    double startBalance,
    bool isLandscape,
  ) {
    final amount = (data['amount'] ?? 0).toDouble();
    final isCredit = data['isCredit'] ?? false;
    final description = data['description'] ?? 'No description';
    final createdAt = data['createdAt'] as Timestamp?;

    // Payment IN = DEBIT (isCredit = false) = GREEN (money coming in)
    // Payment OUT = CREDIT (isCredit = true) = RED (money going out)
    final transactionColor = isCredit ? Colors.red[700] : Colors.green[700];
    final String typeLabel =
        isCredit ? 'Credit to customer' : 'Received from customer';

    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 14 : 16,
            vertical: isLandscape ? 12 : 14,
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: isLandscape ? 40 : 46,
                height: isLandscape ? 40 : 46,
                decoration: BoxDecoration(
                  // Payment IN = DEBIT (isCredit = false) = GREEN
                  // Payment OUT = CREDIT (isCredit = true) = RED
                  color: isCredit
                      ? Colors.red.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  // Payment IN (isCredit=false) = money coming in = arrow up
                  // Payment OUT (isCredit=true) = money going out = arrow down
                  isCredit ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  color: transactionColor,
                  size: isLandscape ? 20 : 22,
                ),
              ),
              SizedBox(width: isLandscape ? 10 : 12),
              // Description and Date/Time
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main Title: Description (Bold)
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                        fontSize: isLandscape ? 14 : 15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Type label: Payment In / Out wording
                    Text(
                      typeLabel,
                      style: TextStyle(
                        color: transactionColor,
                        fontSize: isLandscape ? 11 : 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Subtitle: Date & Time + balance before this transaction
                    if (createdAt != null) ...[
                      SizedBox(height: isLandscape ? 3 : 4),
                      Text(
                        '${_formatDate(createdAt)} at ${_formatTime(createdAt)}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w400,
                          fontSize: isLandscape ? 12 : 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Balance before: ₹${_formatAmount(startBalance)}',
                        style: TextStyle(
                          color: Colors.grey[500],
                          fontSize: isLandscape ? 11 : 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: isLandscape ? 8 : 10),
              // Amount
              Text(
                '₹${_formatAmount(amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: isLandscape ? 15.5 : 16.5,
                  color: transactionColor,
                ),
              ),
            ],
          ),
        ),
        // Divider
        Divider(
          height: 1,
          thickness: 1,
          indent: isLandscape ? 66 : 78,
          endIndent: isLandscape ? 14 : 16,
          color: Colors.grey[200],
        ),
      ],
    );
  }

  /// 🔹 Show detailed balance summary (opening, totals, per-date balances)
  Future<void> _showBalanceSummaryDialog() async {
    if (_selectedShopCollection == null || _selectedShopCollection!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shop information not available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (pageContext) => BalanceDetailsScreen(
          shopCollection: _selectedShopCollection!,
          customerId: widget.customerId,
                                        ),
                                      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = _isLandscape(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1976D2), Color(0xFF4285F4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        title: GestureDetector(
          onTap: () => _showCustomerDetailsBottomSheet(context),
          child: Text(
            widget.customerName,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: isLandscape ? 18 : 20,
              letterSpacing: 0.3,
              color: Colors.white,
            ),
          ),
        ),
        actions: [
          FutureBuilder<Map<String, dynamic>>(
            future: _getCustomerData(),
                            builder: (context, snapshot) {
              final mobile = snapshot.data?['mobile'] ?? '';

              return IconButton(
                icon: Icon(Icons.phone, size: isLandscape ? 22 : 24),
                onPressed: () => _makePhoneCall(mobile, context),
                tooltip: mobile.isNotEmpty
                    ? 'Call $mobile'
                    : 'Phone number not available',
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.account_balance_wallet_outlined,
                size: isLandscape ? 22 : 24),
            tooltip: 'Balance details',
            onPressed: _showBalanceSummaryDialog,
          ),
          SizedBox(width: isLandscape ? 12 : 8),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, initSnapshot) {
          // Check if shop collection is properly initialized
          if (_selectedShopCollection == null ||
              _selectedShopCollection!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: isLandscape ? 56 : 64,
                    color: Colors.grey[400],
                  ),
                  SizedBox(height: isLandscape ? 12 : 16),
                  Text(
                    'Shop information not found',
                    style: TextStyle(
                      fontSize: isLandscape ? 16 : 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            );
          }

          return FutureBuilder<Map<String, dynamic>>(
            future: _getCustomerData(),
            builder: (context, customerSnapshot) {
              if (customerSnapshot.connectionState == ConnectionState.waiting) {
                return _buildProfessionalShimmer(isLandscape);
              }

              if (!customerSnapshot.hasData || customerSnapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: isLandscape ? 56 : 64,
                        color: Colors.grey[400],
                      ),
                      SizedBox(height: isLandscape ? 12 : 16),
                      Text(
                        'Customer not found',
                        style: TextStyle(
                          fontSize: isLandscape ? 16 : 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final customerData = customerSnapshot.data!;
              final openingAmount = customerData['openingAmount'] as double;
              final mobile = customerData['mobile'] as String;

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection(_selectedShopCollection!)
                    .doc('customers')
                    .collection('list')
                    .doc(widget.customerId)
                    .collection('transactions')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildProfessionalShimmer(isLandscape);
                  }

                  final transactions = snapshot.data?.docs ?? [];

                  // Calculate balance and per-transaction starting balances
                  // Payment IN = DEBIT (isCredit = false) → money received from customer → REDUCE balance (subtract)
                  // Payment OUT = CREDIT (isCredit = true) → money given to customer → INCREASE balance (add)
                  double balance = openingAmount;

                  // Build map of start balance per transaction (in chronological order)
                  final List<QueryDocumentSnapshot> chronologicalTx =
                      List<QueryDocumentSnapshot>.from(transactions.reversed);
                  final Map<String, double> startBalanceById = {};

                  for (final doc in chronologicalTx) {
                    final data = doc.data() as Map<String, dynamic>;
                    final amount = (data['amount'] ?? 0).toDouble();
                    final isCredit = data['isCredit'] ?? false;

                    // Balance before applying this transaction
                    startBalanceById[doc.id] = balance;

                    if (isCredit) {
                      balance += amount; // Payment OUT increases what customer owes
                    } else {
                      balance -= amount; // Payment IN reduces what customer owes
                    }
                  }

                  return Column(
                    children: [
                      // Customer Info Section
                      _buildCustomerInfoSection(
                        isLandscape,
                        balance,
                        mobile,
                        context,
                      ),

                      // Transactions List
                      Expanded(
                        child: transactions.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.receipt_long_outlined,
                                      size: isLandscape ? 56 : 64,
                                      color: Colors.grey[400],
                                    ),
                                    SizedBox(height: isLandscape ? 12 : 16),
                                    Text(
                                      'No transactions found',
                                      style: TextStyle(
                                        fontSize: isLandscape ? 16 : 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    SizedBox(height: isLandscape ? 6 : 8),
                                    Text(
                                      'Transactions will appear here',
                                      style: TextStyle(
                                        fontSize: isLandscape ? 13 : 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Container(
                                color: Colors.white,
                                child: ListView.builder(
                                  itemCount: transactions.length,
                                  itemBuilder: (context, index) {
                                    final doc = transactions[index];
                                    final data =
                                        doc.data() as Map<String, dynamic>;
                                    final String docId = doc.id;
                                    final startBalance =
                                        startBalanceById[docId] ??
                                            openingAmount;
                                    return _buildTransactionItem(
                                      data,
                                      startBalance,
                                      isLandscape,
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
      // 🔹 Floating Action Button with Loading State
      floatingActionButton: StreamBuilder<QuerySnapshot>(
        stream: _selectedShopCollection != null && _selectedShopCollection!.isNotEmpty
            ? FirebaseFirestore.instance
                .collection(_selectedShopCollection!)
                .doc('customers')
                .collection('list')
                .doc(widget.customerId)
                .collection('transactions')
                .orderBy('createdAt', descending: true)
                .snapshots()
            : Stream.empty(),
        builder: (context, snapshot) {
          final docs = snapshot.data?.docs ?? [];
          return FloatingActionButton(
            backgroundColor: const Color(0xFF4285F4),
            onPressed: _isDownloading ? null : () => _showDownloadDialog(docs),
            tooltip: 'Download Report',
            child: _isDownloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.download, color: Colors.white),
          );
        },
      ),
    );
  }
  }
