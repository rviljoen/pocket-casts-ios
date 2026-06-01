import SwiftUI

struct EpisodeActionView: View {
    let iconName: String
    let title: String

    var body: some View {
        HStack {
            Image(iconName, bundle: Bundle.watchAssets)
            Text(title)
                .font(.dynamic(size: 16))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .modify { view in
            if #available(watchOS 26.0, *) {
                view.glassEffect(.clear.interactive(), in: .capsule)
            } else {
                view.background(Color.background)
                    .clipShape(Capsule())
            }
        }
    }
}

struct EpisodeActionView_Previews: PreviewProvider {
    static var previews: some View {
        EpisodeActionView(iconName: "episode_download", title: L10n.download)
            .previewDevice(.largeWatch)
    }
}
