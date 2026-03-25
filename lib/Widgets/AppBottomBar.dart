import 'package:flutter/material.dart';
import '../CustomerList.dart';
import '../ledgerlist.dart';
import '../Settings.dart';

/// A shared bottom navigation bar used across multiple screens.
///
/// Usage: place in `Scaffold.bottomNavigationBar` and provide the
/// `currentIndex` to highlight the active tab.
class AppBottomBar extends StatelessWidget {
  final int currentIndex;

  const AppBottomBar({Key? key, this.currentIndex = 0}) : super(key: key);

  void _onItemTapped(BuildContext context, int index) {
    if (index == currentIndex) return;

    switch (index) {
      case 0:
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LedgerListScreen()),
          (route) => false,
        );
        break;
      case 1:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => CustomerListScreen()),
        );
        break;
      case 2:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      items: const <BottomNavigationBarItem>[
        BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Ledger'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Customer'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
      ],
      currentIndex: currentIndex,
      selectedItemColor: const Color(0xFF4285F4),
      unselectedItemColor: Colors.grey,
      onTap: (index) => _onItemTapped(context, index),
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
    );
  }
}
