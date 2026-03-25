# Custom OTP Implementation Guide

## Overview
This guide explains how to implement custom OTP functionality using Node.js Cloud Functions instead of Firebase Auth's built-in phone authentication.

## 📋 Prerequisites

1. **SMS Provider** (Choose one):
   - Twilio (Recommended)
   - AWS SNS
   - Firebase Extensions (Twilio)
   - Other SMS gateway

2. **Firebase Functions** already set up
3. **Firestore** database configured

## 🚀 Step 1: Install Dependencies

If using Twilio, add it to `functions/package.json`:

```bash
cd ledger/functions
npm install twilio
```

Or add to `package.json`:
```json
{
  "dependencies": {
    "twilio": "^4.19.0"
  }
}
```

## 🔧 Step 2: Configure SMS Provider

### Option A: Using Twilio

1. Get Twilio credentials from https://www.twilio.com
2. Set Firebase config:
```bash
firebase functions:config:set twilio.account_sid="YOUR_ACCOUNT_SID"
firebase functions:config:set twilio.auth_token="YOUR_AUTH_TOKEN"
firebase functions:config:set twilio.phone_number="+1234567890"
```

3. Uncomment Twilio code in `functions/otp.js` (lines 70-80)

### Option B: Using AWS SNS

1. Install AWS SDK:
```bash
npm install aws-sdk
```

2. Configure in `otp.js`:
```javascript
const AWS = require('aws-sdk');
const sns = new AWS.SNS({
  region: 'us-east-1',
  accessKeyId: functions.config().aws.access_key_id,
  secretAccessKey: functions.config().aws.secret_access_key,
});

// In sendOTP function:
await sns.publish({
  PhoneNumber: normalizedPhone,
  Message: `Your Ledger App OTP is: ${otp}. Valid for ${OTP_EXPIRY_MINUTES} minutes.`,
}).promise();
```

## 📤 Step 3: Deploy Cloud Functions

```bash
cd ledger/functions
npm install
firebase deploy --only functions
```

This will deploy:
- `sendOTP` - Sends OTP to phone number
- `verifyOTP` - Verifies OTP code
- `resendOTP` - Resends OTP

## 📱 Step 4: Update Flutter App

### 4.1 Update `Loginscreen.dart`

Replace the Firebase Auth OTP methods with Cloud Functions calls:

```dart
import 'package:cloud_functions/cloud_functions.dart';

// Replace _sendOTP method:
Future<void> _sendOTP(String phoneNumber) async {
  try {
    setState(() => _isLoading = true);

    // Verify phone number exists in adminlogin
    final adminData = await _verifyPhoneNumberInAdminLogin(phoneNumber);
    if (adminData == null) {
      _showErrorSnackBar(
        'Phone number not registered.\n\n'
        'Please add "phoneNumber" field to adminlogin collection in Firebase.\n'
        'Or use Username & Password login instead.',
      );
      setState(() => _isLoading = false);
      return;
    }

    // Format phone number
    String formattedPhone = phoneNumber.trim();
    if (!formattedPhone.startsWith('+')) {
      if (formattedPhone.startsWith('91')) {
        formattedPhone = '+$formattedPhone';
      } else if (formattedPhone.length == 10) {
        formattedPhone = '+91$formattedPhone';
      } else {
        formattedPhone = '+$formattedPhone';
      }
    }

    // Call Cloud Function
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('sendOTP');
    
    final result = await callable.call({
      'phoneNumber': formattedPhone,
    });

    final data = result.data as Map<String, dynamic>;
    
    if (data['success'] == true) {
      setState(() {
        _verificationId = data['otpId'] as String; // Store OTP ID instead of verification ID
        _otpSent = true;
        _phoneNumber = formattedPhone;
        _isLoading = false;
      });
      _showSuccessSnackBar('OTP sent to $formattedPhone');
    } else {
      _showErrorSnackBar(data['message'] ?? 'Failed to send OTP');
      setState(() => _isLoading = false);
    }
  } catch (e) {
    debugPrint('Error sending OTP: $e');
    String errorMessage = 'Error sending OTP';
    
    if (e is FirebaseFunctionsException) {
      errorMessage = e.message ?? errorMessage;
    }
    
    _showErrorSnackBar(errorMessage);
    setState(() => _isLoading = false);
  }
}

// Replace _verifyOTP method:
Future<void> _verifyOTP(String otp) async {
  if (_verificationId == null) {
    _showErrorSnackBar('Please send OTP first');
    return;
  }

  setState(() => _isLoading = true);

  try {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('verifyOTP');
    
    final result = await callable.call({
      'otpId': _verificationId,
      'otpCode': otp,
    });

    final data = result.data as Map<String, dynamic>;
    
    if (data['success'] == true) {
      final adminData = data['adminData'] as Map<String, dynamic>;
      final username = adminData['username'] ?? 'Admin';
      final clientId = adminData['id'] ?? '';

      await Future.delayed(const Duration(milliseconds: 500));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', true);
      await prefs.setString('loginType', 'client');
      await prefs.setString('userName', username);
      await prefs.setString('clientId', clientId);

      if (mounted) {
        _showSuccessSnackBar('Welcome, $username!');

        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                const LedgerListScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    } else {
      _showErrorSnackBar(data['message'] ?? 'Invalid OTP');
      setState(() => _isLoading = false);
    }
  } on FirebaseFunctionsException catch (e) {
    debugPrint('OTP verification failed: ${e.message}');
    _showErrorSnackBar(e.message ?? 'Invalid OTP. Please try again.');
    setState(() => _isLoading = false);
  } catch (e) {
    debugPrint('Error verifying OTP: $e');
    _showErrorSnackBar('Error verifying OTP: $e');
    setState(() => _isLoading = false);
  }
}

// Replace _resendOTP method:
Future<void> _resendOTP() async {
  if (_phoneNumber.isEmpty) {
    _showErrorSnackBar('Please enter phone number first');
    return;
  }
  
  // Remove the + prefix for resend
  String phoneForResend = _phoneNumber;
  if (phoneForResend.startsWith('+')) {
    phoneForResend = phoneForResend.substring(1);
  }
  
  await _sendOTP(phoneForResend);
}
```

