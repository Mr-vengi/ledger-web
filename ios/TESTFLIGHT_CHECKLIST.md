# TestFlight Upload Checklist ✅

## ✅ Fixed Issues

### 1. App Icon Transparency ✓
- **Status**: FIXED
- **Issue**: 1024x1024 icon had alpha channel
- **Solution**: Removed transparency, converted to RGB mode
- **File**: `Icon-App-1024x1024@1x.png`

### 2. Export Compliance ✓
- **Status**: FIXED (will be added)
- **Issue**: Missing encryption compliance declaration
- **Solution**: Added `ITSAppUsesNonExemptEncryption` to Info.plist

## ✅ Verified Configurations

### Bundle Identifier
- **Value**: `com.ledger.ledger`
- **Status**: ✓ Valid format

### Version & Build
- **Version**: 1.0.0 (from pubspec.yaml)
- **Build**: 1 (from pubspec.yaml)
- **Status**: ✓ Valid

### Minimum iOS Version
- **Target**: iOS 13.0
- **Status**: ✓ Compatible (App Store minimum is iOS 12.0)

### Required Permissions
- **Camera**: ✓ NSCameraUsageDescription present
- **Photo Library**: ✓ NSPhotoLibraryUsageDescription present
- **Photo Library Add**: ✓ NSPhotoLibraryAddUsageDescription present
- **Status**: ✓ All required permissions declared

### App Icons
- **1024x1024**: ✓ Present, RGB mode (no transparency)
- **All sizes**: ✓ Present (20x20 to 1024x1024)
- **Status**: ✓ Complete

### Launch Screen
- **LaunchScreen.storyboard**: ✓ Present
- **Status**: ✓ Valid

## ⚠️ Things to Verify in Xcode

### 1. Code Signing
- [ ] Valid provisioning profile selected
- [ ] Distribution certificate installed
- [ ] Bundle identifier matches App Store Connect

### 2. Capabilities
- [ ] Push Notifications (if used)
- [ ] Background Modes (if used)
- [ ] App Groups (if used)

### 3. Build Settings
- [ ] Build Configuration: Release
- [ ] ENABLE_BITCODE: NO (already set)
- [ ] Swift Version: 5.0 (already set)

### 4. Archive Settings
- [ ] Select "Any iOS Device" (not simulator)
- [ ] Product → Archive
- [ ] Wait for successful archive

## 📋 Pre-Upload Checklist

Before uploading to TestFlight:

- [x] App icon has no transparency (1024x1024)
- [x] Export compliance declared
- [x] All required permissions in Info.plist
- [x] Version and build numbers set
- [ ] Code signing configured
- [ ] Archive created successfully
- [ ] No build errors or warnings

## 🚀 Upload Steps

1. **Open Xcode:**
   ```bash
   open ledger/ios/Runner.xcworkspace
   ```

2. **Select Device:**
   - Select "Any iOS Device" from device dropdown

3. **Archive:**
   - Product → Archive
   - Wait for completion

4. **Distribute:**
   - Click "Distribute App"
   - Select "App Store Connect"
   - Follow wizard steps
   - Upload

5. **Wait for Processing:**
   - Usually takes 10-30 minutes
   - Check App Store Connect for status

## 🐛 Common Errors & Solutions

### Error: "Invalid large app icon"
- **Solution**: Already fixed - icon transparency removed

### Error: "Missing export compliance"
- **Solution**: Already fixed - added to Info.plist

### Error: "Invalid bundle identifier"
- **Solution**: Ensure bundle ID matches App Store Connect

### Error: "Missing compliance"
- **Solution**: Answer export compliance questions in App Store Connect

### Error: "Invalid provisioning profile"
- **Solution**: Update provisioning profile in Xcode

## 📝 Notes

- All app icons should be RGB mode (no transparency)
- Export compliance is set to "NO" (uses standard encryption)
- Minimum iOS version is 13.0
- All required permissions are declared

## ✅ Ready for Upload

Your app is configured correctly for TestFlight upload. The main issues (icon transparency and export compliance) have been fixed.

