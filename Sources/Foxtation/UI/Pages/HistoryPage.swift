import SwiftUI

struct HistoryPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PagePlaceholder(title: "History")
    }
}
