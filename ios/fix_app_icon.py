"""
Fix iOS App Icon - Remove Alpha Channel
This script removes transparency/alpha channel from the 1024x1024 app icon
to make it compatible with TestFlight/App Store requirements.
"""

import os
import sys
from PIL import Image

# Fix Windows console encoding for emojis
if sys.platform == 'win32':
    import codecs
    sys.stdout = codecs.getwriter('utf-8')(sys.stdout.buffer, 'strict')
    sys.stderr = codecs.getwriter('utf-8')(sys.stderr.buffer, 'strict')

def remove_alpha_channel(input_path, output_path=None):
    """
    Remove alpha channel from PNG image by compositing on white background.
    
    Args:
        input_path: Path to input PNG file
        output_path: Path to output PNG file (default: overwrites input)
    """
    if output_path is None:
        output_path = input_path
    
    try:
        # Open the image
        img = Image.open(input_path)
        
        # Check if image has alpha channel
        if img.mode in ('RGBA', 'LA', 'P'):
            print(f"[INFO] Found image with alpha channel: {img.mode}")
            
            # Create white background
            if img.mode == 'P':
                # Convert palette mode to RGBA first
                img = img.convert('RGBA')
            
            # Create white background
            background = Image.new('RGB', img.size, (255, 255, 255))
            
            # Composite the image on white background
            if img.mode == 'RGBA':
                background.paste(img, mask=img.split()[3])  # Use alpha channel as mask
            else:
                background.paste(img)
            
            # Save as RGB (no alpha channel)
            background.save(output_path, 'PNG', optimize=True)
            print(f"[SUCCESS] Successfully removed alpha channel: {output_path}")
            print(f"         New mode: RGB (no transparency)")
            return True
        else:
            print(f"[INFO] Image already has no alpha channel: {img.mode}")
            return False
            
    except Exception as e:
        print(f"[ERROR] Error processing image: {e}")
        return False

def main():
    # Path to the 1024x1024 icon
    icon_path = os.path.join(
        os.path.dirname(__file__),
        'Runner',
        'Assets.xcassets',
        'AppIcon.appiconset',
        'Icon-App-1024x1024@1x.png'
    )
    
    # Check if file exists
    if not os.path.exists(icon_path):
        print(f"[ERROR] Icon file not found: {icon_path}")
        return
    
    print("=" * 60)
    print("Fixing iOS App Icon - Removing Alpha Channel")
    print("=" * 60)
    print(f"Input: {icon_path}")
    
    # Create backup
    backup_path = icon_path + '.backup'
    if not os.path.exists(backup_path):
        import shutil
        shutil.copy2(icon_path, backup_path)
        print(f"[BACKUP] Created backup: {backup_path}")
    
    # Remove alpha channel
    success = remove_alpha_channel(icon_path)
    
    if success:
        print("\n" + "=" * 60)
        print("[SUCCESS] App icon fixed successfully!")
        print("You can now upload to TestFlight without errors.")
        print("=" * 60)
    else:
        print("\n[WARNING] Icon may already be fixed or an error occurred.")

if __name__ == '__main__':
    main()

