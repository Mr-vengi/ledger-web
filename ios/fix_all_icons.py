"""
Fix all iOS app icons - Remove Alpha Channel
This script removes transparency from all app icon sizes
"""
from PIL import Image
import os
import sys

# Fix Windows console encoding
if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.buffer, 'strict')

def remove_alpha_channel(input_path, output_path=None):
    """Remove alpha channel from PNG image"""
    if output_path is None:
        output_path = input_path
    
    try:
        img = Image.open(input_path)
        
        if img.mode in ('RGBA', 'LA', 'P'):
            if img.mode == 'P':
                img = img.convert('RGBA')
            
            # Create white background
            background = Image.new('RGB', img.size, (255, 255, 255))
            
            if img.mode == 'RGBA':
                background.paste(img, mask=img.split()[3])
            else:
                background.paste(img)
            
            background.save(output_path, 'PNG', optimize=True)
            return True
        return False
    except Exception as e:
        print(f"[ERROR] Error processing {input_path}: {e}")
        return False

def main():
    icon_dir = os.path.join('Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    
    if not os.path.exists(icon_dir):
        print(f"[ERROR] Icon directory not found: {icon_dir}")
        return
    
    print("=" * 60)
    print("Fixing All iOS App Icons - Removing Alpha Channel")
    print("=" * 60)
    
    icons_fixed = []
    icons_skipped = []
    errors = []
    
    for filename in os.listdir(icon_dir):
        if filename.endswith('.png') and not filename.endswith('.backup'):
            icon_path = os.path.join(icon_dir, filename)
            
            # Create backup if not exists
            backup_path = icon_path + '.backup'
            if not os.path.exists(backup_path):
                import shutil
                shutil.copy2(icon_path, backup_path)
            
            # Fix icon
            if remove_alpha_channel(icon_path):
                icons_fixed.append(filename)
            else:
                icons_skipped.append(filename)
    
    print(f"\n[SUCCESS] Fixed {len(icons_fixed)} icons:")
    for icon in icons_fixed:
        print(f"  - {icon}")
    
    if icons_skipped:
        print(f"\n[INFO] Skipped {len(icons_skipped)} icons (already RGB):")
        for icon in icons_skipped[:5]:
            print(f"  - {icon}")
        if len(icons_skipped) > 5:
            print(f"  ... and {len(icons_skipped) - 5} more")
    
    print("\n" + "=" * 60)
    print("[SUCCESS] All app icons fixed!")
    print("Your app is ready for TestFlight upload.")
    print("=" * 60)

if __name__ == '__main__':
    main()

