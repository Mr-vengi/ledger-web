# Ledger PDF Generator - Firebase Cloud Function

This Firebase Cloud Function generates PDF reports for ledger transactions with Tamil language support (converted to Tanglish).

## Setup

1. Install dependencies:
```bash
cd functions
npm install
```

2. Deploy the function:
```bash
firebase deploy --only functions:generateLedgerPDF
```

## Usage

Call the function from your Flutter app:

```dart
final callable = FirebaseFunctions.instance.httpsCallable('generateLedgerPDF');
final result = await callable.call({
  'date': date.toIso8601String(),
  'shopName': shopName,
  'openingBalance': openingBalance,
  'closingBalance': closingBalance,
  'saleValue': saleValue,
  'transactions': transactions,
  'isLedgerClosed': isLedgerClosed,
});

final pdfBase64 = result.data['pdfBase64'] as String;
final pdfBytes = base64Decode(pdfBase64);
```

## Features

- ✅ Tamil to Tanglish conversion
- ✅ Same PDF structure as Flutter version
- ✅ Proper date/time formatting
- ✅ Currency formatting
- ✅ Balance calculations
- ✅ Color-coded balance difference

