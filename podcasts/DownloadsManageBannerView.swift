import SwiftUI
import PocketCastsUtils
import Combine

class DownloadsManageModel: ObservableObject {

    @Published var sizeOccupied: String = ""

    init(initialSize: String) {
        _sizeOccupied = .init(initialValue: initialSize)
        loadData()
    }

    func loadData() {
        Task { [weak self] in
            var totalSize = UInt64(0)
            totalSize += EpisodeManager.downloadSizeOfUnplayedEpisodes(includeStarred: true)
            totalSize += EpisodeManager.downloadSizeOfInProgressEpisodes(includeStarred: true)
            totalSize += EpisodeManager.downloadSizeOfPlayedEpisodes(includeStarred: true)
            let sizeAsStr = SizeFormatter.shared.noDecimalFormat(bytes: Int64(totalSize))
            Task { @MainActor in
                self?.sizeOccupied = sizeAsStr
            }
        }
    }

    static var shouldShowBanner: Bool {
        guard let percentage = FileManager.devicePercentageFreeSpace else {
            return false
        }
        return percentage < 0.1
    }
}

struct DownloadsManageBannerView: View {

    @EnvironmentObject var theme: Theme

    @ObservedObject var dataModel: DownloadsManageModel

    var body: some View {
        HStack(alignment: .top) {
            Image("cleanup")
                .foregroundColor(theme.primaryText01)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.manageDownloadsTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.primaryText01)
                Text(L10n.manageDownloadsDetail(dataModel.sizeOccupied))
                    .lineLimit(nil)
                    .fixedSize(horizontal: true, vertical: false)
                    .multilineTextAlignment(.leading)
                    .font(.system(size: 14))
                    .foregroundColor(theme.secondaryText02)
                Button() {

                } label: {
                    Text(L10n.manageDownloadsAction)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(theme.primaryText02Selected)
                }
            }
            Spacer()
        }
        .padding()
        .background(theme.primaryUi01)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .inset(by: 0.25)
                .stroke(theme.secondaryText02, lineWidth: 0.5)
        )
    }
}

#Preview("Light") {
    DownloadsManageBannerView(dataModel: .init(initialSize: "100 MB"))
        .environmentObject(Theme(previewTheme: .light))
        .padding(16)
        .frame(height: 132)
}

#Preview("Dark") {
    DownloadsManageBannerView(dataModel: .init(initialSize: "100 MB"))
        .environmentObject(Theme(previewTheme: .dark))
        .padding(16)
        .frame(height: 132)
}
