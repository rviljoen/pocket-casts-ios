import Foundation
import SwiftUI
import PocketCastsUtils
import MessageUI

class LogsViewModel: NSObject, ObservableObject, MFMailComposeViewControllerDelegate {
    @Published var logs = ""
    var presenter: UIViewController?

    init(presenter: UIViewController? = nil) {
        self.presenter = presenter
    }

    func load() async {
        let result = await FileLog.shared.logFileAsString()
        await MainActor.run {
            self.logs = result
        }
    }

    func mailLogs() {
        guard MFMailComposeViewController.canSendMail() else {
            return
        }
        let mailVC = MFMailComposeViewController()
        mailVC.mailComposeDelegate = self

        mailVC.setSubject("Logs")
        mailVC.setToRecipients(["support@pocketcasts.com"])
        mailVC.setMessageBody(logs, isHTML: false)

        presenter?.present(mailVC, animated: true)
    }

    func mailComposeController(_ controller: MFMailComposeViewController,
                                       didFinishWith result: MFMailComposeResult,
                               error: Error?) {
        presenter?.dismiss(animated: true)
    }

}

struct LogsView: View {
    @StateObject var model: LogsViewModel

    @EnvironmentObject var theme: Theme

    var body: some View {
        VStack {
            TextEditor(text: $model.logs)
            Spacer()
        }
        .navigationTitle("Logs")
        .toolbar(content: {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    model.mailLogs()
                }, label: {
                    Image("mail")
                })
            }
        })
        .applyDefaultThemeOptions()
        .ignoresSafeArea()
        .task {
            await model.load()
        }
    }
}

#Preview {
    LogsView(model: LogsViewModel())
    .setupDefaultEnvironment()
}
