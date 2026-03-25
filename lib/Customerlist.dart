import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'Addcustomer.dart';
import 'CustomerDetailScreen.dart';
import 'widgets/AppBottomBar.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  String _selectedFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  bool _isSearchExpanded = false;
  DateTimeRange? _customDateRange;
  int? _selectedMonth;
  int? _selectedYear;
  bool _isEmployeeLogin = false;
  String? _userRole;
  String? _userShop;
  String? _userShopCollection;
  String? _selectedShopCollection;
  String? _selectedShopName;
  List<Map<String, dynamic>> _shops = [];
  bool _isLoadingShops = true;

  final List<String> _filterOptions = [
    'All',
    'Retail',
    'Wholesale',
    'Recent',
    'High Amount',
    'No Transactions',
  ];

  @override
  void initState() {
    super.initState();
    _checkLoginType();
  }

  Future<void> _checkLoginType() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final loginType = prefs.getString('loginType') ?? 'client';
      final shopName = prefs.getString('shopName');
      final shopCollection = prefs.getString('shopCollection');

      setState(() {
        _userRole = loginType;
        _isEmployeeLogin = loginType == 'employee';
        _userShop = shopName;
        _userShopCollection = shopCollection;
      });

      if (loginType == 'client') {
        final selectedShopCollection = prefs.getString(
          'selectedShopCollection',
        );
        final selectedShopName = prefs.getString('selectedShopName');

        if (selectedShopCollection != null &&
            selectedShopCollection.isNotEmpty) {
          setState(() {
            _selectedShopCollection = selectedShopCollection;
            _selectedShopName = selectedShopName;
            _isLoadingShops = false;
          });
          debugPrint(
            'Loaded saved shop: $_selectedShopCollection - $_selectedShopName',
          );
        } else {
          await _fetchAllShops();
        }
      } else if (loginType == 'employee') {
        setState(() {
          _selectedShopCollection = shopCollection;
          _selectedShopName = shopName;
          _isLoadingShops = false;
        });
      }

      debugPrint('Login Type: $loginType, Is Employee: $_isEmployeeLogin');
    } catch (e) {
      debugPrint('Error checking login type: $e');
      setState(() => _isLoadingShops = false);
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
      if (!_isSearchExpanded) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
  }

  Future<void> _handleRefresh() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) setState(() {});
  }

  String _getLastTransactionText(Timestamp? lastTransaction) {
    if (lastTransaction == null) return "No transactions yet";
    final lastDate = lastTransaction.toDate();
    final difference = DateTime.now().difference(lastDate).inDays;
    if (difference == 0) return "Today";
    if (difference == 1) return "1 day ago";
    return "$difference days ago";
  }

  String _formatAmount(dynamic amount) {
    num numAmount = 0;
    if (amount is num) {
      numAmount = amount;
    } else if (amount is String) {
      numAmount = num.tryParse(amount) ?? 0;
    }
    final format = NumberFormat('#,##,##0.00');
    return "₹${format.format(numAmount)}";
  }

  Future<double> _calculateOutstanding(
    String customerId,
    double openingAmount,
  ) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_selectedShopCollection!)
          .doc('customers')
          .collection('list')
          .doc(customerId)
          .collection('transactions')
          .get();

      double totalPaymentIn = 0;
      double totalPaymentOut = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final amount = (data['amount'] ?? 0).toDouble();
        final isCredit = data['isCredit'] ?? false;

        // Payment IN = DEBIT (isCredit = false) → money received from customer → REDUCE outstanding (subtract)
        // Payment OUT = CREDIT (isCredit = true) → money given to customer → INCREASE outstanding (add)
        if (isCredit) {
          totalPaymentOut += amount; // Payment OUT (CREDIT)
        } else {
          totalPaymentIn += amount; // Payment IN (DEBIT)
        }
      }
      // ✅ CORRECT FORMULA: Outstanding = Opening - Payment IN + Payment OUT
      // Payment IN reduces what customer owes, Payment OUT increases what customer owes
      return openingAmount - totalPaymentIn + totalPaymentOut;
    } catch (e) {
      debugPrint('Error calculating outstanding: $e');
      return openingAmount;
    }
  }

  bool _matchesFilter(
    Map<String, dynamic> data,
    Timestamp? lastTransaction,
    double outstandingAmount,
  ) {
    switch (_selectedFilter) {
      case 'Retail':
        return data['customerType'] == 'Retail';
      case 'Wholesale':
        return data['customerType'] == 'Wholesale';
      case 'Recent':
        if (lastTransaction == null) return false;
        final difference = DateTime.now()
            .difference(lastTransaction.toDate())
            .inDays;
        return difference <= 7;
      case 'High Amount':
        return outstandingAmount >= 10000;
      case 'No Transactions':
        return lastTransaction == null;
      default:
        return true;
    }
  }

  bool _matchesSearch(String customerName) {
    if (_searchQuery.isEmpty) return true;
    return customerName.toLowerCase().contains(_searchQuery.toLowerCase());
  }

  void _showCustomerOptions(
    BuildContext context,
    String customerId,
    String currentName,
    bool isActive,
  ) {
    bool isCurrentlyActive = isActive;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Column(
                      children: [
                        Text(
                          currentName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Customer Options',
                          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Scrollable options list
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildOptionTile(
                            icon: Icons.edit,
                            title: 'Edit Name',
                            color: const Color(0xFF4285F4),
                            onTap: () {
                              Navigator.pop(context);
                              _showEditNameDialog(customerId, currentName);
                            },
                          ),
                          FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance
                                .collection(_selectedShopCollection!)
                                .doc('customers')
                                .collection('list')
                                .doc(customerId)
                                .get(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const SizedBox.shrink();
                              }
                              final data = snapshot.data!.data() as Map<String, dynamic>?;
                              final openingAmount = (data?['openingAmount'] ?? 0).toDouble();
                              
                              return _buildOptionTile(
                                icon: Icons.account_balance_wallet,
                                title: 'Edit Opening Amount',
                                subtitle: 'Current: ₹${NumberFormat('#,##,##0.00').format(openingAmount)}',
                                color: Colors.orange[700]!,
                                onTap: () {
                                  Navigator.pop(context);
                                  _showEditOpeningAmountDialog(customerId, openingAmount);
                                },
                              );
                            },
                          ),
                          _buildOptionTile(
                            icon: isCurrentlyActive ? Icons.check_circle : Icons.cancel,
                            title: isCurrentlyActive ? 'Active' : 'Inactive',
                            color: isCurrentlyActive ? Colors.green : Colors.red,
                            trailing: Switch(
                              value: isCurrentlyActive,
                              activeColor: Colors.green,
                              onChanged: (value) async {
                                setModalState(() => isCurrentlyActive = value);
                                await _updateCustomerStatus(customerId, value);
                                if (mounted) setState(() {});
                              },
                            ),
                          ),
                          _buildOptionTile(
                            icon: Icons.delete_forever,
                            title: 'Delete Customer',
                            color: Colors.red,
                            onTap: () {
                              Navigator.pop(context);
                              _showDeleteConfirmation(customerId, currentName);
                            },
                          ),
                          // Extra bottom padding for safe area
                          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required Color color,
    Widget? trailing,
    VoidCallback? onTap,
    String? subtitle,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w400,
              ),
            )
          : null,
      trailing: trailing,
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      minLeadingWidth: 30,
    );
  }

  void _showEditNameDialog(String customerId, String currentName) {
    final TextEditingController controller = TextEditingController(
      text: currentName,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Edit name',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: SingleChildScrollView(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Enter name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF4285F4)),
                ),
              ),
              textInputAction: TextInputAction.done,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Name cannot be empty'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              await _updateCustomerName(customerId, newName);
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
            ),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _updateCustomerName(String customerId, String newName) async {
    try {
      await FirebaseFirestore.instance
          .collection(_selectedShopCollection!)
          .doc('customers')
          .collection('list')
          .doc(customerId)
          .update({'customerName': newName});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name updated'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _updateCustomerStatus(String customerId, bool isActive) async {
    try {
      await FirebaseFirestore.instance
          .collection(_selectedShopCollection!)
          .doc('customers')
          .collection('list')
          .doc(customerId)
          .update({'status': isActive ? 'Active' : 'Inactive'});
    } catch (e) {
      debugPrint('Error updating status: $e');
    }
  }

  /// Show dialog to edit customer opening amount
  void _showEditOpeningAmountDialog(String customerId, double currentAmount) {
    final TextEditingController controller = TextEditingController(
      text: currentAmount.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          scrollable: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          title: const Text(
            'Edit Opening Amount',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current: ₹${NumberFormat('#,##,##0.00').format(currentAmount)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'New opening amount',
                  hintText: 'Enter amount',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This will update the outstanding balance calculation.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amountText =
                    controller.text.trim().replaceAll(',', '');
                final newAmount = double.tryParse(amountText);

                if (newAmount == null) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid amount'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                await _updateOpeningAmount(customerId, newAmount);
                if (mounted) Navigator.pop(dialogContext);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4285F4),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  /// Update customer opening amount
  Future<void> _updateOpeningAmount(String customerId, double newAmount) async {
    try {
      await FirebaseFirestore.instance
          .collection(_selectedShopCollection!)
          .doc('customers')
          .collection('list')
          .doc(customerId)
          .update({'openingAmount': newAmount});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Opening amount updated to ₹${NumberFormat('#,##,##0.00').format(newAmount)}',
            ),
            backgroundColor: Colors.green[600],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        // Refresh the list to show updated outstanding amounts
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating opening amount: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteConfirmation(String customerId, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.warning, color: Colors.orange, size: 40),
        title: const Text('Delete Customer?'),
        content: Text(
          'Are you sure you want to delete "$name"?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteCustomer(customerId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCustomer(String customerId) async {
    try {
      final transactionSnapshot = await FirebaseFirestore.instance
          .collection(_selectedShopCollection!)
          .doc('customers')
          .collection('list')
          .doc(customerId)
          .collection('transactions')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in transactionSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      await FirebaseFirestore.instance
          .collection(_selectedShopCollection!)
          .doc('customers')
          .collection('list')
          .doc(customerId)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Customer deleted'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildSearchPanel(bool isLandscape) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _isSearchExpanded ? (isLandscape ? 56 : 60) : 0,
      curve: Curves.easeInOut,
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: isLandscape ? 14 : 16,
          vertical: isLandscape ? 8 : 10,
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _searchQuery = value),
          decoration: InputDecoration(
            hintText: 'Search customers...',
            hintStyle: TextStyle(
              color: Colors.grey[500],
              fontSize: isLandscape ? 14 : 15,
            ),
            prefixIcon: Icon(
              Icons.search,
              color: Colors.grey[600],
              size: isLandscape ? 20 : 22,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(
                      Icons.clear,
                      color: Colors.grey[600],
                      size: isLandscape ? 18 : 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
              borderSide: BorderSide(color: Colors.grey[300] ?? Colors.grey),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(isLandscape ? 10 : 12),
              borderSide: const BorderSide(color: Color(0xFF4285F4)),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 14 : 16,
              vertical: isLandscape ? 10 : 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShopSelector(bool isLandscape) {
    if (_isEmployeeLogin) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 14 : 16,
        vertical: isLandscape ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[200] ?? Colors.grey, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.store,
            color: const Color(0xFF4285F4),
            size: isLandscape ? 18 : 20,
          ),
          SizedBox(width: isLandscape ? 12 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Shop',
                  style: TextStyle(
                    fontSize: isLandscape ? 12 : 13,
                    color: Colors.grey[600] ?? Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: isLandscape ? 2 : 4),
                Text(
                  _selectedShopName ?? 'No Shop Selected',
                  style: TextStyle(
                    fontSize: isLandscape ? 15 : 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 8 : 10,
              vertical: isLandscape ? 4 : 6,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.check_circle,
              color: const Color(0xFF4285F4),
              size: isLandscape ? 16 : 18,
            ),
          ),
        ],
      ),
    );
  }

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
          _buildFilterChip('Retail'),
          const SizedBox(width: 8),
          _buildFilterChip('Wholesale'),
          const SizedBox(width: 8),
          _buildFilterChip('Recent'),
          const SizedBox(width: 8),
          _buildFilterChip('High Amount'),
          const SizedBox(width: 8),
          _buildFilterChip('No Transactions'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = label),
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

  Widget _buildLoadingShimmer(bool isLandscape) {
    return Container(
      color: Colors.white,
      child: ListView.builder(
        itemCount: 8,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) {
          return Column(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? 14 : 16,
                  vertical: isLandscape ? 12 : 14,
                ),
                child: Row(
                  children: [
                    _ShimmerBox(
                      width: isLandscape ? 40 : 48,
                      height: isLandscape ? 40 : 48,
                      borderRadius: BorderRadius.circular(
                        isLandscape ? 20 : 24,
                      ),
                    ),
                    SizedBox(width: isLandscape ? 12 : 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ShimmerBox(
                            width: double.infinity,
                            height: isLandscape ? 14 : 16,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          SizedBox(height: isLandscape ? 6 : 8),
                          _ShimmerBox(
                            width: 120,
                            height: isLandscape ? 12 : 14,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: isLandscape ? 12 : 14),
                    _ShimmerBox(
                      width: isLandscape ? 70 : 80,
                      height: isLandscape ? 14 : 16,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
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
        },
      ),
    );
  }

  Widget _buildCustomerItem(
    BuildContext context,
    Map<String, dynamic> data,
    String customerId,
    String name,
    Timestamp? lastTxn,
    double outstandingAmount,
    bool isLandscape,
  ) {
    final lastTransactionText = _getLastTransactionText(lastTxn);
    final customerType = data['customerType']?.toString();
    final status = data['status'] ?? 'Active';
    final isActive = status == 'Active';

    // Positive amount (customer owes us) = RED
    // Negative amount (we owe customer) = GREEN
    final bool isPositive = outstandingAmount >= 0;
    Color amountColor = isPositive
        ? const Color(0xFFF44336) // Red for positive (customer owes)
        : const Color(0xFF4CAF50); // Green for negative (we owe)

    return Column(
      children: [
        InkWell(
          onTap: () {
            if (!isActive) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('This customer is inactive'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CustomerDetailScreen(
                  customerId: customerId,
                  customerName: name,
                  shopCollection: _selectedShopCollection ?? '',
                ),
              ),
            );
          },
          onLongPress: !_isEmployeeLogin
              ? () => _showCustomerOptions(context, customerId, name, isActive)
              : null,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isLandscape ? 14 : 16,
              vertical: isLandscape ? 12 : 14,
            ),
            color: Colors.white,
            child: Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: isLandscape ? 20 : 24,
                      backgroundColor: const Color(
                        0xFF4285F4,
                      ).withOpacity(isActive ? 0.1 : 0.05),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : 'C',
                        style: TextStyle(
                          color: isActive
                              ? const Color(0xFF4285F4)
                              : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: isLandscape ? 16 : 18,
                        ),
                      ),
                    ),
                    if (customerType != null)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isLandscape ? 4 : 5,
                            vertical: isLandscape ? 1 : 2,
                          ),
                          decoration: BoxDecoration(
                            color: customerType == 'Retail'
                                ? const Color(0xFF2196F3)
                                : const Color(0xFFFF9800),
                            borderRadius: BorderRadius.circular(
                              isLandscape ? 6 : 8,
                            ),
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: Text(
                            customerType == 'Retail' ? 'R' : 'W',
                            style: TextStyle(
                              fontSize: isLandscape ? 8 : 9,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: isLandscape ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: isLandscape ? 14.5 : 15.5,
                          color: isActive ? Colors.black87 : Colors.grey,
                        ),
                      ),
                      SizedBox(height: isLandscape ? 2 : 3),
                      Text(
                        lastTransactionText,
                        style: TextStyle(
                          color: isActive ? Colors.grey[600] : Colors.grey[400],
                          fontWeight: FontWeight.w500,
                          fontSize: isLandscape ? 12 : 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _formatAmount(outstandingAmount.abs()),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: isLandscape ? 15.5 : 16.5,
                        color: amountColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      size: isLandscape ? 18 : 20,
                      color: Colors.grey[400],
                    ),
                  ],
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
          title: const Text(
            'Customer List',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFF4285F4)),
        ),
      );
    }

    final firestore = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4285F4),
        foregroundColor: Colors.white,
        title: Text(
          'Customer List',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isLandscape ? 20 : 22,
          ),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: Icon(
              _isSearchExpanded ? Icons.close : Icons.search,
              size: isLandscape ? 22 : 24,
            ),
            onPressed: _toggleSearch,
          ),
          IconButton(
            icon: Icon(Icons.add_circle_outline, size: isLandscape ? 24 : 26),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddCustomer()),
            ),
          ),
          SizedBox(width: isLandscape ? 12 : 8),
        ],
      ),
      body: Column(
        children: [
          _buildSearchPanel(isLandscape),
          _buildShopSelector(isLandscape),
          _buildFilterBar(isLandscape),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  _selectedShopCollection != null &&
                      _selectedShopCollection!.isNotEmpty
                  ? firestore
                        .collection(_selectedShopCollection!)
                        .doc('customers')
                        .collection('list')
                        .orderBy('createdAt', descending: true)
                        .snapshots()
                  : Stream.empty(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    _selectedShopCollection != null) {
                  return _buildLoadingShimmer(isLandscape);
                }

                if (_selectedShopCollection == null ||
                    _selectedShopCollection!.isEmpty) {
                  return Center(
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
                          'Please select a shop from Ledger page',
                          style: TextStyle(
                            fontSize: isLandscape ? 13 : 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: isLandscape ? 56 : 64,
                          color: Colors.red[400],
                        ),
                        SizedBox(height: isLandscape ? 12 : 16),
                        Text(
                          'Error loading customers',
                          style: TextStyle(
                            fontSize: isLandscape ? 16 : 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState(isLandscape);
                }

                final customers = snapshot.data!.docs;
                final filteredCustomers = customers.where((doc) {
                  final data = doc.data() as Map<String, dynamic>? ?? {};
                  final name =
                      data['customerName']?.toString() ??
                      data['name']?.toString() ??
                      'Unnamed Customer';
                  return _matchesSearch(name);
                }).toList();

                if (filteredCustomers.isEmpty) {
                  return _buildNoSearchResults(isLandscape);
                }

                return RefreshIndicator(
                  onRefresh: _handleRefresh,
                  color: const Color(0xFF4285F4),
                  child: Container(
                    color: Colors.white,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: filteredCustomers.length,
                      itemBuilder: (context, index) {
                        final doc = filteredCustomers[index];
                        final data = doc.data() as Map<String, dynamic>? ?? {};
                        final customerId = doc.id;
                        final name =
                            data['customerName']?.toString() ??
                            data['name']?.toString() ??
                            'Unnamed Customer';
                        final openingAmount = (data['openingAmount'] ?? 0)
                            .toDouble();
                        final lastTxn = data['lastTransaction'] is Timestamp
                            ? data['lastTransaction'] as Timestamp
                            : null;

                        return FutureBuilder<double>(
                          future: _calculateOutstanding(
                            customerId,
                            openingAmount,
                          ),
                          builder: (context, outstandingSnapshot) {
                            final outstandingAmount =
                                outstandingSnapshot.data ?? openingAmount;

                            if (!_matchesFilter(
                              data,
                              lastTxn,
                              outstandingAmount,
                            )) {
                              return const SizedBox.shrink();
                            }

                            if (outstandingSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return _buildShimmerItem(isLandscape);
                            }

                            return _buildCustomerItem(
                              context,
                              data,
                              customerId,
                              name,
                              lastTxn,
                              outstandingAmount,
                              isLandscape,
                            );
                          },
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
      bottomNavigationBar: const AppBottomBar(currentIndex: 1),
    );
  }

  Widget _buildEmptyState(bool isLandscape) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: const Color(0xFF4285F4),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.person_outline,
                  size: isLandscape ? 56 : 64,
                  color: Colors.grey[400],
                ),
                SizedBox(height: isLandscape ? 12 : 16),
                Text(
                  'No customers found',
                  style: TextStyle(
                    fontSize: isLandscape ? 16 : 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: isLandscape ? 6 : 8),
                Text(
                  'Tap the + icon to add one',
                  style: TextStyle(
                    fontSize: isLandscape ? 13 : 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoSearchResults(bool isLandscape) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: const Color(0xFF4285F4),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
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
                  'No customers match your search',
                  style: TextStyle(
                    fontSize: isLandscape ? 15 : 16,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerItem(bool isLandscape) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 14 : 16,
            vertical: isLandscape ? 12 : 14,
          ),
          child: Row(
            children: [
              _ShimmerBox(
                width: isLandscape ? 40 : 48,
                height: isLandscape ? 40 : 48,
                borderRadius: BorderRadius.circular(isLandscape ? 20 : 24),
              ),
              SizedBox(width: isLandscape ? 12 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ShimmerBox(
                      width: double.infinity,
                      height: isLandscape ? 14 : 16,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    SizedBox(height: isLandscape ? 6 : 8),
                    _ShimmerBox(
                      width: 120,
                      height: isLandscape ? 12 : 14,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
              ),
              SizedBox(width: isLandscape ? 12 : 14),
              _ShimmerBox(
                width: isLandscape ? 70 : 80,
                height: isLandscape ? 14 : 16,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
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
}

/// Shimmer Box Widget
class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(
      begin: -2,
      end: 2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.grey[300] ?? Colors.grey,
                Colors.grey[200] ?? Colors.grey,
                Colors.grey[300] ?? Colors.grey,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: GradientRotation(_animation.value),
            ),
          ),
        );
      },
    );
  }
}
