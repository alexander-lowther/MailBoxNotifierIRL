
import SwiftUI
import Lottie

struct LottieLoaderView: UIViewRepresentable {
    let name: String

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: name) // looks in main bundle
        view.loopMode = .loop
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .pauseAndRestore
        view.play()
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        if !uiView.isAnimationPlaying {
            uiView.play()
        }
    }
}
