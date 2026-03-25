/**
 * Local test script for generateLedgerPDF cloud function
 * 
 * Usage: node test-local.js
 * 
 * This script tests the PDF generation locally without deploying.
 * It will generate a test PDF file: test-output.pdf
 */

const admin = require('firebase-admin');
const PdfPrinter = require('pdfmake');
const moment = require('moment');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin (using default credentials or emulator)
// For local testing, we don't need actual Firebase connection
try {
  admin.initializeApp();
  console.log('✅ Firebase Admin initialized');
} catch (e) {
  console.log('⚠️  Firebase Admin already initialized or using emulator');
}

// Import the functions from index.js
// We'll copy the necessary functions here for testing

/**
 * Check if text contains Tamil Unicode characters
 */
function containsTamil(text) {
  if (!text || text.length === 0) return false;
  const tamilRegex = /[\u0B80-\u0BFF]/;
  return tamilRegex.test(text);
}

/**
 * Get font family based on text content
 */
function getFontFamily(text) {
  if (!text) return 'Helvetica';
  return containsTamil(text) ? 'Tamil' : 'Helvetica';
}

/**
 * Load Tamil fonts
 */
function loadTamilFonts() {
  try {
    const possiblePaths = [
      path.join(__dirname, 'fonts', 'NotoSansTamil-Regular.ttf'),
      path.join(__dirname, '..', 'assets', 'icon', 'fonts', 'NotoSansTamil-Regular.ttf'),
    ];
    
    const possibleBoldPaths = [
      path.join(__dirname, 'fonts', 'NotoSansTamil-Bold.ttf'),
      path.join(__dirname, '..', 'assets', 'icon', 'fonts', 'NotoSansTamil-Bold.ttf'),
    ];
    
    let tamilNormal = null;
    let tamilBold = null;
    
    for (const fontPath of possiblePaths) {
      if (fs.existsSync(fontPath)) {
        tamilNormal = fs.readFileSync(fontPath);
        console.log('✅ Tamil Regular font loaded from:', fontPath);
        break;
      }
    }
    
    for (const fontPath of possibleBoldPaths) {
      if (fs.existsSync(fontPath)) {
        tamilBold = fs.readFileSync(fontPath);
        console.log('✅ Tamil Bold font loaded from:', fontPath);
        break;
      }
    }
    
    if (tamilNormal && tamilBold) {
      return {
        normal: tamilNormal,
        bold: tamilBold,
        italics: tamilNormal,
        bolditalics: tamilBold,
      };
    }
    
    console.warn('⚠️ Using Helvetica fallback for Tamil text');
    return {
      normal: 'Helvetica',
      bold: 'Helvetica-Bold',
      italics: 'Helvetica-Oblique',
      bolditalics: 'Helvetica-BoldOblique',
    };
  } catch (error) {
    console.error('❌ Error loading Tamil fonts:', error.message);
    return {
      normal: 'Helvetica',
      bold: 'Helvetica-Bold',
      italics: 'Helvetica-Oblique',
      bolditalics: 'Helvetica-BoldOblique',
    };
  }
}

/**
 * Format currency
 */
function formatCurrency(amount) {
  const absAmount = Math.abs(amount);
  const parts = absAmount.toFixed(2).split('.');
  const integerPart = parts[0];
  const decimalPart = parts[1];
  
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
 * Get transaction time
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
 * Get particulars
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
  return isCredit ? 'Payment Out' : 'Payment In';
}

/**
 * Test PDF generation
 */
