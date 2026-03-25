/**
 * SHOWCASE/REFERENCE IMPLEMENTATION - Using pdfmake for better table support
 * 
 * This is an alternative implementation using pdfmake library which has
 * better table support and can match Flutter's design more closely.
 * 
 * To use this instead of index.js:
 * 1. Rename index.js to index_pdfkit.js (backup)
 * 2. Rename this file to index.js
 * 3. Run: npm install pdfmake
 * 4. Deploy
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const PdfPrinter = require('pdfmake');
const moment = require('moment');
const fs = require('fs');
const path = require('path');

admin.initializeApp();

/**
 * Check if text contains Tamil Unicode characters
 * Tamil Unicode range: U+0B80 to U+0BFF
 */
function containsTamil(text) {
  if (!text || text.length === 0) return false;
  const tamilRegex = /[\u0B80-\u0BFF]/;
  return tamilRegex.test(text);
}

/**
 * Load Tamil font files from assets directory
 * Returns font configuration for pdfmake
 * 
 * Fonts are located at: ledger/assets/icon/fonts/
 * - NotoSansTamil-Regular.ttf
 * - NotoSansTamil-Bold.ttf
 */
function loadTamilFonts() {
  try {
    // Try multiple locations for Tamil fonts
    // 1. First check in functions/fonts/ (for deployment)
    // 2. Then check in ../assets/icon/fonts/ (for local development)
    const possiblePaths = [
      path.join(__dirname, 'fonts', 'NotoSansTamil-Regular.ttf'), // Deployment location
      path.join(__dirname, '..', 'assets', 'icon', 'fonts', 'NotoSansTamil-Regular.ttf'), // Assets location
    ];
    
    const possibleBoldPaths = [
      path.join(__dirname, 'fonts', 'NotoSansTamil-Bold.ttf'), // Deployment location
      path.join(__dirname, '..', 'assets', 'icon', 'fonts', 'NotoSansTamil-Bold.ttf'), // Assets location
    ];
    
    let tamilNormal = null;
    let tamilBold = null;
    let normalPath = null;
    let boldPath = null;
    
    // Find Regular font
    for (const fontPath of possiblePaths) {
      if (fs.existsSync(fontPath)) {
        tamilNormal = fs.readFileSync(fontPath);
        normalPath = fontPath;
        console.log('✅ Tamil Regular font loaded from:', fontPath);
        break;
      }
    }
    
    // Find Bold font
    for (const fontPath of possibleBoldPaths) {
      if (fs.existsSync(fontPath)) {
        tamilBold = fs.readFileSync(fontPath);
        boldPath = fontPath;
        console.log('✅ Tamil Bold font loaded from:', fontPath);
        break;
      }
    }
    
    // If both fonts loaded successfully, return them
    if (tamilNormal && tamilBold) {
      return {
        normal: tamilNormal,
        bold: tamilBold,
        italics: tamilNormal, // Use normal as fallback for italics
        bolditalics: tamilBold, // Use bold as fallback for bold italics
      };
    }
    
    // Log warning if fonts not found
    if (!tamilNormal) {
      console.warn('⚠️ Tamil Regular font not found. Checked paths:');
      possiblePaths.forEach(p => console.warn('   -', p));
    }
    if (!tamilBold) {
      console.warn('⚠️ Tamil Bold font not found. Checked paths:');
      possibleBoldPaths.forEach(p => console.warn('   -', p));
    }
    
    // Fallback if fonts not found
    console.warn('⚠️ Using Helvetica fallback for Tamil text');
    return {
      normal: 'Helvetica',
      bold: 'Helvetica-Bold',
      italics: 'Helvetica-Oblique',
      bolditalics: 'Helvetica-BoldOblique',
    };
  } catch (error) {
    console.error('❌ Error loading Tamil fonts:', error.message);
    console.error('Stack:', error.stack);
    // Return fallback fonts
    return {
      normal: 'Helvetica',
      bold: 'Helvetica-Bold',
      italics: 'Helvetica-Oblique',
      bolditalics: 'Helvetica-BoldOblique',
    };
  }
}

/**
 * Format currency with Indian number format (matches Flutter NumberFormat('#,##,##0.00'))
 */
