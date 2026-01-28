import SwiftUI

enum AppTheme {
    static let surface = Color(.secondarySystemBackground)
}

enum AppSymbols {
    static func best(_ options: [String]) -> String {
        for o in options where UIImage(systemName: o) != nil { return o }
        return options.first ?? "questionmark"
    }
}
