# PDF Generation - Showcase Implementation

## Current Setup

**Main Production Code:** Flutter local PDF generation (`lib/pdf_export_service.dart`)
- This is the active, production code used in the app
- Generates PDFs locally on the device
- Perfect design matching and calculations

**Cloud Function:** Node.js implementation (`functions/index.js`)
- This is a **SHOWCASE/REFERENCE** implementation
- Shows how the logic would work in a backend environment
- **NOT actively used** in the app currently

## Why Two Implementations?

1. **Flutter (Main):** 
   - Widget-based approach with Table widgets
   - Easy to maintain and match exact design
   - Works offline
   - No server costs

2. **Node.js (Showcase):**
   - Demonstrates backend implementation
   - Can be used if you want server-side generation later
   - Useful for client demonstration

## Alternative: Using pdfmake

There's also an alternative implementation using `pdfmake` library (`index_pdfmake.js`) which has better table support and can match Flutter's design more closely.

### To use pdfmake version:

1. Install pdfmake:
```bash
cd functions
npm install pdfmake
```

2. Backup current index.js:
```bash
mv index.js index_pdfkit.js
```

3. Use pdfmake version:
```bash
mv index_pdfmake.js index.js
```

4. Deploy:
```bash
firebase deploy --only functions:generateLedgerPDF
```

## Design Matching Challenges

**PDFKit (current):**
- Requires manual positioning
- Harder to match exact Flutter design
- More code for table layout

**pdfmake (alternative):**
- Declarative table structure (similar to Flutter)
- Better table support
- Easier to match Flutter design
- More similar to Flutter's widget approach

## Recommendation

For exact design matching, **pdfmake** is better because:
- Table-based approach (like Flutter)
- Automatic cell sizing
- Better styling support
- Easier to maintain

The current PDFKit implementation works but requires more manual positioning calculations.

