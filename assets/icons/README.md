# App Icons

Place your app icons in this directory:

- icon.png: Base PNG icon (at least 512x512 pixels) for Linux
- icon.icns: macOS app icon
- icon.ico: Windows app icon

## Converting Icons

### For macOS (icon.icns):
1. Create an AppIcon.iconset directory
2. Add PNG images of various sizes (16x16, 32x32, 64x64, 128x128, 256x256, 512x512, 1024x1024)
3. Run: `iconutil -c icns AppIcon.iconset -o icon.icns`

### For Windows (icon.ico):
Use an online converter like convertio.co or icoconvert.com

### For Linux:
Just use a high-resolution PNG (512x512 or higher)
