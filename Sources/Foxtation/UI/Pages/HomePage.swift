import SwiftUI

struct HomePage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PagePlaceholder(title: "Home")
    }
}
