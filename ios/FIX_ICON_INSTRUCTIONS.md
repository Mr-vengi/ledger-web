# Fix iOS App Icon for TestFlight

## Problem
TestFlight/App Store requires app icons to have **no transparency/alpha channel**. The error message:
```
Invalid large app icon. The large app icon in the asset catalog in "Runner.app" 
can't be transparent or contain an alpha channel.
```

## Solution

### Option 1: Automatic Fix (Recommended)

**On Windows:**
1. Open Command Prompt or PowerShell
2. Navigate to the `ledger/ios` folder
3. Run: `fix_app_icon.bat`

**On Mac/Linux:**
1. Open Terminal
2. Navigate to the `ledger/ios` folder
3. Run: `python3 fix_app_icon.py`

The script will:
- Create a backup of your original icon
- Remove the alpha channel by compositing on white background
- Save the fixed icon

### Option 2: Manual Fix with Image Editor

1. Open `ledger/ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png` in an image editor
2. Remove transparency:
   - **Photoshop/GIMP**: Flatten image, remove alpha channel
   - **Online Tool**: Use https://www.remove.bg or similar
   - **Paint.NET**: Layer → Flatten, then save as PNG without alpha
3. Ensure the icon is exactly **1024x1024 pixels**
4. Save as PNG (RGB mode, no alpha channel)

### Option 3: Using Online Tools

1. Go to https://www.iloveimg.com/remove-background
2. Upload your 1024x1024 icon
3. Remove background or add white background
4. Download and replace the icon file

## Verification

After fixing, verify the icon:
- Open the PNG file
- Check it has no transparency
- Ensure it's 1024x1024 pixels
- File should be RGB mode (not RGBA)

## Requirements

- **Size**: Exactly 1024x1024 pixels
- **Format**: PNG
- **Color Mode**: RGB (no alpha channel)
- **No Transparency**: Solid background required

## After Fixing

1. Clean Xcode build: `flutter clean`
2. Rebuild iOS: `flutter build ios --release`
3. Archive in Xcode
4. Upload to TestFlight

## Troubleshooting

**Python not found:**
- Install Python 3.x from https://www.python.org/
- Make sure to check "Add Python to PATH" during installation

**Pillow not installed:**
- Run: `pip install Pillow`

**Still getting error:**
- Make sure you're fixing the correct file: `Icon-App-1024x1024@1x.png`
- Check all icon sizes don't have transparency
- Clean and rebuild: `flutter clean && flutter build ios`

