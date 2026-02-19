
import SwiftUI

/// iOS 15-compatible replacement for the iOS 16+ `NavigationLink { destination } label: {}` initializer.
///
/// Usage (drop-in):
///     CompatNavigationLink {
///         DestinationView()
///     } label: {
///         Label("Go", systemImage: "chevron.right")
///     }
struct CompatNavigationLink<Destination: View, Label: View>: View {
    private let destination: () -> Destination
    private let label: () -> Label

    init(
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.destination = destination
        self.label = label
    }

    var body: some View {
        NavigationLink(destination: destination(), label: label)
    }
}
