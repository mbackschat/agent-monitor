import SwiftUI

struct MenuBarScrollView<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var contentHeight: CGFloat = 1

    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    contentHeight = height
                }
        }
        .frame(height: min(contentHeight, maximumHeight))
        .scrollBounceBehavior(.basedOnSize)
    }
}

enum MenuBarLayout {
    static let width: CGFloat = 420
    static let maximumBodyHeight: CGFloat = 460
}
