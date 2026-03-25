import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

class ExportCustomerPage extends StatefulWidget {
  const ExportCustomerPage({super.key});

  @override
  State<ExportCustomerPage> createState() => _ExportCustomerPageState();
}

class _ExportCustomerPageState extends State<ExportCustomerPage> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  String? _selectedCustomer;
  bool _isLoading = false;
  List<Map<String, dynamic>> _customers = [];
  String? _lastExportedFilePath;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('customers')
          .where('status', isEqualTo: 'Active')
          .get();

      final customerList = snapshot.docs.map((doc) {
        final data = doc.data();
        return {'id': doc.id, 'name': data['customerName'] ?? 'Unnamed'};
      }).toList();

      customerList.sort(
        (a, b) => (a['name'] as String).compareTo(b['name'] as String),
      );

      setState(() {
        _customers = [
          {'id': 'all', 'name': 'All Customers'},
          ...customerList,
        ];
        if (_selectedCustomer == null && _customers.isNotEmpty) {
          _selectedCustomer = _customers.first['name'];
        }
      });
    } catch (e) {
      debugPrint('Error loading customers: $e');
      setState(() {
        _customers = [
          {'id': 'all', 'name': 'All Customers'},
        ];
        _selectedCustomer = 'All Customers';
      });
    }
  }

  Future<void> _selectDate(BuildContext context, bool isFromDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isFromDate ? _fromDate : _toDate,
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
        if (isFromDate) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
    }
  }

  /// Generate PDF Report
  Future<String> _generatePDF(String reportType) async {
    final pdf = pw.Document();
    final dateRange =
        '${DateFormat('dd-MMM-yyyy').format(_fromDate)} to ${DateFormat('dd-MMM-yyyy').format(_toDate)}';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                color: PdfColors.blue700,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      reportType,
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Period: $dateRange',
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      'Customer: ${_selectedCustomer ?? "All Customers"}',
                      style: const pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      'Generated: ${DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now())}',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.white,
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // Content
              pw.Padding(
                padding: const pw.EdgeInsets.all(20),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Report Details',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Divider(),
                    pw.SizedBox(height: 12),

                    // Sample data table
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey400),
                      children: [
                        // Header
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.grey300,
                          ),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'Date',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'Description',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'Amount',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                textAlign: pw.TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                        // Sample rows
                        ...List.generate(5, (index) {
                          return pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  DateFormat('dd-MMM-yyyy').format(
                                    DateTime.now().subtract(
                                      Duration(days: index),
                                    ),
                                  ),
                                  style: const pw.TextStyle(fontSize: 11),
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  'Sample Transaction ${index + 1}',
                                  style: const pw.TextStyle(fontSize: 11),
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  '₹${(1000 * (index + 1)).toStringAsFixed(2)}',
                                  style: const pw.TextStyle(fontSize: 11),
                                  textAlign: pw.TextAlign.right,
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),

                    pw.SizedBox(height: 20),

                    // Summary
                    pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.blue50,
                        borderRadius: const pw.BorderRadius.all(
                          pw.Radius.circular(8),
                        ),
                      ),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Total:',
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            '₹15,000.00',
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              pw.Spacer(),

              // Footer
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                child: pw.Center(
                  child: pw.Text(
                    'This is a computer-generated document',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    // Save PDF
    final output = await getTemporaryDirectory();
    final fileName =
        '${reportType.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File('${output.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    return file.path;
  }

  /// Generate Excel (CSV format for simplicity)
  Future<String> _generateExcel(String reportType) async {
    final dateRange =
        '${DateFormat('dd-MMM-yyyy').format(_fromDate)} to ${DateFormat('dd-MMM-yyyy').format(_toDate)}';

    // CSV Content
    final csvContent = StringBuffer();
    csvContent.writeln('$reportType');
    csvContent.writeln('Period: $dateRange');
    csvContent.writeln('Customer: ${_selectedCustomer ?? "All Customers"}');
    csvContent.writeln(
      'Generated: ${DateFormat('dd-MMM-yyyy hh:mm a').format(DateTime.now())}',
    );
    csvContent.writeln('');
    csvContent.writeln('Date,Description,Amount');

    // Sample data
    for (int i = 0; i < 5; i++) {
      final date = DateFormat(
        'dd-MMM-yyyy',
      ).format(DateTime.now().subtract(Duration(days: i)));
      csvContent.writeln('$date,Sample Transaction ${i + 1},${1000 * (i + 1)}');
    }

    csvContent.writeln('');
    csvContent.writeln('Total,,15000');

    // Save Excel (CSV)
    final output = await getTemporaryDirectory();
    final fileName =
        '${reportType.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('${output.path}/$fileName');
    await file.writeAsString(csvContent.toString());

    return file.path;
  }

  /// Show success dialog with Open and Share options
  void _showExportSuccessDialog(String reportType, String format) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: Colors.green[600],
                  size: 48,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Export Successful!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),

              // Details
              Text(
                '$reportType exported as $format',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        if (_lastExportedFilePath != null) {
                          final result = await OpenFile.open(
                            _lastExportedFilePath,
                          );
                          if (result.type != ResultType.done) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Could not open file: ${result.message}',
                                  ),
                                  backgroundColor: Colors.orange[600],
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.open_in_new, size: 20),
                      label: const Text('Open'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFF4285F4)),
                        foregroundColor: const Color(0xFF4285F4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        if (_lastExportedFilePath != null) {
                          try {
                            final xFile = XFile(_lastExportedFilePath!);
                            await Share.shareXFiles([
                              xFile,
                            ], text: '$reportType - $format');
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Could not share file: $e'),
                                  backgroundColor: Colors.orange[600],
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.share, size: 20),
                      label: const Text('Share'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF4285F4),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Close Button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Close',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportReport(String reportType, String format) async {
    setState(() => _isLoading = true);

    try {
      String filePath;

      if (format == 'PDF') {
        filePath = await _generatePDF(reportType);
      } else {
        filePath = await _generateExcel(reportType);
      }

      setState(() {
        _isLoading = false;
        _lastExportedFilePath = filePath;
      });

      // Show success dialog with open/share options
      _showExportSuccessDialog(reportType, format);
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Failed to export: $e')),
            ],
          ),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  /// Build flat design export section
  Widget _buildExportSection({
    required IconData icon,
    required String title,
    required String description,
    required Color iconColor,
    required List<Map<String, dynamic>> exportOptions,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Export Buttons
          Row(
            children: exportOptions.map((option) {
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(
                    right: option == exportOptions.last ? 0 : 12,
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _exportReport(title, option['format']),
                    icon: Icon(option['icon'], size: 18),
                    label: Text(option['format']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: option['color'],
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      disabledForegroundColor: Colors.grey[500],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          // Divider
          const SizedBox(height: 20),
          Divider(height: 1, color: Colors.grey[200]),
        ],
      ),
    );
  }

  /// Build date selector - flat design
  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.date_range, color: Colors.blue[700], size: 22),
              const SizedBox(width: 10),
              Text(
                'Date Range',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectDate(context, true),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'From Date',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('dd MMM yyyy').format(_fromDate),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => _selectDate(context, false),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'To Date',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: Colors.blue[700],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('dd MMM yyyy').format(_toDate),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build customer selector - flat design
  Widget _buildCustomerSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, color: Colors.green[700], size: 22),
              const SizedBox(width: 10),
              Text(
                'Customer Selection',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Show loading or dropdown
          if (_customers.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Loading customers...', style: TextStyle(fontSize: 14)),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: DropdownButtonFormField<String>(
                value: _selectedCustomer,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
                hint: const Text('Select Customer'),
                items: _customers.map((customer) {
                  return DropdownMenuItem<String>(
                    value: customer['name'],
                    child: Text(
                      customer['name'],
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCustomer = value;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Export Reports',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Date Range Selector
              _buildDateSelector(),
              const SizedBox(height: 16),

              // Customer Selector
              _buildCustomerSelector(),
              const SizedBox(height: 28),

              // Export Options Header
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Export Options',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ),

              // Customer Statement
              _buildExportSection(
                icon: Icons.receipt_long,
                title: 'Customer Statement',
                description:
                    'Individual transaction history with opening and closing balance',
                iconColor: const Color(0xFF4285F4),
                exportOptions: [
                  {
                    'format': 'PDF',
                    'icon': Icons.picture_as_pdf,
                    'color': const Color(0xFFD32F2F),
                  },
                  {
                    'format': 'Excel',
                    'icon': Icons.table_chart,
                    'color': const Color(0xFF388E3C),
                  },
                ],
              ),

              // Outstanding Summary
              _buildExportSection(
                icon: Icons.analytics,
                title: 'Outstanding Summary',
                description:
                    'All customers with current outstanding amounts and status',
                iconColor: const Color(0xFFFF9800),
                exportOptions: [
                  {
                    'format': 'PDF',
                    'icon': Icons.picture_as_pdf,
                    'color': const Color(0xFFD32F2F),
                  },
                  {
                    'format': 'Excel',
                    'icon': Icons.table_chart,
                    'color': const Color(0xFF388E3C),
                  },
                ],
              ),

              // Collection Report
              _buildExportSection(
                icon: Icons.payment,
                title: 'Collection Report',
                description:
                    'Daily and monthly payment collections with totals',
                iconColor: const Color(0xFF4CAF50),
                exportOptions: [
                  {
                    'format': 'PDF',
                    'icon': Icons.picture_as_pdf,
                    'color': const Color(0xFFD32F2F),
                  },
                  {
                    'format': 'Excel',
                    'icon': Icons.table_chart,
                    'color': const Color(0xFF388E3C),
                  },
                ],
              ),

              const SizedBox(height: 12),

              // Info Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Export Tips',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue[900],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '• PDF for printing and sharing\n'
                            '• Excel for data analysis\n'
                            '• Date range applies to all reports\n'
                            '• Select specific or all customers',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[800],
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),

          // Loading Overlay
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.6),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF4285F4),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Generating Report',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please wait...',
                        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
