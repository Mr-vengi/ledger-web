/**
 * Custom OTP Service for Admin Login
 * 
 * This module handles OTP generation, sending, and verification
 * using Firebase Cloud Functions and Firestore for storage.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// OTP Configuration
const OTP_EXPIRY_MINUTES = 5; // OTP expires in 5 minutes
const OTP_LENGTH = 6;
const MAX_ATTEMPTS = 3; // Max verification attempts
const RATE_LIMIT_MINUTES = 1; // Rate limit: 1 OTP per minute per phone

/**
 * Generate random 6-digit OTP
 */
function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/**
 * Send OTP to phone number
 * 
 * This function:
 * 1. Validates phone number exists in adminlogin collection
 * 2. Checks rate limiting
 * 3. Generates OTP
 * 4. Stores OTP in Firestore with expiry
 * 5. Sends OTP via SMS (you'll need to integrate SMS provider)
 * 
 * @param {string} phoneNumber - Phone number to send OTP to
 * @returns {Promise<{success: boolean, message: string, otpId?: string}>}
 */
exports.sendOTP = functions.https.onCall(async (data, context) => {
  try {
    const { phoneNumber } = data;

    if (!phoneNumber || typeof phoneNumber !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Phone number is required'
      );
    }

    // Normalize phone number
    let normalizedPhone = phoneNumber.replace(/[+\s-]/g, '');
    if (!normalizedPhone.startsWith('+')) {
      if (normalizedPhone.startsWith('91')) {
        normalizedPhone = '+' + normalizedPhone;
      } else if (normalizedPhone.length === 10) {
        normalizedPhone = '+91' + normalizedPhone;
      } else {
        normalizedPhone = '+' + normalizedPhone;
      }
    }

    console.log('📱 Sending OTP to:', normalizedPhone);

    // 1. Verify phone number exists in adminlogin collection
    const adminSnapshot = await db.collection('adminlogin').get();
    let adminData = null;
    let adminDocId = null;

    for (const doc of adminSnapshot.docs) {
      const data = doc.data();
      const docPhone = data.phoneNumber?.toString() || '';
      
      if (!docPhone) continue;

      // Normalize document phone number
      let normalizedDocPhone = docPhone.replace(/[+\s-]/g, '');
      if (normalizedDocPhone.startsWith('+')) {
        normalizedDocPhone = normalizedDocPhone.substring(1);
      }
      const normalizedInput = normalizedPhone.startsWith('+') 
        ? normalizedPhone.substring(1) 
        : normalizedPhone;

      // Check if phone numbers match (with or without country code)
      if (
        normalizedDocPhone === normalizedInput ||
        normalizedDocPhone === normalizedInput.substring(2) ||
        normalizedInput === normalizedDocPhone.substring(2) ||
        (normalizedInput.length >= 10 && normalizedDocPhone.length >= 10 &&
         normalizedInput.substring(normalizedInput.length - 10) === 
         normalizedDocPhone.substring(normalizedDocPhone.length - 10))
      ) {
        adminData = data;
        adminDocId = doc.id;
        break;
      }
    }

    if (!adminData) {
      throw new functions.https.HttpsError(
        'not-found',
        'Phone number not registered. Please contact admin.'
      );
    }

    // 2. Check rate limiting (prevent spam)
    const otpCollection = db.collection('otp_requests');
    const recentOTPs = await otpCollection
      .where('phoneNumber', '==', normalizedPhone)
      .where('createdAt', '>', admin.firestore.Timestamp.fromDate(
        new Date(Date.now() - RATE_LIMIT_MINUTES * 60 * 1000)
      ))
      .orderBy('createdAt', 'desc')
      .limit(1)
      .get();

    if (!recentOTPs.empty) {
      const lastOTP = recentOTPs.docs[0].data();
      const timeDiff = Date.now() - lastOTP.createdAt.toMillis();
      if (timeDiff < RATE_LIMIT_MINUTES * 60 * 1000) {
        throw new functions.https.HttpsError(
          'resource-exhausted',
          `Please wait ${RATE_LIMIT_MINUTES} minute(s) before requesting another OTP.`
        );
      }
    }

    // 3. Generate OTP
    const otp = generateOTP();
    const expiresAt = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000);

    // 4. Store OTP in Firestore
    const otpDoc = await otpCollection.add({
      phoneNumber: normalizedPhone,
      otp: otp,
      adminDocId: adminDocId,
      attempts: 0,
      verified: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    });

    console.log('✅ OTP generated and stored:', otpDoc.id);

    // 5. Send OTP via SMS
    // TODO: Integrate with SMS provider (Twilio, AWS SNS, etc.)
    // For now, we'll just log it (in production, use actual SMS service)
    console.log(`📤 OTP for ${normalizedPhone}: ${otp}`);
    
    // Example: Using Twilio (uncomment and configure)
    /*
    const twilio = require('twilio');
    const accountSid = functions.config().twilio.account_sid;
    const authToken = functions.config().twilio.auth_token;
    const client = twilio(accountSid, authToken);
    
    await client.messages.create({
      body: `Your Ledger App OTP is: ${otp}. Valid for ${OTP_EXPIRY_MINUTES} minutes.`,
      from: functions.config().twilio.phone_number,
      to: normalizedPhone,
    });
    */

    // Clean up expired OTPs (background cleanup)
    cleanupExpiredOTPs();

    return {
      success: true,
      message: `OTP sent to ${normalizedPhone}`,
      otpId: otpDoc.id,
      expiresIn: OTP_EXPIRY_MINUTES * 60, // seconds
    };
  } catch (error) {
    console.error('❌ Error sending OTP:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    
    throw new functions.https.HttpsError(
      'internal',
      'Failed to send OTP. Please try again later.'
    );
  }
});

