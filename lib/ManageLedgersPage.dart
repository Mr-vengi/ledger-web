import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Ledgerdetails.dart';

class ManageLedgersPage extends StatefulWidget {
  const ManageLedgersPage({super.key});

  @override
  State<ManageLedgersPage> createState() => _ManageLedgersPageState();
}

class _ManageLedgersPageState extends State<ManageLedgersPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String? _selectedShopCollection;
  String? _selectedShopName;
  List<Map<String, dynamic>> _shops = [];
  bool _isLoadingShops = true;
  String _searchQuery = '';
  String _selectedFilter = 'All'; // All, Open, Closed
  String _sortOrder = 'Newest'; // Newest, Oldest

  @override
  void initState() {
    super.initState();
    _initializeShops();
  }

  Future<void> _initializeShops() async {
    try {
      final snapshot = await _firestore.collection('shop_list').get();
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
        if (shopsList.isNotEmpty) {
          _selectedShopCollection = shopsList[0]['collectionName'];
          _selectedShopName = shopsList[0]['shopName'];
        }
        _isLoadingShops = false;
      });
    } catch (e) {
      debugPrint('Error fetching shops: $e');
      setState(() => _isLoadingShops = false);
    }
  }

  /// Get all ledgers stream for selected shop
  Stream<QuerySnapshot> _getLedgersStream() {
    if (_selectedShopCollection == null || _selectedShopCollection!.isEmpty) {
      return Stream.empty();
    }

    return _firestore
        .collection(_selectedShopCollection!)
        .doc('ledgers')
        .collection('dates')
        .orderBy('createdAt', descending: _sortOrder == 'Newest')
        .snapshots();
  }

  /// Filter and sort ledgers
  List<QueryDocumentSnapshot> _filterAndSortLedgers(
      List<QueryDocumentSnapshot> docs) {
    var filtered = docs.where((doc) {
      final ledger = doc.data() as Map<String, dynamic>;
      final ledgerDate = ledger['ledgerDate'] ?? '';
      final status = ledger['status'] ?? 'Open';

      // Apply search filter
      bool matchesSearch = _searchQuery.isEmpty ||
          ledgerDate.toLowerCase().contains(_searchQuery.toLowerCase());

      // Apply status filter
      bool matchesStatus = _selectedFilter == 'All' ||
          (_selectedFilter == 'Open' && status.toString().toLowerCase() == 'open') ||
          (_selectedFilter == 'Closed' && status.toString().toLowerCase() == 'closed');

      return matchesSearch && matchesStatus;
    }).toList();

    // Sort by date if needed
    if (_sortOrder == 'Oldest') {
      filtered.sort((a, b) {
        final aDate = a.data() as Map<String, dynamic>;
        final bDate = b.data() as Map<String, dynamic>;
        try {
          final aParsed = DateFormat('dd-MMM-yyyy').parse(aDate['ledgerDate'] ?? '');
          final bParsed = DateFormat('dd-MMM-yyyy').parse(bDate['ledgerDate'] ?? '');
          return aParsed.compareTo(bParsed);
        } catch (e) {
          return 0;
        }
      });
    }

    return filtered;
  }

  /// Delete ledger and all its transactions
  Future<void> _deleteLedger(
      QueryDocumentSnapshot ledgerDoc, String ledgerDate) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red[600], size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Delete Ledger',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to delete this ledger?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ledger Date: $ledgerDate',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.red[800],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '⚠️ This will permanently delete:',
                      style: TextStyle(fontSize: 13, color: Colors.red[700]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• The ledger entry\n• All transactions for this date',
                      style: TextStyle(fontSize: 12, color: Colors.red[600]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This action cannot be undone!',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.red[700],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(fontSize: 15, color: Colors.grey[700]),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // Show loading
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Delete all transactions for this ledger date
      final transactionsSnapshot = await _firestore
          .collection(_selectedShopCollection!)
          .doc('ledgers')
          .collection('transactions')
          .where('ledgerDate', isEqualTo: ledgerDate)
          .get();

      final batch = _firestore.batch();
      for (var doc in transactionsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // Delete the ledger document
      batch.delete(ledgerDoc.reference);

      await batch.commit();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white),
                const SizedBox(width: 12),
                Text('Ledger "$ledgerDate" deleted successfully'),
              ],
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting ledger: $e'),
            backgroundColor: Colors.red[600],
          ),
        );
      }
    }
  }

  /// Build shop selector
  Widget _buildShopSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.store, color: const Color(0xFF4285F4), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              value: _selectedShopCollection,
              isExpanded: true,
              underline: const SizedBox(),
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
              hint: const Text(
                'Select Shop',
                style: TextStyle(color: Colors.grey),
              ),
              items: _shops.map((shop) {
                return DropdownMenuItem<String>(
                  value: shop['collectionName'],
                  child: Text(
                    shop['shopName'],
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedShopCollection = value;
                  final shop = _shops.firstWhere(
                    (s) => s['collectionName'] == value,
                    orElse: () => {'shopName': 'Unknown'},
                  );
                  _selectedShopName = shop['shopName'];
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build search and filter bar
  Widget _buildSearchAndFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          // Search bar
          TextField(
            decoration: InputDecoration(
              hintText: 'Search by date...',
              filled: true,
              fillColor: Colors.grey[50],
              prefixIcon: const Icon(Icons.search, color: Color(0xFF4285F4)),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: Color(0xFF4285F4),
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 16,
              ),
            ),
            onChanged: (value) {
              setState(() => _searchQuery = value);
            },
          ),
          const SizedBox(height: 12),
          // Filter and sort row
          Row(
            children: [
              // Status filter
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedFilter,
                    isExpanded: true,
                    underline: const SizedBox(),
                    icon: Icon(Icons.filter_list, color: Colors.grey[600], size: 20),
                    items: ['All', 'Open', 'Closed'].map((filter) {
                      return DropdownMenuItem<String>(
                        value: filter,
                        child: Text(
                          filter,
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedFilter = value!);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Sort order
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: DropdownButton<String>(
                    value: _sortOrder,
                    isExpanded: true,
                    underline: const SizedBox(),
                    icon: Icon(Icons.sort, color: Colors.grey[600], size: 20),
                    items: ['Newest', 'Oldest'].map((order) {
                      return DropdownMenuItem<String>(
                        value: order,
                        child: Text(
                          order,
                          style: const TextStyle(fontSize: 14),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _sortOrder = value!);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build ledger item
  Widget _buildLedgerItem(QueryDocumentSnapshot doc) {
    final ledger = doc.data() as Map<String, dynamic>;
    final ledgerDate = ledger['ledgerDate'] ?? 'Unknown Date';
    final status = ledger['status'] ?? 'Open';
    final isClosed = status.toString().toLowerCase() == 'closed';
    final openingBalance = (ledger['openingBalance'] ?? 0).toDouble();
    final closingBalance = (ledger['closingBalance'] ?? 0).toDouble();
    final createdAt = ledger['createdAt'] as Timestamp?;

    final statusColor = isClosed ? Colors.red[600]! : Colors.green[600]!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main content
          InkWell(
            onTap: () {
              try {
                final date = DateFormat('dd-MMM-yyyy').parse(ledgerDate);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LedgerDetailsScreen(
                      date: date,
                      shopCollection: _selectedShopCollection,
                      shopName: _selectedShopName,
                    ),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error parsing date: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Date badge
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ledgerDate.split('-')[0], // Day
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                        Text(
                          ledgerDate.split('-')[1].toUpperCase(), // Month
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Ledger info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                ledgerDate,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Opening',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Text(
                                    '₹${NumberFormat('#,##,##0.00').format(openingBalance)}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Closing',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Text(
                                    '₹${NumberFormat('#,##,##0.00').format(closingBalance)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (createdAt != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Created: ${DateFormat('dd-MMM-yyyy HH:mm').format(createdAt.toDate())}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey[400],
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          // Delete button
          Divider(height: 1, thickness: 1, color: Colors.grey[200]),
          InkWell(
            onTap: () => _deleteLedger(doc, ledgerDate),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, color: Colors.red[600], size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Delete Ledger',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.red[600],
                    ),
                  ),
                ],
              ),
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
        title: const Text(
          'Manage Ledgers',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: _isLoadingShops
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Shop selector
                _buildShopSelector(),
                // Search and filter bar
                _buildSearchAndFilterBar(),
                // Ledgers list
                Expanded(
                  child: _selectedShopCollection == null ||
                          _selectedShopCollection!.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.store,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No shop selected',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        )
                      : StreamBuilder<QuerySnapshot>(
                          stream: _getLedgersStream(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (snapshot.hasError) {
                              return Center(
                                child: Text('Error: ${snapshot.error}'),
                              );
                            }

                            final docs = snapshot.data?.docs ?? [];
                            final filteredDocs = _filterAndSortLedgers(docs);

                            if (filteredDocs.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.description_outlined,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No ledgers found',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Try adjusting your filters',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: filteredDocs.length,
                              itemBuilder: (context, index) {
                                return _buildLedgerItem(filteredDocs[index]);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

