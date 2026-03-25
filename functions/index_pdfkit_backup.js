/**
 * SHOWCASE/REFERENCE IMPLEMENTATION
 * 
 * This cloud function is a Node.js reference implementation of the PDF generation logic.
 * The main production code uses Flutter's local PDF generation (pdf_export_service.dart).
 * 
 * This function is kept as a showcase for the client to see how the logic would work
 * in a backend/cloud environment, but is NOT actively used in the app.
 * 
 * To use this in production, uncomment the cloud function call in pdf_export_service.dart
 * and remove the local generation code.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const PDFDocument = require('pdfkit');
const moment = require('moment');
const { convertAdvanced, containsTamil } = require('./tamilToTanglish');

admin.initializeApp();

/**
 * Format currency with Indian number format (matches Flutter NumberFormat('#,##,##0.00'))
 */
function formatCurrency(amount) {
  // Indian number format: #,##,##0.00
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
      return moment(date).format('h:mm A'); // Example: 2:30 PM
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
 */
function getTransactionTypeDisplay(transaction) {
  const isCredit = transaction.isCredit === true;
  return isCredit ? 'Payment In' : 'Payment Out';
}

/**
 * Convert text to Tanglish if it contains Tamil
 */
function convertText(text) {
  if (!text) return text || '';
  return containsTamil(text) ? convertAdvanced(text) : text;
}

/**
 * Generate Ledger PDF Cloud Function
 * 
 * Expected request body:
 * {
 *   date: "2024-01-15T00:00:00.000Z" (ISO string),
 *   shopName: "Shop Name",
 *   openingBalance: 1000.00,
 *   closingBalance: 2000.00,
 *   saleValue: 500.00,
 *   transactions: [...],
 *   isLedgerClosed: true
 * }
 */
exports.generateLedgerPDF = functions.https.onCall(async (data, context) => {
  try {
    // Authentication is optional - the app handles user authentication at the app level
    // Log if user is authenticated (for debugging)
    if (context.auth) {
      console.log('PDF generation requested by authenticated user:', context.auth.uid);
    } else {
      console.log('PDF generation requested (unauthenticated call - allowed)');
    }

    // Extract parameters
    const {
      date,
      shopName,
      openingBalance,
      closingBalance,
      saleValue,
      transactions,
      isLedgerClosed,
    } = data;

    // Validate required fields
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

    // Create PDF document (A4, 20pt margins - EXACT MATCH)
    const doc = new PDFDocument({
      size: 'A4',
      margins: { top: 20, bottom: 20, left: 20, right: 20 },
    });

    // Store PDF chunks
    const chunks = [];
    doc.on('data', (chunk) => chunks.push(chunk));
    doc.on('end', () => {});

    // ✅ Build transaction list with opening balance as first row (EXACT MATCH TO FLUTTER)
    const allTransactions = [
      // Opening balance row (first entry)
      {
        date: ledgerDateShort,
        time: '',
        particulars: 'Opening Balance',
        type: '',
        debit: openingBalance,
        credit: 0.0,
      },
      // Add all actual transactions
      ...transactions.map((t) => {
        const amount = parseFloat(t.amount || 0);
        const isCredit = t.isCredit === true;
        const time = getTransactionTime(t);

        return {
          date: getCorrectTransactionDate(t, ledgerDate),
          time: time,
          particulars: getParticulars(t),
          type: getTransactionTypeDisplay(t),
          debit: !isCredit ? amount : 0.0,
          credit: isCredit ? amount : 0.0,
        };
      }),
    ];

    // ✅ Calculate totals (including opening balance) - EXACT MATCH TO FLUTTER
    let totalDebit = allTransactions.reduce((sum, t) => sum + (t.debit || 0), 0);
    let totalCredit = allTransactions.reduce((sum, t) => sum + (t.credit || 0), 0);

    // ✅ CONDITIONAL: Add SALES VALUE ROW only if finalSaleValue > 0 - EXACT MATCH
    if (finalSaleValue > 0) {
      allTransactions.push({
        date: '',
        time: '',
        particulars: 'SALES VALUE',
        type: '',
        debit: finalSaleValue,
        credit: 0.0,
      });

      // ✅ Add SALES VALUE to totals
      totalDebit += finalSaleValue;
    }

    // ✅ Add CLOSING BALANCE row (in CREDIT column) - BEFORE GRAND TOTAL - EXACT MATCH
    allTransactions.push({
      date: '',
      time: '',
      particulars: 'CLOSING BALANCE',
      type: '',
      debit: 0.0,
      credit: finalClosingBalance,
    });

    // ✅ ADD CLOSING BALANCE TO TOTAL CREDIT FOR GRAND TOTAL CALCULATION - EXACT MATCH
    const grandTotalCredit = totalCredit + finalClosingBalance;

    // ✅ Add GRAND TOTAL row (AFTER CLOSING BALANCE) - EXACT MATCH
    allTransactions.push({
      date: '',
      time: '',
      particulars: 'GRAND TOTAL',
      type: '',
      debit: totalDebit,
      credit: grandTotalCredit,
    });

    // ✅ FORMULA: Balance Difference = Credit - Debit - EXACT MATCH
    const balanceDifference = grandTotalCredit - totalDebit;

    // ✅ Add BALANCE DIFFERENCE row (AFTER GRAND TOTAL, in DEBIT column) - EXACT MATCH
    allTransactions.push({
      date: '',
      time: '',
      particulars: 'BALANCE DIFFERENCE',
      type: '',
      debit: balanceDifference,
      credit: 0.0,
    });

    // ========== HEADER SECTION (EXACT MATCH TO FLUTTER) ==========
    const shopNameText = convertText(shopName);
    doc.fontSize(16).font('Helvetica-Bold').text(shopNameText.toUpperCase(), {
      align: 'center',
    });
    doc.moveDown(0.3);
    doc
      .fontSize(12)
      .font('Helvetica')
      .text(
        `Ledger Report - Date: ${ledgerDate}`,
        { align: 'center' }
      );
    doc.moveDown(1);

    // Transaction Details title
    doc.fontSize(12).font('Helvetica-Bold').text('Transaction Details');
    doc.moveDown(0.5);

    // ========== TABLE SETUP (EXACT MATCH TO FLUTTER) ==========
    // Flutter uses FlexColumnWidth: 1.8, 2.5, 1.5, 1.5, 1.5
    // Total flex = 1.8 + 2.5 + 1.5 + 1.5 + 1.5 = 8.8
    // Available width = 595 - 40 (margins) = 555
    const tableWidth = 555;
    const colWidths = {
      date: (1.8 / 8.8) * tableWidth,      // ~113.5
      particulars: (2.5 / 8.8) * tableWidth, // ~157.7
      type: (1.5 / 8.8) * tableWidth,      // ~94.6
      credit: (1.5 / 8.8) * tableWidth,    // ~94.6
      debit: (1.5 / 8.8) * tableWidth,     // ~94.6
    };

    const rowHeight = 20;
    const startX = 20;
    let currentY = doc.y;

    // ========== TABLE HEADER (EXACT MATCH) ==========
    // Header background (grey200)
    doc.rect(startX, currentY, tableWidth, rowHeight)
      .fillAndStroke('#E5E5E5', '#000000');
    
    doc.fontSize(9).font('Helvetica-Bold');
    const headerPadding = 6;
    doc.text('Date', startX + headerPadding, currentY + headerPadding, {
      width: colWidths.date,
      align: 'left',
    });
    doc.text('Particulars', startX + colWidths.date + headerPadding, currentY + headerPadding, {
      width: colWidths.particulars,
      align: 'left',
    });
    doc.text('Type', startX + colWidths.date + colWidths.particulars + headerPadding, currentY + headerPadding, {
      width: colWidths.type,
      align: 'center',
    });
    doc.text('Credit (Rs)', startX + colWidths.date + colWidths.particulars + colWidths.type + headerPadding, currentY + headerPadding, {
      width: colWidths.credit,
      align: 'center',
    });
    doc.text('Debit (Rs)', startX + colWidths.date + colWidths.particulars + colWidths.type + colWidths.credit + headerPadding, currentY + headerPadding, {
      width: colWidths.debit,
      align: 'center',
    });
    currentY += rowHeight;

    // ========== TRANSACTION ROWS (EXACT MATCH TO FLUTTER) ==========
    allTransactions.forEach((tx) => {
      const isGrandTotal = tx.particulars === 'GRAND TOTAL';
      const isSalesValue = tx.particulars === 'SALES VALUE';
      const isOpeningBalance = tx.particulars === 'Opening Balance';
      const isBalanceDifference = tx.particulars === 'BALANCE DIFFERENCE';
      const isClosingBalance = tx.particulars === 'CLOSING BALANCE';

      // Check if we need a new page
      if (currentY > 750) {
        doc.addPage();
        currentY = 20;
      }

      // Background color for special rows (grey100 = #F5F5F5)
      if (
        isGrandTotal ||
        isSalesValue ||
        isOpeningBalance ||
        isBalanceDifference ||
        isClosingBalance
      ) {
        doc.rect(startX, currentY, tableWidth, rowHeight)
          .fillAndStroke('#F5F5F5', '#000000');
      } else {
        // Regular row - just border (horizontalInside = grey400 = #BDBDBD)
        doc.rect(startX, currentY, tableWidth, rowHeight).stroke('#BDBDBD');
      }

      // Date with time (fontSize 8, center aligned)
      const dateText = tx.time ? `${tx.date} | ${tx.time}` : tx.date;
      doc.fontSize(8).font('Helvetica');
      if (
        isGrandTotal ||
        isSalesValue ||
        isBalanceDifference ||
        isClosingBalance
      ) {
        doc.font('Helvetica-Bold');
      }
      doc.text(dateText, startX + headerPadding, currentY + headerPadding, {
        width: colWidths.date,
        align: 'left',
      });

      // Particulars (fontSize 9, left aligned, with Tamil conversion)
      const particularsText = convertText(tx.particulars);
      doc.fontSize(9);
      if (
        isGrandTotal ||
        isSalesValue ||
        isOpeningBalance ||
        isBalanceDifference ||
        isClosingBalance
      ) {
        doc.font('Helvetica-Bold');
      } else {
        doc.font('Helvetica');
      }
      doc.text(particularsText, startX + colWidths.date + headerPadding, currentY + headerPadding, {
        width: colWidths.particulars,
        align: 'left',
      });

      // Type (fontSize 9, center aligned, with Tamil conversion)
      const typeText = convertText(tx.type);
      doc.text(typeText, startX + colWidths.date + colWidths.particulars + headerPadding, currentY + headerPadding, {
        width: colWidths.type,
        align: 'center',
      });

      // Credit column (fontSize 9, center aligned)
      if (tx.credit > 0 || isClosingBalance) {
        let creditText = '';
        if (isClosingBalance) {
          creditText = tx.credit !== 0
            ? `Rs ${formatCurrency(tx.credit)}`
            : 'Rs 0.00';
        } else {
          creditText = tx.credit > 0
            ? `Rs ${formatCurrency(tx.credit)}`
            : '';
        }
        
        if (creditText) {
          doc.fontSize(9);
          if (isGrandTotal || isSalesValue || isClosingBalance) {
            doc.font('Helvetica-Bold');
          } else {
            doc.font('Helvetica');
          }
          doc.text(creditText, startX + colWidths.date + colWidths.particulars + colWidths.type + headerPadding, currentY + headerPadding, {
            width: colWidths.credit,
            align: 'center',
          });
        }
      }

      // Debit column (fontSize 9, center aligned, with color coding for balance difference)
      if (tx.debit > 0 || isBalanceDifference) {
        let debitText = '';
        if (isBalanceDifference) {
          debitText = tx.debit !== 0
            ? `Rs ${tx.debit < 0 ? '-' : ''}${formatCurrency(Math.abs(tx.debit))}`
            : 'Rs 0.00';
          
          // Color coding for balance difference
          if (tx.debit > 0) {
            doc.fillColor('#00AA00'); // Green
          } else if (tx.debit < 0) {
            doc.fillColor('#FF0000'); // Red
          } else {
            doc.fillColor('#000000'); // Black
          }
        } else {
          debitText = `Rs ${formatCurrency(tx.debit)}`;
        }
        
        doc.fontSize(9);
        if (
          isGrandTotal ||
          isSalesValue ||
          isClosingBalance ||
          isOpeningBalance ||
          isBalanceDifference
        ) {
          doc.font('Helvetica-Bold');
        } else {
          doc.font('Helvetica');
        }
        doc.text(debitText, startX + colWidths.date + colWidths.particulars + colWidths.type + colWidths.credit + headerPadding, currentY + headerPadding, {
          width: colWidths.debit,
          align: 'center',
        });
        doc.fillColor('#000000'); // Reset to black
      }

      currentY += rowHeight;
    });

    // ========== FOOTER (EXACT MATCH TO FLUTTER) ==========
    doc.moveDown(2);
    const footerY = doc.y;
    doc
      .moveTo(startX, footerY)
      .lineTo(startX + tableWidth, footerY)
      .stroke('#CCCCCC'); // grey300
    doc.moveDown(0.5);
    doc
      .fontSize(10)
      .font('Helvetica-Oblique')
      .fillColor('#666666') // grey700
      .text(
        '"Financial stability is the foundation of success. Track every rupee, plan every expense, grow exponentially."',
        {
          align: 'center',
        }
      );
    doc.moveDown(0.3);
    doc.fontSize(9).font('Helvetica').fillColor('#000000').text('Powered by Ledger System', {
      align: 'center',
    });

    // Finalize PDF
    doc.end();

    // Wait for PDF to be generated
    return new Promise((resolve, reject) => {
      doc.on('end', () => {
        const pdfBuffer = Buffer.concat(chunks);
        const pdfBase64 = pdfBuffer.toString('base64');

        resolve({
          success: true,
          pdfBase64: pdfBase64,
          message: 'PDF generated successfully',
        });
      });

      doc.on('error', (error) => {
        reject(
          new functions.https.HttpsError(
            'internal',
            'Error generating PDF: ' + error.message
          )
        );
      });
    });
  } catch (error) {
    console.error('Error in generateLedgerPDF:', error);
    throw new functions.https.HttpsError(
      'internal',
      'Error generating PDF: ' + error.message
    );
  }
});
