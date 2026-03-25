"""Quick verification script for app icon"""
from PIL import Image
import os

icon_path = os.path.join('Runner', 'Assets.xcassets', 'AppIcon.appiconset', 'Icon-App-1024x1024@1x.png')

if os.path.exists(icon_path):
    img = Image.open(icon_path)
    print(f"Image mode: {img.mode}")
    print(f"Image size: {img.size}")
    print(f"Has transparency: {img.mode in ('RGBA', 'LA', 'P')}")
    if img.mode == 'RGB':
        print("✓ Icon is ready for TestFlight!")
    else:
        print("✗ Icon still has transparency. Run fix_app_icon.py")
else:
    print(f"Icon not found: {icon_path}")

