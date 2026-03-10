import Foundation

// MARK: - FractalKeyframe

/// A snapshot of all animatable fractal parameters at a point in time.
struct FractalKeyframe {
    var time: Double

    // View state
    var centerX: Float
    var centerY: Float
    var zoom: Float

    // Julia
    var juliaCX: Float
    var juliaCY: Float

    // Colour
    var colorOffset: Float
    var colorCycleLength: Float
    var paletteIndex: Int       // discrete — snapped, not interpolated

    // Quality
    var maxIterations: Int32    // discrete — snapped
    var fractalType: FractalType // discrete — snapped

    // MARK: Interpolation

    /// Linear interpolation between two keyframes; discrete fields snap at t = 0.5.
    static func lerp(_ a: FractalKeyframe, _ b: FractalKeyframe, t: Float) -> FractalKeyframe {
        FractalKeyframe(
            time:            a.time + Double(t) * (b.time - a.time),
            centerX:         a.centerX + t * (b.centerX - a.centerX),
            centerY:         a.centerY + t * (b.centerY - a.centerY),
            zoom:            a.zoom    + t * (b.zoom    - a.zoom),
            juliaCX:         a.juliaCX + t * (b.juliaCX - a.juliaCX),
            juliaCY:         a.juliaCY + t * (b.juliaCY - a.juliaCY),
            colorOffset:     fractMod(a.colorOffset + t * shortArc(a.colorOffset, b.colorOffset)),
            colorCycleLength: a.colorCycleLength + t * (b.colorCycleLength - a.colorCycleLength),
            paletteIndex:    t < 0.5 ? a.paletteIndex : b.paletteIndex,
            maxIterations:   t < 0.5 ? a.maxIterations : b.maxIterations,
            fractalType:     t < 0.5 ? a.fractalType   : b.fractalType
        )
    }

    /// Wrap colourOffset to [0,1) range.
    private static func fractMod(_ v: Float) -> Float {
        var r = v.truncatingRemainder(dividingBy: 1.0)
        if r < 0 { r += 1.0 }
        return r
    }

    /// Shortest arc between two colour offsets on the unit circle.
    private static func shortArc(_ a: Float, _ b: Float) -> Float {
        var d = b - a
        if d >  0.5 { d -= 1.0 }
        if d < -0.5 { d += 1.0 }
        return d
    }
}

// MARK: - RecordedSession

struct RecordedSession {
    var keyframes: [FractalKeyframe]
    var duration: Double { keyframes.last?.time ?? 0 }

    /// Interpolated keyframe at a given playback time.
    func frame(at time: Double) -> FractalKeyframe? {
        guard !keyframes.isEmpty else { return nil }
        let clampedTime = max(0, min(time, duration))

        // Binary search for the surrounding pair
        var lo = 0
        var hi = keyframes.count - 1
        while lo < hi - 1 {
            let mid = (lo + hi) / 2
            if keyframes[mid].time <= clampedTime { lo = mid } else { hi = mid }
        }

        let a = keyframes[lo]
        let b = keyframes[hi]
        if a.time == b.time { return a }
        let t = Float((clampedTime - a.time) / (b.time - a.time))
        return .lerp(a, b, t: t)
    }
}
