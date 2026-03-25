import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'dart:async';
import 'package:share_plus/share_plus.dart';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _selectedShopId;
  String _selectedShopName = '';
  List<Map<String, String>> _availableShops = [];

  // Analytics Data
  Map<String, dynamic> _ledgerStats = {};
  Map<String, dynamic> _customerStats = {};
  Map<String, dynamic> _transactionStats = {};
  List<Map<String, dynamic>> _recentTransactions = [];
  List<Map<String, dynamic>> _dailyBalances = [];
  List<Map<String, dynamic>> _topCustomers = [];

  // Bills Data
  List<Map<String, dynamic>> _allBills = [];
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  bool _isLoadingBills = false;
  bool _hasMoreBills = true;
  DocumentSnapshot? _lastBillDocument;
  static const int _billsPerPage = 50;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadAvailableShops();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableShops() async {
    try {
      setState(() => _isLoading = true);

      // Fetch shops from shop_list collection in Firestore
      final snapshot = await FirebaseFirestore.instance
          .collection('shop_list')
          .get();

      List<Map<String, String>> shops = [];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final collectionName = data['collectionName'] ?? '';

        // ✅ Fetch shop name from the actual shop collection's Credentials document
        try {
          final credentialsDoc = await FirebaseFirestore.instance
              .collection(collectionName)
              .doc('Credentials')
              .get();

          if (credentialsDoc.exists) {
            final credentialsData = credentialsDoc.data() ?? {};
            final actualShopName =
                credentialsData['shopName'] ?? 'Unknown Shop';

            shops.add({
              'id': collectionName,
              'name': actualShopName.toUpperCase(),
            });

            debugPrint('✅ Shop loaded: $collectionName → $actualShopName');
          } else {
            debugPrint('❌ No Credentials document for $collectionName');
          }
        } catch (e) {
          debugPrint('❌ Shop $collectionName not accessible: $e');
        }
      }

      setState(() {
        _availableShops = shops;
        if (shops.isNotEmpty) {
          _selectedShopId = shops.first['id'];
          _selectedShopName = shops.first['name']!;
        }
      });

      if (_selectedShopId != null) {
        _loadAnalyticsData();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading shops: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAnalyticsData() async {
    if (_selectedShopId == null) return;

    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadLedgerAnalytics(),
        _loadCustomerAnalytics(),
        _loadTransactionAnalytics(),
        _loadRecentTransactions(),
        _loadDailyBalances(),
        _loadBills(),
      ]);
    } catch (e) {
      debugPrint('Error loading analytics: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLedgerAnalytics() async {
    try {
      final now = DateTime.now();
      final thisMonth = DateTime(now.year, now.month, 1);
      final todayString = DateFormat('dd-MMM-yyyy').format(now);

      final datesSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShopId!)
          .doc('ledgers')
          .collection('dates')
          .orderBy('createdAt', descending: true)
          .get();

      double totalClosingBalance = 0;
      double todayBalance = 0;
      double totalOpeningBalance = 0;
      int totalDays = datesSnapshot.docs.length;
      int thisMonthDays = 0;
      double thisMonthBalance = 0;
      int openLedgers = 0;
      int closedLedgers = 0;

      for (var doc in datesSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final closingBalance = (data['closingBalance'] ?? 0).toDouble();
        final openingBalance = (data['openingBalance'] ?? 0).toDouble();
        final status = data['status'] ?? '';
        final ledgerDate = data['ledgerDate'] ?? '';

        totalClosingBalance += closingBalance;
        totalOpeningBalance += openingBalance;

        if (status == 'Open') openLedgers++;
        if (status == 'Closed') closedLedgers++;

        if (ledgerDate == todayString) {
          todayBalance = closingBalance;
        }

        try {
          final parsedDate = DateFormat('dd-MMM-yyyy').parse(ledgerDate);
          if (parsedDate.isAfter(thisMonth)) {
            thisMonthDays++;
            thisMonthBalance += closingBalance;
          }
        } catch (e) {
          debugPrint('Error parsing date: $ledgerDate');
        }
      }

      setState(() {
        _ledgerStats = {
          'currentBalance': todayBalance,
          'totalClosingBalance': totalClosingBalance,
          'totalOpeningBalance': totalOpeningBalance,
          'totalDays': totalDays,
          'thisMonthDays': thisMonthDays,
          'thisMonthBalance': thisMonthBalance,
          'avgDailyBalance': totalDays > 0
              ? totalClosingBalance / totalDays
              : 0.0,
          'profitLoss': totalClosingBalance - totalOpeningBalance,
          'openLedgers': openLedgers,
          'closedLedgers': closedLedgers,
        };
      });
    } catch (e) {
      debugPrint('Error loading ledger analytics: $e');
    }
  }

  Future<void> _loadCustomerAnalytics() async {
    try {
      final customerSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShopId!)
          .doc('customers')
          .collection('list')
          .where('status', isEqualTo: 'Active')
          .get();

      int totalCustomers = customerSnapshot.docs.length;
      int retailCustomers = 0;
      int wholesaleCustomers = 0;
      double totalOpeningAmount = 0;
      List<Map<String, dynamic>> customers = [];

      for (var doc in customerSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final customerType = data['customerType'] ?? '';
        final openingAmount = (data['openingAmount'] ?? 0).toDouble();
        final customerName = data['customerName'] ?? 'Unknown';

        totalOpeningAmount += openingAmount;

        if (customerType == 'Retail') retailCustomers++;
        if (customerType == 'Wholesale') wholesaleCustomers++;

        customers.add({
          'id': doc.id,
          'name': customerName,
          'type': customerType,
          'openingAmount': openingAmount,
          'mobile': data['mobile'] ?? '',
          'openingDate': data['openingDate'] ?? '',
        });
      }

      customers.sort(
            (a, b) => (b['openingAmount'] as double).compareTo(
          a['openingAmount'] as double,
        ),
      );

      setState(() {
        _customerStats = {
          'totalCustomers': totalCustomers,
          'retailCustomers': retailCustomers,
          'wholesaleCustomers': wholesaleCustomers,
          'totalOpeningAmount': totalOpeningAmount,
          'avgOpeningAmount': totalCustomers > 0
              ? totalOpeningAmount / totalCustomers
              : 0.0,
        };
        _topCustomers = customers.take(5).toList();
      });
    } catch (e) {
      debugPrint('Error loading customer analytics: $e');
    }
  }

  Future<void> _loadTransactionAnalytics() async {
    try {
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));

      final transactionSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShopId!)
          .doc('ledgers')
          .collection('transactions')
          .orderBy('createdAt', descending: true)
          .get();

      double totalCredit = 0;
      double totalDebit = 0;
      double monthCredit = 0;
      double monthDebit = 0;
      double weekCredit = 0;
      double weekDebit = 0;
      int totalTransactions = transactionSnapshot.docs.length;
      int monthTransactions = 0;
      int weekTransactions = 0;

      Map<String, int> transactionTypes = {};

      for (var doc in transactionSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final amount = (data['amount'] ?? 0).toDouble();
        final isCredit = data['isCredit'] ?? false;
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        final transactionType = data['transactionType'] ?? 'General';

        transactionTypes[transactionType] =
            (transactionTypes[transactionType] ?? 0) + 1;

        if (isCredit) {
          totalCredit += amount;
        } else {
          totalDebit += amount;
        }

        if (createdAt != null) {
          if (createdAt.isAfter(startOfMonth)) {
            monthTransactions++;
            if (isCredit) {
              monthCredit += amount;
            } else {
              monthDebit += amount;
            }
          }

          if (createdAt.isAfter(startOfWeek)) {
            weekTransactions++;
            if (isCredit) {
              weekCredit += amount;
            } else {
              weekDebit += amount;
            }
          }
        }
      }

      setState(() {
        _transactionStats = {
          'totalCredit': totalCredit,
          'totalDebit': totalDebit,
          'monthCredit': monthCredit,
          'monthDebit': monthDebit,
          'weekCredit': weekCredit,
          'weekDebit': weekDebit,
          'totalTransactions': totalTransactions,
          'monthTransactions': monthTransactions,
          'weekTransactions': weekTransactions,
          'netFlow': totalCredit - totalDebit,
          'monthNetFlow': monthCredit - monthDebit,
          'transactionTypes': transactionTypes,
        };
      });
    } catch (e) {
      debugPrint('Error loading transaction analytics: $e');
    }
  }

  Future<void> _loadRecentTransactions() async {
    try {
      final transactionSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShopId!)
          .doc('ledgers')
          .collection('transactions')
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      List<Map<String, dynamic>> transactions = [];

      for (var doc in transactionSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        transactions.add({
          'id': doc.id,
          'amount': data['amount'] ?? 0,
          'isCredit': data['isCredit'] ?? false,
          'transactionType': data['transactionType'] ?? 'General',
          'ledgerName': data['ledgerName'] ?? '',
          'description': data['description'] ?? '',
          'ledgerDate': data['ledgerDate'] ?? '',
          'createdAt': data['createdAt'],
        });
      }

      setState(() {
        _recentTransactions = transactions;
      });
    } catch (e) {
      debugPrint('Error loading recent transactions: $e');
    }
  }

  Future<void> _loadDailyBalances() async {
    try {
      final datesSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShopId!)
          .doc('ledgers')
          .collection('dates')
          .orderBy('createdAt', descending: true)
          .limit(7)
          .get();

      List<Map<String, dynamic>> balances = [];

      for (var doc in datesSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        balances.add({
          'date': data['ledgerDate'] ?? doc.id,
          'opening': data['openingBalance'] ?? 0,
          'closing': data['closingBalance'] ?? 0,
          'status': data['status'] ?? 'Open',
          'saleValue': data['saleValue'] ?? 0,
          'note': data['note'] ?? '',
          'createdBy': data['createdBy'] ?? '',
          'closedAt': data['closedAt'],
        });
      }

      setState(() {
        _dailyBalances = balances;
      });
    } catch (e) {
      debugPrint('Error loading daily balances: $e');
    }
  }

  Future<void> _loadBills({bool loadMore = false}) async {
    if (_selectedShopId == null) return;

    // Reset if not loading more
    if (!loadMore) {
      setState(() {
        _isLoadingBills = true;
        _allBills = [];
        _lastBillDocument = null;
        _hasMoreBills = true;
      });
    } else {
      setState(() => _isLoadingBills = true);
    }

    try {
      Query query = FirebaseFirestore.instance
          .collection(_selectedShopId!)
          .doc('ledgers')
          .collection('transactions')
          .where('billPhotoUrl', isNotEqualTo: null)
          .orderBy('createdAt', descending: true)
          .limit(_billsPerPage);

      // Apply pagination
      if (loadMore && _lastBillDocument != null) {
        query = query.startAfterDocument(_lastBillDocument!);
      }

      final snapshot = await query.get();

      List<Map<String, dynamic>> newBills = [];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final billPhotoUrl = data['billPhotoUrl'] as String?;

        if (billPhotoUrl != null && billPhotoUrl.isNotEmpty) {
          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

          // Apply date filter in memory
          bool shouldInclude = true;
          if (_selectedStartDate != null && createdAt != null) {
            if (createdAt.isBefore(DateTime(_selectedStartDate!.year,
                _selectedStartDate!.month, _selectedStartDate!.day))) {
              shouldInclude = false;
            }
          }
          if (shouldInclude && _selectedEndDate != null && createdAt != null) {
            if (createdAt.isAfter(DateTime(_selectedEndDate!.year,
                _selectedEndDate!.month, _selectedEndDate!.day, 23, 59, 59))) {
              shouldInclude = false;
            }
          }

          if (shouldInclude) {
            newBills.add({
              'id': doc.id,
              'billPhotoUrl': billPhotoUrl,
              'amount': data['amount'] ?? 0,
              'description': data['description'] ?? '',
              'ledgerName': data['ledgerName'] ?? '',
              'customerName': data['customerName'] ?? '',
              'transactionType': data['transactionType'] ?? 'General',
              'ledgerDate': data['ledgerDate'] ?? '',
              'createdAt': createdAt,
              'isCredit': data['isCredit'] ?? false,
            });
          }
        }
      }

      // Update last document for pagination
      if (snapshot.docs.isNotEmpty) {
        _lastBillDocument = snapshot.docs.last;
        _hasMoreBills = snapshot.docs.length == _billsPerPage;
      } else {
        _hasMoreBills = false;
      }

      setState(() {
        if (loadMore) {
          _allBills.addAll(newBills);
        } else {
          _allBills = newBills;
        }
      });
    } catch (e) {
      debugPrint('Error loading bills: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading bills: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() => _isLoadingBills = false);
    }
  }

  String _formatCurrency(double amount) {
    return '₹${NumberFormat('#,##,##0').format(amount.abs())}';
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1976D2)),
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<String>(
            value: _selectedShopId,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 14,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF1976D2),
                  width: 2,
                ),
              ),
              prefixIcon: Icon(Icons.store, color: Colors.grey[600], size: 20),
            ),
            items: _availableShops.map((shop) {
              return DropdownMenuItem<String>(
                value: shop['id'],
                child: Text(shop['name']!),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedShopId = value;
                  _selectedShopName = _availableShops.firstWhere(
                        (shop) => shop['id'] == value,
                  )['name']!;
                });
                _loadAnalyticsData();
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Current Balance',
          value: _formatCurrency((_ledgerStats['currentBalance'] ?? 0).toDouble()),
          subtitle: 'Latest ledger balance',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Total Profit/Loss',
          value: ((_ledgerStats['profitLoss'] ?? 0) as num).toDouble() >= 0
              ? '+${_formatCurrency(((_ledgerStats['profitLoss'] ?? 0) as num).toDouble())}'
              : '-${_formatCurrency(((_ledgerStats['profitLoss'] ?? 0) as num).toDouble().abs())}',
          subtitle: 'Total closing - opening balance',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Total Customers',
          value: '${_customerStats['totalCustomers'] ?? 0}',
          subtitle: 'Active customers',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Active Ledger Days',
          value: '${_ledgerStats['totalDays'] ?? 0}',
          subtitle:
          '${_ledgerStats['openLedgers'] ?? 0} open, ${_ledgerStats['closedLedgers'] ?? 0} closed',
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCustomersTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1976D2)),
      );
    }

    return ListView(
      children: [
        _buildMetricCard(
          label: 'Total Active Customers',
          value: '${_customerStats['totalCustomers'] ?? 0}',
          subtitle: 'Active customers in system',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Retail vs Wholesale',
          value:
          '${_customerStats['retailCustomers'] ?? 0} : ${_customerStats['wholesaleCustomers'] ?? 0}',
          subtitle: 'Retail to wholesale ratio',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Total Opening Amounts',
          value: _formatCurrency((_customerStats['totalOpeningAmount'] ?? 0).toDouble()),
          subtitle: 'Sum of all customer opening amounts',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Average Opening Amount',
          value: _formatCurrency((_customerStats['avgOpeningAmount'] ?? 0).toDouble()),
          subtitle: 'Per customer average',
        ),
        if (_topCustomers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Top Customers by Opening Amount',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ..._topCustomers.asMap().entries.map((entry) {
            final customer = entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: customer['type'] == 'Retail'
                          ? const Color(0xFF1976D2).withOpacity(0.1)
                          : const Color(0xFF388E3C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        customer['type'] == 'Retail'
                            ? Icons.person
                            : Icons.business,
                        color: customer['type'] == 'Retail'
                            ? const Color(0xFF1976D2)
                            : const Color(0xFF388E3C),
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer['name'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          customer['type'],
                          style: TextStyle(
                            fontSize: 12,
                            color: customer['type'] == 'Retail'
                                ? const Color(0xFF1976D2)
                                : const Color(0xFF388E3C),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatCurrency((customer['openingAmount'] as num).toDouble()),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTransactionsTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1976D2)),
      );
    }

    return ListView(
      children: [
        _buildMetricCard(
          label: 'This Month Credits',
          value: _formatCurrency((_transactionStats['monthCredit'] ?? 0).toDouble()),
          subtitle:
          '${_transactionStats['monthTransactions'] ?? 0} transactions',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'This Month Debits',
          value: _formatCurrency((_transactionStats['monthDebit'] ?? 0).toDouble()),
          subtitle: 'Monthly outflows',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Monthly Net Flow',
          value: ((_transactionStats['monthNetFlow'] ?? 0) as num).toDouble() >= 0
              ? '+${_formatCurrency(((_transactionStats['monthNetFlow'] ?? 0) as num).toDouble())}'
              : '-${_formatCurrency(((_transactionStats['monthNetFlow'] ?? 0) as num).toDouble().abs())}',
          subtitle: 'This month performance',
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Recent Transactions',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_recentTransactions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No transactions found',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ),
          )
        else
          ..._recentTransactions.asMap().entries.map((entry) {
            final transaction = entry.value;
            final isCredit = transaction['isCredit'] as bool;
            final amount = transaction['amount'] as num;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      // Payment IN = DEBIT (isCredit = false) = GREEN (money coming in)
                      // Payment OUT = CREDIT (isCredit = true) = RED (money going out)
                      color: isCredit
                          ? const Color(0xFFD32F2F).withOpacity(0.1)
                          : const Color(0xFF388E3C).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        // Payment IN (isCredit=false) = add icon, Payment OUT (isCredit=true) = remove icon
                        isCredit ? Icons.remove : Icons.add,
                        color: isCredit
                            ? const Color(0xFFD32F2F)
                            : const Color(0xFF388E3C),
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          transaction['ledgerName'] ?? 'Unknown',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          transaction['transactionType'] ?? 'General',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    // Payment IN (isCredit=false) = +, Payment OUT (isCredit=true) = -
                    '${isCredit ? '-' : '+'}${_formatCurrency(amount.toDouble())}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      // Payment IN = DEBIT (isCredit = false) = GREEN
                      // Payment OUT = CREDIT (isCredit = true) = RED
                      color: isCredit
                          ? const Color(0xFFD32F2F)
                          : const Color(0xFF388E3C),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPerformanceTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1976D2)),
      );
    }

    return ListView(
      children: [
        _buildMetricCard(
          label: 'Average Daily Balance',
          value: _formatCurrency((_ledgerStats['avgDailyBalance'] ?? 0).toDouble()),
          subtitle: 'Per day average closing balance',
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'This Month Activity',
          value: '${_ledgerStats['thisMonthDays'] ?? 0} Days',
          subtitle: _formatCurrency((_ledgerStats['thisMonthBalance'] ?? 0).toDouble()),
        ),
        const SizedBox(height: 8),
        _buildMetricCard(
          label: 'Transaction Types',
          value:
          '${(_transactionStats['transactionTypes'] as Map<String, int>?)?.length ?? 0}',
          subtitle: 'Different transaction categories',
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Recent Daily Balances',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_dailyBalances.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No balance data available',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ),
          )
        else
          ..._dailyBalances.asMap().entries.map((entry) {
            final balance = entry.value;
            final opening = balance['opening'] as num;
            final closing = balance['closing'] as num;
            final difference = closing - opening;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: balance['status'] == 'Closed'
                          ? const Color(0xFF388E3C).withOpacity(0.1)
                          : const Color(0xFFF57C00).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        balance['status'] == 'Closed'
                            ? Icons.check_circle
                            : Icons.schedule,
                        color: balance['status'] == 'Closed'
                            ? const Color(0xFF388E3C)
                            : const Color(0xFFF57C00),
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          balance['date'],
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Open: ${_formatCurrency(opening.toDouble())} • Close: ${_formatCurrency(closing.toDouble())}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    difference >= 0
                        ? '+${_formatCurrency(difference.toDouble())}'
                        : '-${_formatCurrency(difference.abs().toDouble())}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: difference >= 0
                          ? const Color(0xFF388E3C)
                          : const Color(0xFFD32F2F),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildBillsTab() {
    return Column(
      children: [
        // Date Filter Section
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.filter_alt, size: 20, color: Color(0xFF1976D2)),
                  const SizedBox(width: 8),
                  const Text(
                    'Filter by Date',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  if (_selectedStartDate != null || _selectedEndDate != null)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedStartDate = null;
                          _selectedEndDate = null;
                        });
                        _loadBills();
                      },
                      icon: const Icon(Icons.clear, size: 16),
                      label: const Text('Clear'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red[600],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedStartDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _selectedStartDate = date;
                          });
                          _loadBills();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                size: 18, color: Color(0xFF1976D2)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedStartDate != null
                                    ? DateFormat('dd-MMM-yyyy')
                                    .format(_selectedStartDate!)
                                    : 'Start Date',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _selectedStartDate != null
                                      ? Colors.black87
                                      : Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedEndDate ?? DateTime.now(),
                          firstDate: _selectedStartDate ?? DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setState(() {
                            _selectedEndDate = date;
                          });
                          _loadBills();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                size: 18, color: Color(0xFF1976D2)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedEndDate != null
                                    ? DateFormat('dd-MMM-yyyy')
                                    .format(_selectedEndDate!)
                                    : 'End Date',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _selectedEndDate != null
                                      ? Colors.black87
                                      : Colors.grey[600],
                                ),
                              ),
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
        ),
        // Bills Grid
        Expanded(
          child: _isLoadingBills
              ? const Center(
            child: CircularProgressIndicator(color: Color(0xFF1976D2)),
          )
              : _allBills.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long,
                    size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No bills found',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _selectedStartDate != null || _selectedEndDate != null
                      ? 'Try adjusting your date filter'
                      : 'Bills will appear here when transactions have photos',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
              : NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification scrollInfo) {
              if (!_isLoadingBills &&
                  _hasMoreBills &&
                  scrollInfo.metrics.pixels >=
                      scrollInfo.metrics.maxScrollExtent - 200) {
                // Load more when scrolled near bottom (200px threshold)
                _loadBills(loadMore: true);
              }
              return false;
            },
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: _allBills.length + (_hasMoreBills ? 1 : 0),
              itemBuilder: (context, index) {
                // Show loading indicator at the end if more bills available
                if (index == _allBills.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(
                        color: Color(0xFF1976D2),
                      ),
                    ),
                  );
                }
                final bill = _allBills[index];
                return _buildBillCard(bill);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBillCard(Map<String, dynamic> bill) {
    final amount = (bill['amount'] ?? 0).toDouble();
    final isCredit = bill['isCredit'] ?? false;
    final createdAt = bill['createdAt'] as DateTime?;
    final ledgerName = bill['ledgerName'] ?? 'Unknown';
    final description = bill['description'] ?? '';

    return InkWell(
      onTap: () => _showBillViewer(bill),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Bill Image Preview
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: Image.network(
                    bill['billPhotoUrl'] as String,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        child: const Center(
                          child: Icon(Icons.broken_image,
                              size: 40, color: Colors.grey),
                        ),
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey[100],
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                loadingProgress.expectedTotalBytes!
                                : null,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            // Bill Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ledgerName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatCurrency(amount),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          // Payment IN = DEBIT (isCredit = false) = GREEN
                          // Payment OUT = CREDIT (isCredit = true) = RED
                          color: isCredit
                              ? const Color(0xFFD32F2F)
                              : const Color(0xFF388E3C),
                        ),
                      ),
                      if (createdAt != null)
                        Text(
                          DateFormat('dd MMM').format(createdAt),
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBillViewer(Map<String, dynamic> bill) {
    final billPhotoUrl = bill['billPhotoUrl'] as String;
    final ledgerName = bill['ledgerName'] ?? 'Unknown';
    final amount = (bill['amount'] ?? 0).toDouble();
    final createdAt = bill['createdAt'] as DateTime?;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BillViewerBottomSheet(
        billPhotoUrl: billPhotoUrl,
        transactionTitle: ledgerName,
        amount: amount,
        createdAt: createdAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analytics Dashboard',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalyticsData,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            color: const Color(0xFF1976D2),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Tab(text: 'OVERVIEW'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Tab(text: 'CUSTOMERS'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Tab(text: 'TRANSACTIONS'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Tab(text: 'PERFORMANCE'),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Tab(text: 'BILLS'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(),
          _buildCustomersTab(),
          _buildTransactionsTab(),
          _buildPerformanceTab(),
          _buildBillsTab(),
        ],
      ),
    );
  }
}

