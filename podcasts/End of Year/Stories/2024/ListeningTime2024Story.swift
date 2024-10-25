import SwiftUI

struct ListeningTime2024Story: ShareableStory {
    @Environment(\.renderForSharing) var renderForSharing: Bool

    let listeningTime: Double

    private let backgroundColor = Color(hex: "#EDB0F3")

    enum Constants {
        static let wayToGoStickerSize: CGSize = .init(width: 197, height: 165)
    }

    var body: some View {
        let components = listeningTime.components()
        let bigNumber = components.0
        let description = L10n.playback2024ListeningTimeDescription(components.1)

        GeometryReader { geometry in
            ZStack {
                VStack {
                    Text("\(bigNumber)")
                        .lineLimit(1)
                        .font(.custom("Humane-Bold", size: geometry.size.height * 0.7))
                    Text(description)
                        .font(.system(size: 30, weight: .bold))
                }
                Image("playback-sticker-way-to-go")
                    .resizable()
                    .frame(width: Constants.wayToGoStickerSize.width, height: Constants.wayToGoStickerSize.height)
                    .position(x: 21, y: 52, for: Constants.wayToGoStickerSize, in: geometry.frame(in: .local), corner: .topLeading)
            }
        }
        .background(backgroundColor)
        .enableProportionalValueScaling()
    }

    func sharingAssets() -> [Any] {
        [
            StoryShareableProvider.new(AnyView(self)),
            StoryShareableText(L10n.eoyStoryListenedToShareText(listeningTime.storyTimeDescriptionForSharing))
        ]
    }
}

extension Double {
    func dateComponents() -> DateComponents {
        let calendar = Calendar.current
        let referenceDate = Date(timeIntervalSinceReferenceDate: Double(seconds))

        let components = calendar.dateComponents([.day, .hour, .minute, .second], from: referenceDate)

        return components
    }

    func components() -> (Int, String) {
        let components = dateComponents()
        if let days = components.day, days != 0 {
            if let hours = components.hour, hours != 0 {
                return (days, "days and \(hours) hours")
            }
            return (days, "days")
        } else if let hours = components.hour, hours != 0 {
            return (hours, "")
        } else if let minutes = components.minute, minutes != 0 {
            return (minutes, "")
        } else if let seconds = components.second, seconds != 0 {
            return (seconds, "")
        } else {
            return (0, "Unknown time")
        }
    }
}

#Preview("Days") {
    ListeningTime2024Story(listeningTime: 500*60)
}

#Preview("Hours") {
    ListeningTime2024Story(listeningTime: 60)
}