function formatCurrency(amount) {
  const absAmount = Math.abs(amount);
  const parts = absAmount.toFixed(2).split('.');
  const integerPart = parts[0];
  const decimalPart = parts[1];
  
  // Format with Indian numbering (lakhs, crores)
  let formatted = integerPart;
  if (integerPart.length > 3) {
    formatted = integerPart.slice(0, -3) + ',' + integerPart.slice(-3);
  }
  if (integerPart.length > 5) {
    formatted = integerPart.slice(0, -5) + ',' + integerPart.slice(-5, -3) + ',' + integerPart.slice(-3);
  }
  
  return formatted + '.' + decimalPart;
}

/**
 * Get transaction time formatted with AM/PM
 */
function getTransactionTime(transaction) {
  try {
    if (transaction.createdAt) {
      let date;
      if (transaction.createdAt.toDate) {
        date = transaction.createdAt.toDate();
      } else if (transaction.createdAt._seconds) {
        date = new Date(transaction.createdAt._seconds * 1000);
      } else if (transaction.createdAt.seconds) {
        date = new Date(transaction.createdAt.seconds * 1000);
      } else {
        date = new Date(transaction.createdAt);
      }
      // Force Indian time (IST, UTC+5:30) so it matches the app display
      return moment(date).utcOffset(330).format('h:mm A');
    }
  } catch (e) {
    // Handle error silently
  }
  return '';
}

/**
 * Get correct transaction date
 */
function getCorrectTransactionDate(transaction, fallbackLedgerDate) {
  let transactionDateStr = null;

  if (transaction.transactionDate) {
    transactionDateStr = transaction.transactionDate.toString();
  } else if (transaction.date) {
    transactionDateStr = transaction.date.toString();
  } else if (transaction.createdAt) {
    try {
      let date;
      if (transaction.createdAt.toDate) {
        date = transaction.createdAt.toDate();
      } else if (transaction.createdAt._seconds) {
        date = new Date(transaction.createdAt._seconds * 1000);
      } else if (transaction.createdAt.seconds) {
        date = new Date(transaction.createdAt.seconds * 1000);
      } else {
        date = new Date(transaction.createdAt);
      }
      return moment(date).format('DD-MM-YYYY');
    } catch (e) {
      // Continue to fallback
    }
  }

  if (transactionDateStr && transactionDateStr.length > 0) {
    try {
      const date = moment(transactionDateStr, 'DD-MMM-YYYY');
      if (date.isValid()) {
        return date.format('DD-MM-YYYY');
      }
      const date2 = moment(transactionDateStr, 'DD-MM-YYYY');
      if (date2.isValid()) {
        return date2.format('DD-MM-YYYY');
      }
    } catch (e) {
      // Continue to fallback
    }
  }

  try {
    const date = moment(fallbackLedgerDate, 'DD-MMM-YYYY');
    if (date.isValid()) {
      return date.format('DD-MM-YYYY');
    }
  } catch (e) {
    // Return fallback as-is
  }

  return fallbackLedgerDate;
}

/**
 * Get particulars (customer name or ledger name)
 */
function getParticulars(transaction) {
  const customerName = transaction.customerName?.toString() || '';
  const ledgerName = transaction.ledgerName?.toString() || '';

  if (customerName.length > 0) return customerName;
  if (ledgerName.length > 0) return ledgerName;
  return 'Transaction';
}

/**
 * Get transaction type display
 * Payment IN = DEBIT (isCredit = false) → "Payment In"
 * Payment OUT = CREDIT (isCredit = true) → "Payment Out"
 */
function getTransactionTypeDisplay(transaction) {
  const isCredit = transaction.isCredit === true;
  return isCredit ? 'Payment Out' : 'Payment In';
}

/**
 * Get font family based on text content
 * Returns 'Tamil' if text contains Tamil, otherwise 'Helvetica'
 */
function getFontFamily(text) {
  if (!text) return 'Helvetica';
  return containsTamil(text) ? 'Tamil' : 'Helvetica';
}

/**
 * Create mixed text array for pdfmake that handles Tamil and English properly
 * Splits text into segments and applies appropriate fonts to each segment
 * Returns either a string (if pure English) or an array of text objects (if mixed)
 */