// Bill Viewer Bottom Sheet
class BillViewerBottomSheet extends StatefulWidget {
  final String billPhotoUrl;
  final String transactionTitle;
  final double amount;
  final DateTime? createdAt;

  const BillViewerBottomSheet({
    super.key,
    required this.billPhotoUrl,
    required this.transactionTitle,
    required this.amount,
    this.createdAt,
  });

  @override
  State<BillViewerBottomSheet> createState() => _BillViewerBottomSheetState();
}

class _BillViewerBottomSheetState extends State<BillViewerBottomSheet> {
  final TransformationController _transformationController =
  TransformationController();
  bool _isDownloading = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _downloadBill() async {
    setState(() => _isDownloading = true);

    try {
      final response = await http.get(Uri.parse(widget.billPhotoUrl));
      if (response.statusCode == 200) {
        final Uint8List imageBytes = response.bodyBytes;

        // Create blob and trigger download
        final blob = html.Blob([imageBytes], 'image/jpeg');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', 'bill_${DateTime.now().millisecondsSinceEpoch}.jpg')
          ..click();
        html.Url.revokeObjectUrl(url);

        setState(() => _isDownloading = false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bill downloaded successfully'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        throw Exception('Failed to download image');
      }
    } catch (e) {
      setState(() => _isDownloading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading bill: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareBill() async {
    setState(() => _isDownloading = true);

    try {
      final response = await http.get(Uri.parse(widget.billPhotoUrl));
      if (response.statusCode == 200) {
        final Uint8List imageBytes = response.bodyBytes;

        // Create a blob for sharing
        final blob = html.Blob([imageBytes], 'image/jpeg');

        // Check if Web Share API is available
        if (html.window.navigator.share != null) {
          try {
            // Create a File object
            final file = html.File([blob], 'bill_${widget.transactionTitle.replaceAll(' ', '_')}.jpg',
                {'type': 'image/jpeg'});

            // For sharing files, we need to use the share method with files property
            await html.window.navigator.share({
              'title': 'Bill',
              'text': 'Bill for ${widget.transactionTitle}',
              'files': [file]
            });

            setState(() => _isDownloading = false);

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Bill shared successfully'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            }
            return;
          } catch (e) {
            debugPrint('Web Share API with files failed: $e');
            // Fall through to download method
          }
        }

        // Fallback: Download the file
        _downloadBill();

        setState(() => _isDownloading = false);
      } else {
        throw Exception('Failed to download image');
      }
    } catch (e) {
      setState(() => _isDownloading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing bill: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.transactionTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.createdAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('dd MMM yyyy, hh:mm a')
                                .format(widget.createdAt!),
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Image Viewer
            Expanded(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    widget.billPhotoUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image,
                                size: 64, color: Colors.white54),
                            SizedBox(height: 16),
                            Text(
                              'Failed to load image',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            // Action Buttons
            SafeArea(
              top: false,
              child: Container(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: 16 + MediaQuery.of(context).padding.bottom,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  border: Border(
                    top: BorderSide(color: Colors.grey[800]!, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isDownloading ? null : _downloadBill,
                        icon: _isDownloading
                            ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                            : const Icon(Icons.download, size: 18),
                        label: const Text('Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1976D2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isDownloading ? null : _shareBill,
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Share'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}