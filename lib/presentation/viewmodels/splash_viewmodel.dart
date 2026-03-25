import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repositories/splash_repository.dart';

class SplashViewModel extends ChangeNotifier {
  SplashViewModel({
    required SplashRepository repository,
    Duration navigationDelay = const Duration(seconds: 3),
  })  : _repository = repository,
        _navigationDelay = navigationDelay;

  final SplashRepository _repository;
  final Duration _navigationDelay;

  bool _shouldNavigate = false;
  bool get shouldNavigate => _shouldNavigate;

  Future<void> initialize() async {
    _hideSystemUI();
    await _repository.preloadApp();
    await Future<void>.delayed(_navigationDelay);
    _showSystemUI();
    _shouldNavigate = true;
    notifyListeners();
  }

  void markNavigationHandled() {
    if (_shouldNavigate) {
      _shouldNavigate = false;
      notifyListeners();
    }
  }

  void _hideSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: <SystemUiOverlay>[],
    );
  }

  void _showSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  @override
  void dispose() {
    _showSystemUI();
    super.dispose();
  }
}

