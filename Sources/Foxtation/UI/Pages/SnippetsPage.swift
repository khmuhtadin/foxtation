import SwiftUI

struct SnippetsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PagePlaceholder(title: "Snippets")
    }
}
