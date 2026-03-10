import SwiftUI

// MARK: - ColorPalette

struct ColorPalette: Identifiable {
    let id: Int
    let name: String
    /// Representative gradient colours for the UI swatch.
    let previewColors: [Color]

    // These must stay in sync with the palette indices in FractalShaders.metal.
    static let all: [ColorPalette] = [
        ColorPalette(id: 0, name: "Classic",
                     previewColors: [.blue, .cyan, .white, .orange]),
        ColorPalette(id: 1, name: "Fire",
                     previewColors: [.black, Color(red:0.6,green:0,blue:0), .orange, .yellow]),
        ColorPalette(id: 2, name: "Ocean",
                     previewColors: [Color(red:0,green:0.1,blue:0.4), .blue, .cyan, .white]),
        ColorPalette(id: 3, name: "Neon",
                     previewColors: [.purple, .pink, .yellow, .green, .cyan]),
        ColorPalette(id: 4, name: "Purple Haze",
                     previewColors: [.black, .purple, .indigo, Color(red:0.8,green:0.6,blue:1)]),
        ColorPalette(id: 5, name: "Sunset",
                     previewColors: [Color(red:0.4,green:0,blue:0.1), .red, .orange, .yellow]),
        ColorPalette(id: 6, name: "Ice",
                     previewColors: [.blue, .cyan, .white, Color(red:0.9,green:1,blue:1)]),
        ColorPalette(id: 7, name: "Forest",
                     previewColors: [.black, Color(red:0,green:0.3,blue:0), .green, .yellow]),
    ]
}

// MARK: - JuliaPreset

struct JuliaPreset: Identifiable {
    let id: Int
    let name: String
    let cx: Float
    let cy: Float

    static let all: [JuliaPreset] = [
        JuliaPreset(id: 0, name: "Douady's Rabbit", cx: -0.7000, cy:  0.27015),
        JuliaPreset(id: 1, name: "Siegel Disk",     cx: -0.3905, cy: -0.58679),
        JuliaPreset(id: 2, name: "Spiral",          cx:  0.2850, cy:  0.01000),
        JuliaPreset(id: 3, name: "Dendrite",        cx:  0.0000, cy:  1.00000),
        JuliaPreset(id: 4, name: "San Marco",       cx: -0.7380, cy:  0.18800),
        JuliaPreset(id: 5, name: "Cauliflower",     cx:  0.4500, cy:  0.14280),
        JuliaPreset(id: 6, name: "Airplane",        cx: -0.7017, cy: -0.38420),
        JuliaPreset(id: 7, name: "Electric",        cx: -0.8350, cy: -0.23210),
    ]
}
