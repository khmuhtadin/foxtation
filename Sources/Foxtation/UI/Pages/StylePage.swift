import SwiftUI

struct StylePage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PagePlaceholder(title: "Style")
    }
}
