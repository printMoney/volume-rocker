# Replacing the app icon

The current icon is a placeholder drawn by `Scripts/make-placeholder-icon.swift`.

1. Design a **1024 × 1024 PNG**. Follow Apple's macOS icon grid: the artwork is a rounded square of about 824 × 824 centred on the canvas, with transparent space around it. Apple's [icon templates](https://developer.apple.com/design/resources/) help, and on macOS 26 you can use the Icon Composer app to make a Liquid Glass icon.
2. Run:

   ```bash
   Scripts/make-icon-set.sh path/to/your-icon-1024.png
   ```

   This creates every required size in `VolumeRocker/Resources/Assets.xcassets/AppIcon.appiconset`.
3. Rebuild the app. If the old icon still shows in Finder, run `killall Dock`.

Run `Scripts/make-icon-set.sh` without an argument to restore the placeholder.
