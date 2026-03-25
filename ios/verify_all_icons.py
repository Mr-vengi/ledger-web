"""
Verify all app icons don't have transparency
"""
from PIL import Image
import os

icon_dir = os.path.join('Runner', 'Assets.xcassets', 'AppIcon.appiconset')
icons_with_alpha = []
icons_ok = []

if os.path.exists(icon_dir):
    for filename in os.listdir(icon_dir):
        if filename.endswith('.png') and not filename.endswith('.backup'):
            icon_path = os.path.join(icon_dir, filename)
            try:
                img = Image.open(icon_path)
                if img.mode in ('RGBA', 'LA', 'P'):
                    icons_with_alpha.append(f"{filename} ({img.mode})")
                else:
                    icons_ok.append(f"{filename} ({img.mode})")
            except Exception as e:
                print(f"Error checking {filename}: {e}")

print("=" * 60)
print("App Icon Transparency Check")
print("=" * 60)

if icons_with_alpha:
    print(f"\n[WARNING] Icons with transparency ({len(icons_with_alpha)}):")
    for icon in icons_with_alpha:
        print(f"  - {icon}")
    print("\nThese icons may cause TestFlight upload errors!")
else:
    print("\n[SUCCESS] All icons are RGB mode (no transparency)")

if icons_ok:
    print(f"\n[OK] Icons without transparency ({len(icons_ok)}):")
    for icon in icons_ok[:5]:  # Show first 5
        print(f"  - {icon}")
    if len(icons_ok) > 5:
        print(f"  ... and {len(icons_ok) - 5} more")

print("\n" + "=" * 60)