### 4.2 Remove Firebase Auth Phone Authentication

You can remove these imports if not used elsewhere:
- `firebase_auth` (if only used for phone auth)
- Keep it if you use email auth

### 4.3 Update State Variables

In `Loginscreen.dart`, change:
```dart
String? _verificationId; // This now stores OTP ID instead of Firebase verification ID
```

## 🧪 Step 5: Test the Implementation

1. **Test OTP Sending:**
   - Enter phone number
   - Check console logs for OTP (in development)
   - Verify SMS is received (in production)

2. **Test OTP Verification:**
   - Enter correct OTP → Should login successfully
   - Enter wrong OTP → Should show error with remaining attempts
   - Enter expired OTP → Should show expiry message

3. **Test Rate Limiting:**
   - Send multiple OTPs quickly → Should be rate limited

## 🔒 Security Considerations

1. **Rate Limiting:** Already implemented (1 OTP per minute)
2. **OTP Expiry:** 5 minutes (configurable)
3. **Max Attempts:** 3 attempts per OTP
4. **Firestore Security Rules:** Add rules for `otp_requests` collection:

```javascript
match /otp_requests/{otpId} {
  // Only allow read/write through Cloud Functions
  allow read, write: if false;
}
```

## 📊 Firestore Structure

The OTP system creates a new collection: `otp_requests`

Document structure:
```json
{
  "phoneNumber": "+919876543210",
  "otp": "123456",
  "adminDocId": "gVqhngvSiXV7fHIUVL2u",
  "attempts": 0,
  "verified": false,
  "createdAt": "2025-01-15T10:30:00Z",
  "expiresAt": "2025-01-15T10:35:00Z"
}
```

## 🚀 Deployment Checklist

- [ ] Install SMS provider SDK (Twilio/AWS SNS)
- [ ] Configure SMS provider credentials
- [ ] Deploy Cloud Functions: `firebase deploy --only functions`
- [ ] Update Flutter code to use Cloud Functions
- [ ] Test OTP sending
- [ ] Test OTP verification
- [ ] Test rate limiting
- [ ] Update Firestore security rules
- [ ] Test on production

## 💰 Cost Considerations

**Firebase Auth Phone:** ~$0.06 per verification
**Custom OTP (Twilio):** ~$0.0075 per SMS (India)
**Custom OTP (AWS SNS):** ~$0.00645 per SMS (India)

**Savings:** ~88% cheaper with custom OTP!

## ⚠️ Important Notes

1. **Do you need to rebuild the app?**
   - **Yes** - You need to update the Flutter code
   - **No full rebuild needed** - Just update code and redeploy
   - The app will work after code update, no need to rebuild APK/IPA

2. **Backward Compatibility:**
   - Old Firebase Auth OTP will stop working
   - Users need to update app to use new OTP system

3. **Testing:**
   - Use test phone numbers during development
   - Monitor Cloud Functions logs: `firebase functions:log`

## 🐛 Troubleshooting

**OTP not received:**
- Check SMS provider configuration
- Check phone number format
- Check Cloud Functions logs

**OTP verification fails:**
- Check Firestore `otp_requests` collection
- Verify OTP hasn't expired
- Check attempt limits

**Rate limiting issues:**
- Adjust `RATE_LIMIT_MINUTES` in `otp.js`
- Check Firestore indexes

## 📝 Next Steps

1. Choose SMS provider (Twilio recommended)
2. Configure credentials
3. Deploy functions
4. Update Flutter code
5. Test thoroughly
6. Deploy to production

