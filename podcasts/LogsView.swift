import Foundation
import SwiftUI
import PocketCastsUtils

struct LogsView: View {
    @State var logs: String = ""

    @EnvironmentObject var theme: Theme

    private func load() async {
        let result = await FileLog.shared.logFileAsString()
        await MainActor.run {
            self.logs = result
        }
    }

    var body: some View {
        VStack {
            TextEditor(text: $logs)
            Spacer()
        }
        .navigationTitle("Logs")
        .toolbar(content: {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {

                }, label: {
                    Image("mail")
                })
            }
        })
        .applyDefaultThemeOptions()
        .ignoresSafeArea()
        .task {
            await load()
        }
    }
}

#Preview {
    LogsView(logs: """
Line 1
Line 2
Line 3
Line 4
Line 5
Line 6
Line 7
Line 8
Line 9
Line 10
Line 11
""")
    .setupDefaultEnvironment()
}