/**
 * Verify OTP
 * 
 * This function:
 * 1. Validates OTP ID and code
 * 2. Checks if OTP exists and is not expired
 * 3. Checks attempt limits
 * 4. Verifies OTP code
 * 5. Marks OTP as verified
 * 6. Returns admin details for login
 * 
 * @param {string} otpId - OTP document ID
 * @param {string} otpCode - OTP code entered by user
 * @returns {Promise<{success: boolean, adminData?: object}>}
 */
exports.verifyOTP = functions.https.onCall(async (data, context) => {
  try {
    const { otpId, otpCode } = data;

    if (!otpId || !otpCode) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'OTP ID and code are required'
      );
    }

    if (otpCode.length !== OTP_LENGTH || !/^\d+$/.test(otpCode)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Invalid OTP format'
      );
    }

    console.log('🔍 Verifying OTP:', otpId);

    // 1. Get OTP document
    const otpDoc = await db.collection('otp_requests').doc(otpId).get();

    if (!otpDoc.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        'OTP not found. Please request a new OTP.'
      );
    }

    const otpData = otpDoc.data();

    // 2. Check if already verified
    if (otpData.verified) {
      throw new functions.https.HttpsError(
        'already-exists',
        'This OTP has already been used. Please request a new OTP.'
      );
    }

    // 3. Check if expired
    const now = admin.firestore.Timestamp.now();
    if (otpData.expiresAt.toMillis() < now.toMillis()) {
      // Mark as expired
      await otpDoc.ref.update({ verified: false, expired: true });
      throw new functions.https.HttpsError(
        'deadline-exceeded',
        'OTP has expired. Please request a new OTP.'
      );
    }

    // 4. Check attempt limits
    if (otpData.attempts >= MAX_ATTEMPTS) {
      await otpDoc.ref.update({ blocked: true });
      throw new functions.https.HttpsError(
        'permission-denied',
        'Too many failed attempts. Please request a new OTP.'
      );
    }

    // 5. Verify OTP code
    if (otpData.otp !== otpCode) {
      // Increment attempts
      await otpDoc.ref.update({
        attempts: admin.firestore.FieldValue.increment(1),
      });

      const remainingAttempts = MAX_ATTEMPTS - (otpData.attempts + 1);
      throw new functions.https.HttpsError(
        'permission-denied',
        `Invalid OTP. ${remainingAttempts} attempt(s) remaining.`
      );
    }

    // 6. OTP is valid - mark as verified
    await otpDoc.ref.update({
      verified: true,
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // 7. Get admin details
    const adminDoc = await db.collection('adminlogin').doc(otpData.adminDocId).get();
    const adminData = adminDoc.data();

    console.log('✅ OTP verified successfully for:', otpData.phoneNumber);

    // Return admin data (excluding sensitive info)
    return {
      success: true,
      adminData: {
        id: adminDoc.id,
        username: adminData.username,
        email: adminData.email,
        phoneNumber: adminData.phoneNumber,
      },
    };
  } catch (error) {
    console.error('❌ Error verifying OTP:', error);
    
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    
    throw new functions.https.HttpsError(
      'internal',
      'Failed to verify OTP. Please try again.'
    );
  }
});

/**
 * Resend OTP
 * 
 * This function allows resending OTP if the previous one expired
 */
exports.resendOTP = functions.https.onCall(async (data, context) => {
  try {
    const { phoneNumber } = data;

    if (!phoneNumber) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Phone number is required'
      );
    }

    // Call sendOTP function
    return await exports.sendOTP.handler(data, context);
  } catch (error) {
    console.error('❌ Error resending OTP:', error);
    throw error;
  }
});

/**
 * Cleanup expired OTPs (background function)
 * This runs periodically to clean up old OTP records
 */
async function cleanupExpiredOTPs() {
  try {
    const expiredOTPs = await db.collection('otp_requests')
      .where('expiresAt', '<', admin.firestore.Timestamp.now())
      .where('verified', '==', false)
      .limit(100)
      .get();

    const batch = db.batch();
    expiredOTPs.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });

    if (expiredOTPs.docs.length > 0) {
      await batch.commit();
      console.log(`🧹 Cleaned up ${expiredOTPs.docs.length} expired OTPs`);
    }
  } catch (error) {
    console.error('Error cleaning up expired OTPs:', error);
  }
}

/**
 * Scheduled function to clean up expired OTPs daily
 * Uncomment and configure in firebase.json if needed
 */
/*
exports.cleanupExpiredOTPs = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    await cleanupExpiredOTPs();
  });
*/

