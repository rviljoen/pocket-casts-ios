import SwiftUI

struct StoryFooter2024: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 31, weight: .bold))
            Text(description)
                .font(.system(size: 15, weight: .light))
            Button(L10n.share) {
                //TODO: Implement sharing
            }
            .buttonStyle(BasicButtonStyle(textColor: .black, backgroundColor: Color.clear, borderColor: .black))
        }
        .minimumScaleFactor(0.9)
        .padding()
    }
}
