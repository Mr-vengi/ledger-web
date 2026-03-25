import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Createledger.dart';
import 'widgets/AppBottomBar.dart';
import 'Ledgerdetails.dart';

class LedgerListScreen extends StatefulWidget {
  const LedgerListScreen({super.key});
  @override
  State<LedgerListScreen> createState() => _LedgerListScreenState();
}

class _LedgerListScreenState extends State<LedgerListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isChecking = false;
  bool _isSearchExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';
  DateTimeRange? _customDateRange;
  int? _selectedMonth;
  int? _selectedYear;

  // User & Shop related
  String? _userRole;
  String? _userShop;
  String? _userShopCollection;
  List<Map<String, dynamic>> _shops = [];
  String? _selectedShopCollection;
  String? _selectedShopName;
  bool _isLoadingShops = true;

  @override
  void initState() {
    super.initState();
    _initializeUserAndShops();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Initialize user role and fetch shops
  Future<void> _initializeUserAndShops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginType = prefs.getString('loginType');
      final shopName = prefs.getString('shopName');
      final shopCollection = prefs.getString('shopCollection');

      setState(() {
        _userRole = loginType;
        _userShop = shopName;
        _userShopCollection = shopCollection;
      });

      // For client, fetch all shops
      if (loginType == 'client') {
        await _fetchAllShops();

        // ✅ IMPORTANT: After fetching shops, check if there's a saved selected shop
        final savedSelectedShop = prefs.getString('selectedShopCollection');
        final savedSelectedShopName = prefs.getString('selectedShopName');

        if (savedSelectedShop != null && savedSelectedShop.isNotEmpty) {
          // Use the saved selected shop instead of resetting to first
          setState(() {
            _selectedShopCollection = savedSelectedShop;
            _selectedShopName = savedSelectedShopName;
          });
          debugPrint(
            'Restored saved shop: $_selectedShopCollection - $_selectedShopName',
          );
        }
      } else if (loginType == 'employee') {
        // For employee, set their shop
        setState(() {
          _selectedShopCollection = shopCollection;
          _selectedShopName = shopName;
          _isLoadingShops = false;
        });
      }
    } catch (e) {
      debugPrint('Error initializing: $e');
      setState(() => _isLoadingShops = false);
    }
  }

  /// Fetch all shops for admin
  Future<void> _fetchAllShops() async {
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
        // DON'T auto-select first shop if we already have a saved selection
        // Only set it if _selectedShopCollection is null
        if (_selectedShopCollection == null && shopsList.isNotEmpty) {
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

  /// ✅ CHECK FOR OPEN LEDGERS BEFORE CREATING NEW ONE - FIXED QUERY
  Future<void> _checkAndNavigateToCreateLedger() async {
    if (_selectedShopCollection == null || _selectedShopCollection!.isEmpty) {
      _showErrorDialog(
        'No Shop Selected',
        'Please select a shop first before creating a ledger.',
      );
      return;
    }

    setState(() => _isChecking = true);

    try {
      // ✅ SIMPLIFIED QUERY - Remove orderBy to avoid index requirement
      final openLedgersQuery = await _firestore
          .collection(_selectedShopCollection!)
          .doc('ledgers')
          .collection('dates')
          .where('status', isEqualTo: 'Open')
          .get(); // ✅ Removed .orderBy and .limit to avoid index issues

      setState(() => _isChecking = false);

      if (openLedgersQuery.docs.isNotEmpty) {
        // Found open ledger(s) - get the first one
        final openLedger = openLedgersQuery.docs.first.data();
        final openLedgerDate = openLedger['ledgerDate'] ?? 'Unknown Date';

        debugPrint('Found open ledger: $openLedgerDate');
        _showOpenLedgerWarningDialog(openLedgerDate);
      } else {
        // No open ledgers found - allow creation
        debugPrint('No open ledgers found - allowing creation');
        _navigateToCreateLedger();
      }
    } catch (e) {
      setState(() => _isChecking = false);
      debugPrint('Error checking open ledgers: $e');

      // ✅ Try alternative check method
      await _alternativeOpenLedgerCheck();
    }
  }

  /// ✅ ALTERNATIVE CHECK METHOD - Stream-based approach
  Future<void> _alternativeOpenLedgerCheck() async {
    try {
      debugPrint('Trying alternative check method...');

      // Get all ledgers and check status manually
      final allLedgersQuery = await _firestore
          .collection(_selectedShopCollection!)
          .doc('ledgers')
          .collection('dates')
          .get();

      // Find open ledgers manually
      String? openLedgerDate;
      for (var doc in allLedgersQuery.docs) {
        final data = doc.data();
        final status = data['status']?.toString() ?? 'Open';
        if (status.toLowerCase() == 'open') {
          openLedgerDate = data['ledgerDate']?.toString();
          break;
        }
      }

      if (openLedgerDate != null) {
        debugPrint('Alternative check found open ledger: $openLedgerDate');
        _showOpenLedgerWarningDialog(openLedgerDate);
      } else {
        debugPrint('Alternative check - no open ledgers found');
        _navigateToCreateLedger();
      }
    } catch (e) {
      debugPrint('Alternative check also failed: $e');

      // ✅ Final fallback - show user-friendly message but allow creation
      _showFallbackDialog();
    }
  }

  /// ✅ SHOW FALLBACK DIALOG WHEN ALL CHECKS FAIL
  void _showFallbackDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[600], size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Unable to Check',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: const Text(
            'Cannot check for open ledgers due to network issues. '
            'Please ensure you close any open ledgers before creating a new one.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(fontSize: 15, color: Colors.grey[700]),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToCreateLedger();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Continue Anyway',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  /// ✅ SHOW WARNING DIALOG WHEN OPEN LEDGER EXISTS - SIMPLE DESIGN
  void _showOpenLedgerWarningDialog(String openLedgerDate) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange[600],
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'Open Ledger Found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You have an open ledger for:',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Text(
                  openLedgerDate,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Colors.orange[800],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Please close this ledger before creating a new one.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToOpenLedger(openLedgerDate);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[600],
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Go to Ledger',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  /// ✅ NAVIGATE TO OPEN LEDGER
  void _navigateToOpenLedger(String ledgerDate) {
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
      debugPrint('Error parsing date: $e');
      _showErrorDialog('Error', 'Failed to navigate to the open ledger.');
    }
  }

  /// ✅ NAVIGATE TO CREATE LEDGER (ONLY WHEN NO OPEN LEDGERS)
  void _navigateToCreateLedger() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateLedgerScreen()),
    ).then((_) {
      // Refresh the list when coming back
      setState(() {});
    });
  }

  /// ✅ SHOW ERROR DIALOG
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red[600], size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          content: Text(message, style: const TextStyle(fontSize: 15)),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Check if device is in landscape mode
  bool _isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  /// Handle pull to refresh
  Future<void> _handleRefresh() async {
    setState(() {});
  }

  /// Get ledger stream for selected shop
  Stream<QuerySnapshot> _getLedgersStream() {
    if (_selectedShopCollection == null || _selectedShopCollection!.isEmpty) {
      return Stream.empty();
    }

    // For employees: Show only last 10 days
    // For admin (client): Show all dates
    if (_userRole == 'employee') {
      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
      final tenDaysAgoTimestamp = Timestamp.fromDate(tenDaysAgo);
      
      return _firestore
          .collection(_selectedShopCollection!)
          .doc('ledgers')
          .collection('dates')
          .where('createdAt', isGreaterThanOrEqualTo: tenDaysAgoTimestamp)
          .orderBy('createdAt', descending: true)
          .snapshots();
    }

    // Admin: Show all dates
    return _firestore
        .collection(_selectedShopCollection!)
        .doc('ledgers')
        .collection('dates')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Filter ledgers based on search query and date filter
  List<QueryDocumentSnapshot> _filterLedgers(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final ledger = doc.data() as Map<String, dynamic>;
      final ledgerDate = ledger['ledgerDate'] ?? '';
      // Apply search filter
      bool matchesSearch =
          _searchQuery.isEmpty ||
          ledgerDate.toLowerCase().contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;
      // Apply date filter
      if (_selectedFilter == 'All') return true;
      try {
        final date = DateFormat('dd-MMM-yyyy').parse(ledgerDate);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        switch (_selectedFilter) {
          case 'This Week':
            final startOfWeek = today.subtract(
              Duration(days: today.weekday - 1),
            );
            return date.isAfter(startOfWeek.subtract(const Duration(days: 1)));
          case 'This Month':
            final startOfMonth = DateTime(now.year, now.month, 1);
            return date.isAfter(startOfMonth.subtract(const Duration(days: 1)));
          case 'Last Quarter':
            final currentQuarter = ((now.month - 1) ~/ 3);
            final lastQuarterMonth = currentQuarter * 3 - 2;
            final quarterStart = lastQuarterMonth > 0
                ? DateTime(now.year, lastQuarterMonth, 1)
                : DateTime(now.year - 1, 10, 1);
            final quarterEnd = lastQuarterMonth > 0
                ? DateTime(now.year, lastQuarterMonth + 3, 0)
                : DateTime(now.year, 1, 0);
            return (date.isAtSameMomentAs(quarterStart) ||
                    date.isAfter(quarterStart)) &&
                (date.isAtSameMomentAs(quarterEnd) ||
                    date.isBefore(quarterEnd.add(const Duration(days: 1))));
          case 'This Year':
            final startOfYear = DateTime(now.year, 1, 1);
            return date.isAfter(startOfYear.subtract(const Duration(days: 1)));
          case 'Specific Month':
            if (_selectedMonth == null || _selectedYear == null) return true;
            return date.year == _selectedYear && date.month == _selectedMonth;
          case 'Custom':
            if (_customDateRange == null) return true;
            final startDate = DateTime(
              _customDateRange!.start.year,
              _customDateRange!.start.month,
              _customDateRange!.start.day,
            );
            final endDate = DateTime(
              _customDateRange!.end.year,
              _customDateRange!.end.month,
              _customDateRange!.end.day,
            );
            return (date.isAtSameMomentAs(startDate) ||
                    date.isAfter(startDate)) &&
                (date.isAtSameMomentAs(endDate) || date.isBefore(endDate));
          default:
            return true;
        }
      } catch (e) {
        debugPrint("Error parsing date: $e");
        return false;
      }
    }).toList();
  }

  /// Show month picker
  Future<void> _showMonthYearPicker() async {
    final now = DateTime.now();
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        int tempMonth = _selectedMonth ?? now.month;
        int tempYear = _selectedYear ?? now.year;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Select Month & Year',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 300,
                height: 300,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () {
                            setDialogState(() {
                              tempYear--;
                            });
                          },
                        ),
                        Text(
                          tempYear.toString(),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () {
                            setDialogState(() {
                              tempYear++;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 2,
                            ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          final month = index + 1;
                          final monthName = DateFormat(
                            'MMM',
                          ).format(DateTime(2000, month));
                          final isSelected = tempMonth == month;
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                tempMonth = month;
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF4285F4)
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                monthName,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedMonth = tempMonth;
                      _selectedYear = tempYear;
                      _selectedFilter = 'Specific Month';
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Show custom date range picker
  Future<void> _showCustomDatePicker() async {
    final now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange:
          _customDateRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF4285F4),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedFilter = 'Custom';
      });
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (!_isSearchExpanded) {
        _searchController.clear();
        _searchQuery = '';
      }
    });
  }

  /// Build shop selector dropdown for admin
  Widget _buildShopSelector(bool isLandscape) {
    if (_userRole == 'employee') {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(isLandscape ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200] ?? Colors.grey),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.store,
            color: const Color(0xFF4285F4),
            size: isLandscape ? 18 : 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              value: _selectedShopCollection,
              isExpanded: true,
              underline: const SizedBox(),
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
              hint: Text(
                'Select Shop',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: isLandscape ? 14 : 15,
                ),
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
              onChanged: (value) async {
                if (value != null) {
                  setState(() {
                    _selectedShopCollection = value;
                    final shop = _shops.firstWhere(
                      (s) => s['collectionName'] == value,
                      orElse: () => {'shopName': 'Unknown'},
                    );
                    _selectedShopName = shop['shopName'];
                  });

                  // ✅ SAVE selected shop to SharedPreferences
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('selectedShopCollection', value);
                  await prefs.setString(
                    'selectedShopName',
                    _selectedShopName ?? '',
                  );
                  debugPrint('Shop selected and saved: $value');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build employee shop display
  Widget _buildEmployeeShopDisplay(bool isLandscape) {
    return Container(
      padding: EdgeInsets.all(isLandscape ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border(bottom: BorderSide(color: Colors.blue[200]!)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.store,
            color: Colors.blue[700],
            size: isLandscape ? 18 : 20,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Shop',
                style: TextStyle(
                  fontSize: isLandscape ? 12 : 13,
                  color: Colors.blue[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _userShop ?? 'Unknown Shop',
                style: TextStyle(
                  fontSize: isLandscape ? 15 : 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[900],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build search panel
  Widget _buildSearchPanel(bool isLandscape) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _isSearchExpanded ? (isLandscape ? 70 : 80) : 0,
      curve: Curves.easeInOut,
      child: _isSearchExpanded
          ? Container(
              padding: EdgeInsets.symmetric(
                horizontal: isLandscape ? 24.0 : 16.0,
                vertical: isLandscape ? 8.0 : 16.0,
              ),
              color: Colors.white,
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search by date...',
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(
                    Icons.search,
                    color: Color(0xFF4285F4),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
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
                      color: Color(0xFF4285F4),
                      width: 1.5,
                    ),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    vertical: isLandscape ? 10 : 12,
                    horizontal: 16,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  /// Build filter bar
  Widget _buildFilterBar(bool isLandscape) {
    return Container(
      height: isLandscape ? 50 : 56,
      padding: EdgeInsets.symmetric(vertical: isLandscape ? 6 : 8),
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: isLandscape ? 24 : 16),
        children: [
          _buildFilterChip('All'),
          const SizedBox(width: 8),
          _buildFilterChip('This Week'),
          const SizedBox(width: 8),
          _buildFilterChip('This Month'),
          const SizedBox(width: 8),
          _buildFilterChip('Last Quarter'),
          const SizedBox(width: 8),
          _buildFilterChip('This Year'),
          const SizedBox(width: 8),
          _buildSpecificMonthChip(),
          const SizedBox(width: 8),
          _buildCustomFilterChip(),
        ],
      ),
    );
  }

  /// Build filter chip
  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
          if (label != 'Custom' && label != 'Specific Month') {
            _customDateRange = null;
            _selectedMonth = null;
            _selectedYear = null;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? const Color(0xFF4285F4) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF4285F4) : Colors.grey[700],
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  /// Build specific month chip
  Widget _buildSpecificMonthChip() {
    final isSelected = _selectedFilter == 'Specific Month';
    final label = isSelected && _selectedMonth != null && _selectedYear != null
        ? '${DateFormat('MMM').format(DateTime(2000, _selectedMonth!))} $_selectedYear'
        : 'Specific Month';
    return GestureDetector(
      onTap: _showMonthYearPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? const Color(0xFF4285F4) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF4285F4) : Colors.grey[700],
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  /// Build custom filter chip
  Widget _buildCustomFilterChip() {
    final isSelected = _selectedFilter == 'Custom';
    final label = isSelected && _customDateRange != null
        ? '${DateFormat('MMM d').format(_customDateRange!.start)} - ${DateFormat('MMM d').format(_customDateRange!.end)}'
        : 'Custom Range';
    return GestureDetector(
      onTap: _showCustomDatePicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? const Color(0xFF4285F4) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF4285F4) : Colors.grey[700],
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  /// Build loading shimmer
  Widget _buildLoadingShimmer(bool isLandscape) {
    return ListView.builder(
      itemCount: 10,
      padding: EdgeInsets.symmetric(horizontal: isLandscape ? 24 : 0),
      itemBuilder: (context, index) {
        return Column(
          children: [
            Container(
              margin: EdgeInsets.symmetric(
                horizontal: isLandscape ? 0 : 16,
                vertical: isLandscape ? 8 : 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: isLandscape ? 44 : 48,
                    height: isLandscape ? 44 : 48,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  SizedBox(width: isLandscape ? 12 : 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 16,
                          width: isLandscape ? 160 : 140,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 14,
                          width: 80,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    height: 16,
                    width: isLandscape ? 120 : 100,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              indent: isLandscape ? 80 : 78,
              endIndent: isLandscape ? 24 : 16,
              color: Colors.grey[300],
            ),
          ],
        );
      },
    );
  }

  /// Calculate balance difference using the EXACT same formula as PDF export
  /// Formula: Balance Difference = Grand Total Credit - Grand Total Debit
  /// Where:
  /// - Grand Total Debit = Opening Balance + Transactions (Payment IN) + Sales Value
  /// - Grand Total Credit = Transactions (Payment OUT) + Cash Out + Closing Balance
  Future<double> _calculateBalanceDifference(
    String ledgerDate,
    Map<String, dynamic> ledger,
  ) async {
    if (_selectedShopCollection == null || _selectedShopCollection!.isEmpty) {
      return 0.0;
    }

    try {
      final openingBalance = (ledger['openingBalance'] ?? 0).toDouble();
      final closingBalance = (ledger['closingBalance'] ?? 0).toDouble();
      final saleValue = (ledger['saleValue'] ?? 0).toDouble();
      final cashOut = (ledger['cashOut'] ?? 0).toDouble(); // ✅ ADD CASH OUT
      final isLedgerClosed = (ledger['status'] ?? 'Open').toString().toLowerCase() == 'closed';

      // Get all transactions for this ledger date
      final transactionsSnapshot = await _firestore
          .collection(_selectedShopCollection!)
          .doc('ledgers')
          .collection('transactions')
          .where('ledgerDate', isEqualTo: ledgerDate)
          .get();

      // ✅ Calculate total debit and credit from transactions (EXACT MATCH TO PDF)
      // Start with opening balance in debit
      double totalDebit = openingBalance;
      double totalCredit = 0.0;

      for (var doc in transactionsSnapshot.docs) {
        final data = doc.data();
        final amount = (data['amount'] ?? 0).toDouble();
        final isCredit = data['isCredit'] == true;

        // Payment IN = DEBIT (isCredit = false) → amount in debit
        // Payment OUT = CREDIT (isCredit = true) → amount in credit
        if (isCredit) {
          totalCredit += amount;
        } else {
          totalDebit += amount;
        }
      }

      // ✅ Add sales value if ledger is closed (EXACT MATCH TO PDF)
      final finalSaleValue = isLedgerClosed ? saleValue : 0.0;
      if (finalSaleValue > 0) {
        totalDebit += finalSaleValue;
      }

      // ✅ Add cash out if ledger is closed (EXACT MATCH TO PDF)
      final finalCashOut = isLedgerClosed ? cashOut : 0.0;
      if (finalCashOut > 0) {
        totalCredit += finalCashOut;
      }

      // ✅ Add closing balance to credit (0 if not closed) (EXACT MATCH TO PDF)
      final finalClosingBalance = isLedgerClosed ? closingBalance : 0.0;
      
      // ✅ Grand Total Credit = Total Credit (includes cash out) + Closing Balance
      // This matches the PDF export formula exactly
      final grandTotalCredit = totalCredit + finalClosingBalance;

      // ✅ Calculate balance difference: Grand Total Credit - Grand Total Debit
      // This matches the PDF export formula exactly
      final balanceDifference = grandTotalCredit - totalDebit;

      return balanceDifference;
    } catch (e) {
      debugPrint('Error calculating balance difference: $e');
      return 0.0;
    }
  }

  /// Show confirmation dialog and delete ledger + all its transactions (ADMIN only)
  Future<void> _showDeleteLedgerDialog(
    BuildContext context,
    String ledgerDate,
  ) async {
    if (_selectedShopCollection == null || _selectedShopCollection!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a shop first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Delete ledger?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            'Ledger date: $ledgerDate\n\nThis will delete this ledger and all its transactions permanently.',
            style: const TextStyle(
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'Cancel',
                style: TextStyle(fontSize: 14),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    // Show loading overlay
    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      // Find the ledger document by ledgerDate (safest, in case docId differs)
      final ledgerQuery = await _firestore
          .collection(_selectedShopCollection!)
          .doc('ledgers')
          .collection('dates')
          .where('ledgerDate', isEqualTo: ledgerDate)
          .limit(1)
          .get();

      final batch = _firestore.batch();

      if (ledgerQuery.docs.isNotEmpty) {
        final ledgerDoc = ledgerQuery.docs.first;
        batch.delete(ledgerDoc.reference);
      }

      // Delete all transactions for this ledger date
      final transactionsSnapshot = await _firestore
          .collection(_selectedShopCollection!)
          .doc('ledgers')
          .collection('transactions')
          .where('ledgerDate', isEqualTo: ledgerDate)
          .get();

      for (var doc in transactionsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ledger $ledgerDate deleted successfully'),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
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

  /// Build ledger item - PASS SHOP COLLECTION TO DETAILS
  /// Build ledger item - FIXED: Pass shop collection correctly
  Widget _buildLedgerItem(
    BuildContext context,
    Map<String, dynamic> ledger,
    bool isLandscape,
  ) {
    final ledgerDate = ledger['ledgerDate'] ?? 'Unknown Date';
    final status = ledger['status'] ?? 'Open';
    final isClosed = status == 'Closed';
    final isToday =
        ledgerDate == DateFormat('dd-MMM-yyyy').format(DateTime.now());
    final statusColor = isClosed
        ? Colors.red[600]
        : (isToday ? const Color(0xFF4285F4) : Colors.green[600]);

    // Debug: Print values being passed
    debugPrint(
      'Passing shop: $_selectedShopCollection, name: $_selectedShopName',
    );

    return Column(
      children: [
        InkWell(
          onTap: () {
            // Ensure shop collection is not null before navigating
            if (_selectedShopCollection == null ||
                _selectedShopCollection!.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please select a shop first'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LedgerDetailsScreen(
                  date: DateFormat('dd-MMM-yyyy').parse(ledgerDate),
                  shopCollection: _selectedShopCollection,
                  shopName: _selectedShopName,
                ),
              ),
            );
          },
          // Long press: admin-only delete ledger (ledger + all transactions)
          onLongPress: () {
            // Only admin (client login) can delete ledgers
            if (_userRole?.toLowerCase() != 'client') {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Only admin can delete ledgers'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }

            _showDeleteLedgerDialog(context, ledgerDate);
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 24.0 : 16.0,
              vertical: isLandscape ? 10.0 : 14.0,
            ),
            child: Row(
              children: [
                Container(
                  width: isLandscape ? 44 : 48,
                  height: isLandscape ? 44 : 48,
                  decoration: BoxDecoration(
                    color: statusColor?.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat(
                          'dd',
                        ).format(DateFormat('dd-MMM-yyyy').parse(ledgerDate)),
                        style: TextStyle(
                          fontSize: isLandscape ? 16 : 18,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      Text(
                        DateFormat('MMM')
                            .format(DateFormat('dd-MMM-yyyy').parse(ledgerDate))
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: isLandscape ? 8 : 9,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: isLandscape ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ledgerDate,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: isLandscape ? 14.5 : 15.5,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: isLandscape ? 2 : 3),
                      Text(
                        status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                          fontSize: isLandscape ? 12 : 13,
                        ),
                      ),
                    ],
                  ),
                ),
                FutureBuilder<double>(
                  future: _calculateBalanceDifference(ledgerDate, ledger),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return SizedBox(
                        width: isLandscape ? 60 : 70,
                        height: isLandscape ? 16 : 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(statusColor!),
                        ),
                      );
                    }

                    final balanceDifference = snapshot.data ?? 0.0;
                    final isNegative = balanceDifference < 0;
                    final displayColor = isNegative ? Colors.red[600] : Colors.green[600];
                    
                    // Format with Indian numbering system (lakhs, crores) - same as PDF export
                    final formattedAmount = NumberFormat('#,##,##0.00').format(balanceDifference.abs());

                    return Row(
                      children: [
                        Text(
                          isNegative
                              ? '-₹$formattedAmount'
                              : '₹$formattedAmount',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: isLandscape ? 15.5 : 16.5,
                            color: displayColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right,
                          size: isLandscape ? 18 : 20,
                          color: Colors.grey[400],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          indent: isLandscape ? 80 : 78,
          endIndent: isLandscape ? 24 : 16,
          color: Colors.grey[200],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = _isLandscape(context);

    if (_isLoadingShops) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFF4285F4),
          foregroundColor: Colors.white,
          title: Text(
            'Ledger List',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isLandscape ? 20 : 22,
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF4285F4)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: Text(
          'Ledger List',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isLandscape ? 20 : 22,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearchExpanded ? Icons.close : Icons.search,
              size: isLandscape ? 22 : 24,
            ),
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: _isChecking
                ? SizedBox(
                    width: isLandscape ? 20 : 22,
                    height: isLandscape ? 20 : 22,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(Icons.add_circle_outline, size: isLandscape ? 24 : 26),
            onPressed: _isChecking ? null : _checkAndNavigateToCreateLedger,
          ),
          SizedBox(width: isLandscape ? 12 : 8),
        ],
      ),
      body: Column(
        children: [
          // Admin: Shop Selector Dropdown
          if (_userRole == 'client')
            _buildShopSelector(isLandscape)
          // Employee: Shop Display
          else if (_userRole == 'employee')
            _buildEmployeeShopDisplay(isLandscape),

          // Expandable Search Panel
          _buildSearchPanel(isLandscape),

          // Horizontal Filter Bar
          _buildFilterBar(isLandscape),

          // Ledger List
          Expanded(
            child:
                _selectedShopCollection == null ||
                    _selectedShopCollection!.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.store,
                          size: isLandscape ? 56 : 64,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: isLandscape ? 12 : 16),
                        Text(
                          'No shop selected',
                          style: TextStyle(
                            fontSize: isLandscape ? 16 : 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                        SizedBox(height: isLandscape ? 6 : 8),
                        Text(
                          'Please select a shop from dropdown',
                          style: TextStyle(
                            fontSize: isLandscape ? 13 : 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: _getLedgersStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return _buildLoadingShimmer(isLandscape);
                      }
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Error loading ledgers.'),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: isLandscape ? 56 : 64,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: isLandscape ? 12 : 16),
                              Text(
                                'No ledgers found',
                                style: TextStyle(
                                  fontSize: isLandscape ? 16 : 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey,
                                ),
                              ),
                              SizedBox(height: isLandscape ? 6 : 8),
                              Text(
                                'Tap the + icon to create one',
                                style: TextStyle(
                                  fontSize: isLandscape ? 13 : 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      // Apply filters
                      final filteredDocs = _filterLedgers(snapshot.data!.docs);
                      if (filteredDocs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off,
                                size: isLandscape ? 56 : 64,
                                color: Colors.grey[400],
                              ),
                              SizedBox(height: isLandscape ? 12 : 16),
                              Text(
                                'No ledgers match your filters',
                                style: TextStyle(
                                  fontSize: isLandscape ? 15 : 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: _handleRefresh,
                        child: Container(
                          color: Colors.white,
                          child: ListView.builder(
                            itemCount: filteredDocs.length,
                            itemBuilder: (context, index) {
                              final ledger =
                                  filteredDocs[index].data()
                                      as Map<String, dynamic>;
                              return _buildLedgerItem(
                                context,
                                ledger,
                                isLandscape,
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomBar(currentIndex: 0),
    );
  }
}