async function testPDFGeneration() {
  console.log('\n🧪 Starting local PDF generation test...\n');

  // Sample test data (mix of English and Tamil)
  const testData = {
    date: moment().format('YYYY-MM-DD'),
    shopName: 'Test Shop Name', // English shop name
    openingBalance: 10000.50,
    closingBalance: 15000.75,
    saleValue: 5000.25,
    cashOut: 2000.00,
    isLedgerClosed: true,
    transactions: [
      {
        customerName: 'Customer One', // English
        amount: 2000.00,
        isCredit: false,
        createdAt: { seconds: Math.floor(Date.now() / 1000) },
        transactionDate: moment().format('DD-MMM-YYYY'),
      },
      {
        customerName: 'Customer Two', // English
        amount: 1500.50,
        isCredit: true,
        createdAt: { seconds: Math.floor(Date.now() / 1000) },
        transactionDate: moment().format('DD-MMM-YYYY'),
      },
      {
        customerName: 'ராஜ் கடை', // Tamil
        amount: 3000.00,
        isCredit: false,
        createdAt: { seconds: Math.floor(Date.now() / 1000) },
        transactionDate: moment().format('DD-MMM-YYYY'),
      },
    ],
  };

  try {
    // Parse date
    const ledgerDate = moment(testData.date).format('DD-MMM-YYYY');
    const ledgerDateShort = moment(testData.date).format('DD-MM-YYYY');

    // Calculate final values
    const finalClosingBalance = testData.isLedgerClosed ? (testData.closingBalance || 0) : 0.0;
    const finalSaleValue = testData.isLedgerClosed ? (testData.saleValue || 0) : 0.0;
    const finalCashOut = testData.isLedgerClosed ? (testData.cashOut || 0) : 0.0;

    // Build transaction list
    const allTransactions = [
      {
        date: ledgerDateShort,
        time: '',
        particulars: 'Opening Balance',
        type: '',
        debit: testData.openingBalance,
        credit: 0.0,
      },
      ...testData.transactions.map((t) => {
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

    // Calculate totals
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

    // Load fonts
    const tamilFonts = loadTamilFonts();
    
    const fonts = {
      Helvetica: {
        normal: 'Helvetica',
        bold: 'Helvetica-Bold',
        italics: 'Helvetica-Oblique',
        bolditalics: 'Helvetica-BoldOblique',
      },
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

      const dateText = tx.time ? `${tx.date} | ${tx.time}` : tx.date;

      let creditText = '';
      if (isClosingBalance || isCashOut) {
        creditText = tx.credit !== 0 ? `Rs ${formatCurrency(tx.credit)}` : 'Rs 0.00';
      } else if (tx.credit > 0) {
        creditText = `Rs ${formatCurrency(tx.credit)}`;
      }

      let debitText = '';
      let debitColor = '#000000';
      if (isBalanceDifference) {
        debitText = tx.debit !== 0
          ? `Rs ${tx.debit < 0 ? '-' : ''}${formatCurrency(Math.abs(tx.debit))}`
          : 'Rs 0.00';
        if (tx.debit > 0) {
          debitColor = '#00AA00';
        } else if (tx.debit < 0) {
          debitColor = '#FF0000';
        }
      } else if (tx.debit > 0) {
        debitText = `Rs ${formatCurrency(tx.debit)}`;
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
        {
          text: tx.particulars,
          fontSize: 9,
          bold: isSpecialRow,
          alignment: 'left',
          margin: [6, 6, 6, 6],
          font: getFontFamily(tx.particulars),
        },
        {
          text: tx.type,
          fontSize: 9,
          bold: isSpecialRow,
          alignment: 'center',
          margin: [6, 6, 6, 6],
          font: getFontFamily(tx.type),
        },
        {
          text: creditText,
          fontSize: 9,
          bold: isSpecialRow,
          alignment: 'center',
          margin: [6, 6, 6, 6],
          font: 'Helvetica',
        },
        {
          text: debitText,
          fontSize: 9,
          bold: isSpecialRow,
          color: debitColor,
          alignment: 'center',
          margin: [6, 6, 6, 6],
          font: 'Helvetica',
        },
      ];
    });

    const totalRatio = 1.8 + 2.5 + 1.5 + 1.5 + 1.5;
    const availableWidth = 555;
    const columnWidths = [
      (1.8 / totalRatio) * availableWidth,
      (2.5 / totalRatio) * availableWidth,
      (1.5 / totalRatio) * availableWidth,
      (1.5 / totalRatio) * availableWidth,
      (1.5 / totalRatio) * availableWidth,
    ];

    const docDefinition = {
      pageSize: 'A4',
      pageMargins: [20, 20, 20, 20],
      defaultStyle: {
        font: 'Helvetica',
      },
      content: [
        {
          text: testData.shopName.toUpperCase(),
          fontSize: 16,
          bold: true,
          alignment: 'center',
          margin: [0, 0, 0, 4],
          font: getFontFamily(testData.shopName),
        },
        {
          text: `Ledger Report - Date: ${ledgerDate}`,
          fontSize: 12,
          alignment: 'center',
          margin: [0, 0, 0, 20],
          font: 'Helvetica',
        },
        {
          text: 'Transaction Details',
          fontSize: 12,
          bold: true,
          margin: [0, 0, 0, 8],
          font: 'Helvetica',
        },
        {
          table: {
            headerRows: 1,
            widths: columnWidths,
            body: [
              [
                {
                  text: 'Date',
                  fontSize: 9,
                  bold: true,
                  alignment: 'center',
                  fillColor: '#E5E5E5',
                  margin: [6, 6, 6, 6],
                  font: 'Helvetica',
                },
                {
                  text: 'Particulars',
                  fontSize: 9,
                  bold: true,
                  alignment: 'center',
                  fillColor: '#E5E5E5',
                  margin: [6, 6, 6, 6],
                  font: 'Helvetica',
                },
                {
                  text: 'Type',
                  fontSize: 9,
                  bold: true,
                  alignment: 'center',
                  fillColor: '#E5E5E5',
                  margin: [6, 6, 6, 6],
                  font: 'Helvetica',
                },
                {
                  text: 'Credit (Rs)',
                  fontSize: 9,
                  bold: true,
                  alignment: 'center',
                  fillColor: '#E5E5E5',
                  margin: [6, 6, 6, 6],
                  font: 'Helvetica',
                },
                {
                  text: 'Debit (Rs)',
                  fontSize: 9,
                  bold: true,
                  alignment: 'center',
                  fillColor: '#E5E5E5',
                  margin: [6, 6, 6, 6],
                  font: 'Helvetica',
                },
              ],
              ...tableBody,
            ],
          },
          layout: {
            hLineWidth: function (i, node) {
              if (i === 0 || i === node.table.body.length) {
                return 0.8;
              }
              return 0.3;
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
              if (rowIndex === 0) return '#E5E5E5';
              
              const particulars = row[1]?.text || '';
              if (
                particulars === 'GRAND TOTAL' ||
                particulars === 'SALES VALUE' ||
                particulars === 'CASH OUT' ||
                particulars === 'Opening Balance' ||
                particulars === 'BALANCE DIFFERENCE' ||
                particulars === 'CLOSING BALANCE'
              ) {
                return '#F5F5F5';
              }
              return null;
            },
          },
        },
        {
          margin: [0, 15, 0, 0],
          text: [
            {
              text: '"Financial stability is the foundation of success. Track every rupee, plan every expense, grow exponentially."',
              fontSize: 10,
              italics: true,
              color: '#666666',
              alignment: 'center',
              font: 'Helvetica',
            },
            '\n',
            {
              text: 'Powered by Ledger System',
              fontSize: 9,
              color: '#666666',
              alignment: 'center',
              font: 'Helvetica',
            },
          ],
        },
      ],
    };

    // Generate PDF
    const pdfDoc = printer.createPdfKitDocument(docDefinition);

    // Save to file
    const outputPath = path.join(__dirname, 'test-output.pdf');
    const writeStream = fs.createWriteStream(outputPath);
    pdfDoc.pipe(writeStream);
    pdfDoc.end();

    await new Promise((resolve, reject) => {
      writeStream.on('finish', () => {
        console.log(`\n✅ PDF generated successfully!`);
        console.log(`📄 Output file: ${outputPath}`);
        console.log(`\n📋 Test Summary:`);
        console.log(`   - Shop Name: ${testData.shopName} (English)`);
        console.log(`   - Transactions: ${testData.transactions.length} (mix of English & Tamil)`);
        console.log(`   - English text should use Helvetica font`);
        console.log(`   - Tamil text should use NotoSansTamil font`);
        console.log(`\n💡 Open the PDF file to verify both English and Tamil text render correctly.\n`);
        resolve();
      });
      writeStream.on('error', (error) => {
        console.error('❌ Error writing PDF:', error);
        reject(error);
      });
    });

  } catch (error) {
    console.error('❌ Error generating PDF:', error);
    console.error('Stack:', error.stack);
    process.exit(1);
  }
}

// Run the test
testPDFGeneration().catch((error) => {
  console.error('❌ Test failed:', error);
  process.exit(1);
});