/**
 * Create mixed text array for pdfmake that handles Tamil and English properly
 * Splits text into segments and applies appropriate fonts to each segment
 * Special characters (brackets, dots, commas, spaces, etc.) are grouped with adjacent text segments
 * Returns either a string (if pure English) or an array of text objects (if mixed)
 */
function createMixedText(text, fontSize = 9, bold = false) {
  if (!text || text.length === 0) return '';
  
  // If no Tamil, return simple string with Helvetica
  // All special characters will render correctly with Helvetica
  if (!containsTamil(text)) {
    return text;
  }
  
  // Check if it's pure Tamil (no English/numbers)
  const hasEnglish = /[A-Za-z0-9]/.test(text);
  
  // If pure Tamil, return simple string with Tamil font
  // Special characters like brackets, dots, commas will render fine with Tamil font
  if (!hasEnglish) {
    return text;
  }
  
  // Mixed content - split into segments
  // Tamil Unicode range: U+0B80 to U+0BFF
  const tamilRegex = /[\u0B80-\u0BFF]/;
  const segments = [];
  let currentSegment = '';
  let currentIsTamil = false;
  
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    const isTamil = tamilRegex.test(char);
    
    // Special characters (not Tamil, not English/numbers) will be grouped with
    // the current segment type. This ensures brackets, dots, spaces, etc.
    // are rendered with the appropriate font context.
    
    // Check if we need to switch font
    if (i === 0) {
      // First character - determine segment type
      currentIsTamil = isTamil;
      currentSegment = char;
    } else if (isTamil === currentIsTamil) {
      // Same type (both Tamil or both non-Tamil), continue segment
      // This groups special characters with adjacent text
      currentSegment += char;
    } else {
      // Different type, save current segment and start new one
      if (currentSegment.length > 0) {
        segments.push({
          text: currentSegment,
          font: currentIsTamil ? 'Tamil' : 'Helvetica',
        });
      }
      currentSegment = char;
      currentIsTamil = isTamil;
    }
  }
  
  // Add last segment
  if (currentSegment.length > 0) {
    segments.push({
      text: currentSegment,
      font: currentIsTamil ? 'Tamil' : 'Helvetica',
    });
  }
  
  // If only one segment, return it as simple text object
  if (segments.length === 1) {
    return {
      text: segments[0].text,
      font: segments[0].font,
      fontSize: fontSize,
      bold: bold,
    };
  }
  
  // Multiple segments - return array with styling applied
  // Each segment will have the correct font (Tamil or Helvetica)
  // Special characters are included in the appropriate segments
  return segments.map(seg => ({
    text: seg.text,
    font: seg.font,
    fontSize: fontSize,
    bold: bold,
  }));
}

/**
 * Generate Ledger PDF Cloud Function using pdfmake
 */
