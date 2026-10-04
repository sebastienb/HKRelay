import SwiftUI

#if targetEnvironment(macCatalyst)
import UIKit

struct CatalystWindowSizeConfigurator: UIViewRepresentable {
    let minimumSize: CGSize

    func makeUIView(context: Context) -> WindowConfigurationView {
        WindowConfigurationView(minimumSize: minimumSize)
    }

    func updateUIView(_ uiView: WindowConfigurationView, context: Context) {
        uiView.minimumSize = minimumSize
        uiView.applyRestrictions()
    }
}

final class WindowConfigurationView: UIView {
    var minimumSize: CGSize

    init(minimumSize: CGSize) {
        self.minimumSize = minimumSize
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyRestrictions()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyRestrictions()
    }

    func applyRestrictions() {
        guard let restrictions = window?.windowScene?.sizeRestrictions else { return }

        restrictions.minimumSize = minimumSize
        restrictions.maximumSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        restrictions.allowsFullScreen = true
    }
}
#else
struct CatalystWindowSizeConfigurator: View {
    let minimumSize: CGSize

    var body: some View {
        EmptyView()
    }
}
#endif
