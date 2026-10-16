import SwiftUI

struct DictionaryPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        PagePlaceholder(title: "Dictionary")
    }
}