exports.generateLedgerPDF = functions.https.onCall(async (data, context) => {
  try {
    if (context.auth) {
      console.log('PDF generation requested by authenticated user:', context.auth.uid);
    } else {
      console.log('PDF generation requested (unauthenticated call - allowed)');
    }

    const {
      date,
      shopName,
      openingBalance,
      closingBalance,
      saleValue,
      cashOut,
      transactions,
      isLedgerClosed,
    } = data;

    if (!date || !shopName || openingBalance === undefined || !transactions) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Missing required parameters: date, shopName, openingBalance, transactions'
      );
    }

    // Parse date
    const ledgerDate = moment(date).format('DD-MMM-YYYY');
    const ledgerDateShort = moment(date).format('DD-MM-YYYY');
    const currentTime = moment().format('HH:mm');

    // Calculate final values (EXACT MATCH TO FLUTTER)
    const finalClosingBalance = isLedgerClosed ? (closingBalance || 0) : 0.0;
    const finalSaleValue = isLedgerClosed ? (saleValue || 0) : 0.0;
    const finalCashOut = isLedgerClosed ? (cashOut || 0) : 0.0;

    // Build transaction list (EXACT MATCH TO FLUTTER)
    const allTransactions = [
      {
        date: ledgerDateShort,
        time: '',
        particulars: 'Opening Balance',
        type: '',
        debit: openingBalance,
        credit: 0.0,
      },
      ...transactions.map((t) => {
        const amount = parseFloat(t.amount || 0);
        const isCredit = t.isCredit === true;
        const time = getTransactionTime(t);

        return {
          date: getCorrectTransactionDate(t, ledgerDate),
          time: time,
          particulars: getParticulars(t),
          type: getTransactionTypeDisplay(t),
          // Payment IN = DEBIT (isCredit = false) → amount in debit column
          // Payment OUT = CREDIT (isCredit = true) → amount in credit column
          debit: !isCredit ? amount : 0.0,
          credit: isCredit ? amount : 0.0,
        };
      }),
    ];

    // Calculate totals (EXACT MATCH TO FLUTTER)
    let totalDebit = allTransactions.reduce((sum, t) => sum + (t.debit || 0), 0);
    let totalCredit = allTransactions.reduce((sum, t) => sum + (t.credit || 0), 0);

    // Add sales value if applicable
    if (finalSaleValue > 0) {
      allTransactions.push({
        date: '',
        time: '',
        particulars: 'SALES VALUE',
        type: '',
        debit: finalSaleValue,
        credit: 0.0,
      });
      totalDebit += finalSaleValue;
    }

    // Add cash out if applicable
    if (finalCashOut > 0) {
      allTransactions.push({
        date: '',
        time: '',
        particulars: 'CASH OUT',
        type: '',
        debit: 0.0,
        credit: finalCashOut,
      });
      totalCredit += finalCashOut;
    }

    // Add closing balance
    allTransactions.push({
      date: '',
      time: '',
      particulars: 'CLOSING BALANCE',
      type: '',
      debit: 0.0,
      credit: finalClosingBalance,
    });

    const grandTotalCredit = totalCredit + finalClosingBalance;

    // Add grand total
    allTransactions.push({
      date: '',
      time: '',
      particulars: 'GRAND TOTAL',
      type: '',
      debit: totalDebit,
      credit: grandTotalCredit,
    });

    // Calculate balance difference
    const balanceDifference = grandTotalCredit - totalDebit;

    // Add balance difference
    allTransactions.push({
      date: '',
      time: '',
      particulars: 'BALANCE DIFFERENCE',
      type: '',
      debit: balanceDifference,
      credit: 0.0,
    });

    // Define fonts (pdfmake requires font definitions)
    // Load Tamil fonts if available
    const tamilFonts = loadTamilFonts();
    
    const fonts = {
      Helvetica: {
        normal: 'Helvetica',
        bold: 'Helvetica-Bold',
        italics: 'Helvetica-Oblique',
        bolditalics: 'Helvetica-BoldOblique',
      },
      // Tamil font configuration - uses actual font files if available
      Tamil: tamilFonts,
    };

    const printer = new PdfPrinter(fonts);

    // Build table body rows
    const tableBody = allTransactions.map((tx) => {
      const isGrandTotal = tx.particulars === 'GRAND TOTAL';
      const isSalesValue = tx.particulars === 'SALES VALUE';
      const isCashOut = tx.particulars === 'CASH OUT';
      const isOpeningBalance = tx.particulars === 'Opening Balance';
      const isBalanceDifference = tx.particulars === 'BALANCE DIFFERENCE';
      const isClosingBalance = tx.particulars === 'CLOSING BALANCE';

      const isSpecialRow =
        isGrandTotal ||
        isSalesValue ||
        isCashOut ||
        isOpeningBalance ||
        isBalanceDifference ||
        isClosingBalance;

      // Date with time
      const dateText = tx.time ? `${tx.date} | ${tx.time}` : tx.date;

      // Credit text
      let creditText = '';
      if (isClosingBalance || isCashOut) {
        creditText = tx.credit !== 0 ? `Rs ${formatCurrency(tx.credit)}` : 'Rs 0.00';
      } else if (tx.credit > 0) {
        creditText = `Rs ${formatCurrency(tx.credit)}`;
      }

      // Debit text
      let debitText = '';
      let debitColor = '#000000';
      if (isBalanceDifference) {
        debitText = tx.debit !== 0
          ? `Rs ${tx.debit < 0 ? '-' : ''}${formatCurrency(Math.abs(tx.debit))}`
          : 'Rs 0.00';
        if (tx.debit > 0) {
          debitColor = '#00AA00'; // Green
        } else if (tx.debit < 0) {
          debitColor = '#FF0000'; // Red
        }
      } else if (tx.debit > 0) {
        debitText = `Rs ${formatCurrency(tx.debit)}`;
      }

      // Create mixed text for particulars and type (handles Tamil + English properly)
      const particularsMixed = createMixedText(tx.particulars, 9, isSpecialRow);
      const typeMixed = createMixedText(tx.type, 9, isSpecialRow);
      
      // Build particulars cell
      let particularsCell = {
        fontSize: 9,
        bold: isSpecialRow,
        alignment: 'left',
        margin: [6, 6, 6, 6],
      };
      if (typeof particularsMixed === 'string') {
        // Check if it's pure Tamil or pure English
        particularsCell.text = particularsMixed;
        particularsCell.font = containsTamil(particularsMixed) ? 'Tamil' : 'Helvetica';
      } else if (Array.isArray(particularsMixed)) {
        particularsCell.text = particularsMixed;
      } else {
        // Single object
        particularsCell = { ...particularsCell, ...particularsMixed };
      }
      
      // Build type cell
      let typeCell = {
        fontSize: 9,
        bold: isSpecialRow,
        alignment: 'center',
        margin: [6, 6, 6, 6],
      };
      if (typeof typeMixed === 'string') {
        // Check if it's pure Tamil or pure English
        typeCell.text = typeMixed;
        typeCell.font = containsTamil(typeMixed) ? 'Tamil' : 'Helvetica';
      } else if (Array.isArray(typeMixed)) {
        typeCell.text = typeMixed;
      } else {
        // Single object
        typeCell = { ...typeCell, ...typeMixed };
      }
      
      return [
        {
          text: dateText,
          fontSize: 8,
          bold: isSpecialRow,
          alignment: 'left',
          margin: [6, 6, 6, 6],
          font: 'Helvetica',
        },
        particularsCell,
        typeCell,
        {
          text: creditText,
          fontSize: 9,
          bold: isSpecialRow,
          alignment: 'center',
          margin: [6, 6, 6, 6],
          font: 'Helvetica', // Explicitly use Helvetica for English/numeric text
        },
        {
          text: debitText,
          fontSize: 9,
          bold: isSpecialRow,
          color: debitColor,
          alignment: 'center',
          margin: [6, 6, 6, 6],
          font: 'Helvetica', // Explicitly use Helvetica for English/numeric text
        },
      ];
    });

    // Create mixed text for shop name header
    // Don't use toUpperCase() as it can break Tamil text rendering
    const shopNameMixed = createMixedText(shopName, 16, true);
    let shopNameHeader = {
      fontSize: 16,
      bold: true,
      alignment: 'center',
      margin: [0, 0, 0, 4],
    };
    if (typeof shopNameMixed === 'string') {
      // Check if it's pure Tamil or pure English
      shopNameHeader.text = shopNameMixed;
      shopNameHeader.font = containsTamil(shopNameMixed) ? 'Tamil' : 'Helvetica';
    } else if (Array.isArray(shopNameMixed)) {
      shopNameHeader.text = shopNameMixed;
    } else {
      shopNameHeader = { ...shopNameHeader, ...shopNameMixed };
    }
    
    const docDefinition = {
      pageSize: 'A4',
      pageMargins: [20, 20, 20, 20],
      content: [
        // Header
        shopNameHeader,
        {
          text: `Ledger Report - Date: ${ledgerDate}`,
          fontSize: 12,
          alignment: 'center',
          margin: [0, 0, 0, 20],
          font: 'Helvetica', // Explicitly use Helvetica for English text
        },
        // Transaction Details title
        {
          text: 'Transaction Details',
          fontSize: 12,
          bold: true,
          margin: [0, 0, 0, 8],
          font: 'Helvetica', // Explicitly use Helvetica for English text
        },
        // Table
        {
          table: {
            headerRows: 1,
            widths: ['*', '*', '*', '*', '*'], // Equal widths, will adjust
            body: [
              // Header row
              [
                {
                  text: 'Date',
                  fontSize: 9,
                  bold: true,
                  alignment: 'center',
                  fillColor: '#E5E5E5',
                  margin: [6, 6, 6, 6],
                  font: 'Helvetica', // Explicitly use Helvetica for English text
                },
                {
                  text: 'Particulars',
                  fontSize: 9,
                  bold: true,
                  alignment: 'center',
                  fillColor: '#E5E5E5',
                  margin: [6, 6, 6, 6],
                  font: 'Helvetica', // Explicitly use Helvetica for English text
                },
                {
                  text: 'Type',
                  fontSize: 9,
                  bold: true,
                  alignment: 'center',
                  fillColor: '#E5E5E5',
                  margin: [6, 6, 6, 6],
                  font: 'Helvetica', // Explicitly use Helvetica for English text
                },
                {
                  text: 'Credit (Rs)',
                  fontSize: 9,
                  bold: true,
                  alignment: 'center',
                  fillColor: '#E5E5E5',
                  margin: [6, 6, 6, 6],
                  font: 'Helvetica', // Explicitly use Helvetica for English text
                },
                {
                  text: 'Debit (Rs)',
                  fontSize: 9,
                  bold: true,
                  alignment: 'center',
                  fillColor: '#E5E5E5',
                  margin: [6, 6, 6, 6],
                  font: 'Helvetica', // Explicitly use Helvetica for English text
                },
              ],
              ...tableBody,
            ],
          },
          layout: {
            hLineWidth: function (i, node) {
              if (i === 0 || i === node.table.body.length) {
                return 0.8; // Top and bottom borders
              }
              return 0.3; // Horizontal lines
            },
            vLineWidth: function () {
              return 0;
            },
            paddingLeft: function () {
              return 0;
            },
            paddingRight: function () {
              return 0;
            },
            paddingTop: function () {
              return 0;
            },
            paddingBottom: function () {
              return 0;
            },
            fillColor: function (rowIndex, node, columnIndex) {
              const row = node.table.body[rowIndex];
              if (rowIndex === 0) return '#E5E5E5'; // Header
              
              // Check if this is a special row
              const particulars = row[1]?.text || '';
              if (
                particulars === 'GRAND TOTAL' ||
                particulars === 'SALES VALUE' ||
                particulars === 'CASH OUT' ||
                particulars === 'Opening Balance' ||
                particulars === 'BALANCE DIFFERENCE' ||
                particulars === 'CLOSING BALANCE'
              ) {
                return '#F5F5F5'; // Grey background for special rows
              }
              return null;
            },
          },
        },
        // Footer
        {
          margin: [0, 15, 0, 0],
          text: [
            {
              text: '"Financial stability is the foundation of success. Track every rupee, plan every expense, grow exponentially."',
              fontSize: 10,
              italics: true,
              color: '#666666',
              alignment: 'center',
              font: 'Helvetica', // Explicitly use Helvetica for English text
            },
            '\n',
            {
              text: 'Powered by Ledger System',
              fontSize: 9,
              color: '#666666',
              alignment: 'center',
              font: 'Helvetica', // Explicitly use Helvetica for English text
            },
          ],
        },
      ],
    };

    // Generate PDF
    const pdfDoc = printer.createPdfKitDocument(docDefinition);

    // Convert to buffer
    return new Promise((resolve, reject) => {
      const chunks = [];
      pdfDoc.on('data', (chunk) => chunks.push(chunk));
      pdfDoc.on('end', () => {
        const pdfBuffer = Buffer.concat(chunks);
        const pdfBase64 = pdfBuffer.toString('base64');

        resolve({
          success: true,
          pdfBase64: pdfBase64,
          message: 'PDF generated successfully',
        });
      });
      pdfDoc.on('error', (error) => {
        reject(
          new functions.https.HttpsError(
            'internal',
            'Error generating PDF: ' + error.message
          )
        );
      });
      pdfDoc.end();
    });
  } catch (error) {
    console.error('Error in generateLedgerPDF:', error);
    throw new functions.https.HttpsError(
      'internal',
      'Error generating PDF: ' + error.message
    );
  }
});

