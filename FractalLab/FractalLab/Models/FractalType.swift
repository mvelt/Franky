import Foundation

enum FractalType: Int32, CaseIterable, Identifiable {
    case mandelbrot = 0
    case julia      = 1

    var id: Int32 { rawValue }

    var displayName: String {
        switch self {
        case .mandelbrot: return "Mandelbrot"
        case .julia:      return "Julia"
        }
    }

    var icon: String {
        switch self {
        case .mandelbrot: return "m.circle"
        case .julia:      return "j.circle"
        }
    }
}
