// lib/font_loader.dart

import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart'; // ← This import fixes debugPrint
import 'dart:typed_data';

class TamilFontLoader {
  static pw.Font? tamilRegular;
  static pw.Font? tamilBold;
  static bool _isInitialized = false;

  /// Call this once in main() — loads NotoSansTamil fonts for PDF generation
  static Future<void> initializeFonts() async {
    if (_isInitialized) return;

    try {
      final regularData = await rootBundle.load(
        "assets/icon/fonts/NotoSansTamil-Regular.ttf",
      );
      final boldData = await rootBundle.load(
        "assets/icon/fonts/NotoSansTamil-Bold.ttf",
      );

      // Create TTF fonts - these will be embedded in PDF
      // rootBundle.load() returns ByteData which can be used directly
      // This ensures proper font embedding for Tamil characters including conjuncts
      // IMPORTANT: Use ByteData directly - don't convert to Uint8List
      tamilRegular = pw.Font.ttf(regularData);
      tamilBold = pw.Font.ttf(boldData);
      
      // Verify fonts are created successfully
      if (tamilRegular == null || tamilBold == null) {
        throw Exception('Failed to create Tamil font objects');
      }

      _isInitialized = true;
      debugPrint("✅ Tamil fonts loaded successfully for PDF generation");
      debugPrint("   Regular font: ${tamilRegular != null ? 'Loaded' : 'Failed'}");
      debugPrint("   Bold font: ${tamilBold != null ? 'Loaded' : 'Failed'}");
    } catch (e) {
      debugPrint("Failed to load Tamil fonts: $e");
      rethrow; // So main() can show a warning if needed
    }
  }

  // Easy getters (so you don't have to check for null every time)
  static pw.Font get regular => tamilRegular!;
  static pw.Font get bold => tamilBold!;
}
