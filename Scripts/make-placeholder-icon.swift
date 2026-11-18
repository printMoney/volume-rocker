#!/usr/bin/env swift
// Draws the placeholder app icon (1024×1024 PNG). Usage: swift Scripts/make-placeholder-icon.swift out.png
// Replace it with a real icon later; see docs/APP_ICON.md.
import AppKit

let size = 1024.0
let output = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // macOS icon grid: 824×824 rounded square centred on a 1024 canvas.
    let inset = (size - 824) / 2
    let rect = NSRect(x: inset, y: inset, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
    NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.42, blue: 0.98, alpha: 1),
        NSColor(srgbRed: 0.62, green: 0.30, blue: 0.92, alpha: 1),
    ])?
        .draw(in: path, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: 440, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    }
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
