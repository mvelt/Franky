import SwiftUI

// MARK: - ControlPanelView

/// Collapsible HUD overlay for fractal type, palettes, colour rotation, and quality.
struct ControlPanelView: View {

    @ObservedObject var state: FractalState
    let onSavePhoto: () -> Void

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {

            // ── Toggle button ─────────────────────────────────────────────
            Button {
                withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "slider.horizontal.3")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .shadow(radius: 4)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {

                    // ── Fractal type ──────────────────────────────────────
                    fractalTypeSection

                    Divider().background(.white.opacity(0.3))

                    // ── Julia preset (only when Julia active) ─────────────
                    if state.fractalType == .julia {
                        juliaSection
                        Divider().background(.white.opacity(0.3))
                    }

                    // ── Colour palettes ───────────────────────────────────
                    paletteSection

                    Divider().background(.white.opacity(0.3))

                    // ── Colour rotation ───────────────────────────────────
                    colorRotationSection

                    Divider().background(.white.opacity(0.3))

                    // ── Quality ───────────────────────────────────────────
                    qualitySection

                    Divider().background(.white.opacity(0.3))

                    // ── Save photo ────────────────────────────────────────
                    Button {
                        onSavePhoto()
                    } label: {
                        Label("Save Photo", systemImage: "photo.badge.plus")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    // ── Reset ─────────────────────────────────────────────
                    Button {
                        withAnimation { state.resetToDefaults() }
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.trailing, 16)
        .padding(.top, 60)
    }

    // MARK: Sub-sections

    private var fractalTypeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Fractal")
            HStack(spacing: 8) {
                ForEach(FractalType.allCases) { type in
                    Button {
                        state.fractalType = type
                    } label: {
                        Text(type.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(state.fractalType == type ? .black : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                state.fractalType == type ? Color.white : Color.white.opacity(0.15),
                                in: Capsule()
                            )
                    }
                }
            }
        }
    }

    private var juliaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Julia Preset")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(JuliaPreset.all) { preset in
                        Button {
                            state.juliaCX = preset.cx
                            state.juliaCY = preset.cy
                            state.juliaCPresetIndex = preset.id
                        } label: {
                            Text(preset.name)
                                .font(.caption2)
                                .foregroundStyle(state.juliaCPresetIndex == preset.id ? .black : .white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    state.juliaCPresetIndex == preset.id
                                        ? Color.white
                                        : Color.white.opacity(0.15),
                                    in: Capsule()
                                )
                        }
                    }
                }
            }
            Text(String(format: "c = %.4f %+.4fi", state.juliaCX, state.juliaCY))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
            Text("Long-press canvas to drag c")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Palette")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ColorPalette.all) { palette in
                        Button {
                            state.paletteIndex = palette.id
                        } label: {
                            VStack(spacing: 3) {
                                PaletteSwatch(colors: palette.previewColors)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                state.paletteIndex == palette.id
                                                    ? Color.white : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                                Text(palette.name)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                    }
                }
            }
        }
    }

    private var colorRotationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Colour Rotation")

            // Play / reverse / stop row
            HStack(spacing: 10) {
                iconButton("backward.fill") {
                    state.colorRotationSpeed = -abs(state.colorRotationSpeed)
                    state.isRotatingColors = true
                }
                iconButton(state.isRotatingColors ? "stop.fill" : "play.fill") {
                    state.isRotatingColors.toggle()
                }
                iconButton("forward.fill") {
                    state.colorRotationSpeed = abs(state.colorRotationSpeed)
                    state.isRotatingColors = true
                }
            }

            // Speed slider
            HStack {
                Image(systemName: "tortoise")
                    .foregroundStyle(.white.opacity(0.7))
                Slider(
                    value: Binding(
                        get: { Double(abs(state.colorRotationSpeed)) },
                        set: { v in
                            let sign: Float = state.colorRotationSpeed >= 0 ? 1 : -1
                            state.colorRotationSpeed = sign * Float(v)
                        }
                    ),
                    in: 0.02...2.0
                )
                .accentColor(.white)
                Image(systemName: "hare")
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Cycle density slider
            HStack {
                Text("Dense")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
                Slider(value: Binding(
                    get: { Double(state.colorCycleLength) },
                    set: { state.colorCycleLength = Float($0) }
                ), in: 8.0...256.0)
                .accentColor(.white)
                Text("Sparse")
                    .font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Max Iterations: \(state.maxIterations)")
            Slider(
                value: Binding(
                    get: { Double(state.maxIterations) },
                    set: { state.maxIterations = Int32($0) }
                ),
                in: 64...2000, step: 32
            )
            .accentColor(.white)
        }
    }

    // MARK: Helpers

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.white.opacity(0.7))
            .textCase(.uppercase)
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 28)
                .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - PaletteSwatch

struct PaletteSwatch: View {
    let colors: [Color]

    var body: some View {
        LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            .frame(width: 54, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
