import SwiftUI

struct StoriesView: View {
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack {
            ZStack {
                Spacer()
                fakeStory
                    .cornerRadius(Constants.storyCornerRadius)
                storySwitcher
                header
            }

            ZStack {}
                .frame(height: Constants.spaceBetweenShareAndStory)

            shareButton
        }
        .background(Color.black)
    }

    // Header containing the close button and the rectangles
    var header: some View {
        ZStack {
            VStack {
                HStack {
                    storyIndicator
                    storyIndicator
                }
                .frame(height: Constants.storyIndicatorHeight)
                Spacer()
            }
            .padding(.leading, Constants.storyIndicatorVerticalPadding)
            .padding(.trailing, Constants.storyIndicatorVerticalPadding)

            closeButton
        }
        .padding(.top, Constants.headerTopPadding)
    }

    var fakeStory: some View {
        ZStack {
            Color.purple
        }
    }

    var closeButton: some View {
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                            .padding(Constants.closeButtonPadding)
                    }
                }
                .padding(.top, Constants.closeButtonTopPadding)
                Spacer()
            }
        }

    var storyIndicator: some View {
        GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .foregroundColor(Color.white.opacity(Constants.storyIndicatorBackgroundOpacity))
                        .cornerRadius(Constants.storyIndicatorBorderRadius)

                    Rectangle()
                        .foregroundColor(Color.white.opacity(Constants.storyIndicatorForegroundOpacity))
                        .cornerRadius(Constants.storyIndicatorBorderRadius)
                }
            }
    }

    // Invisible component to go to the next/prev story
    var storySwitcher: some View {
        HStack(alignment: .center, spacing: Constants.storySwitcherSpacing) {
            Rectangle()
                .foregroundColor(.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    print("Previous")
            }
            Rectangle()
                .foregroundColor(.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    print("Next")
            }
        }
    }

    var shareButton: some View {
        Button(action: {

        }) {
            HStack {
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundColor(.white)
                Text("Share")
                    .foregroundColor(.white)
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .padding(.top, Constants.shareButtonVerticalPadding)
        .padding(.bottom, Constants.shareButtonVerticalPadding)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.shareButtonCornerRadius)
                .stroke(.white, style: StrokeStyle(lineWidth: Constants.shareButtonBorderSize))
        )
        .padding(.leading, Constants.shareButtonHorizontalPadding)
        .padding(.trailing, Constants.shareButtonHorizontalPadding)
    }
}

// MARK: - Constants

private extension StoriesView {
    struct Constants {
        static let storyIndicatorHeight: CGFloat = 2
        static let storyIndicatorVerticalPadding: CGFloat = 13
        static let headerTopPadding: CGFloat = 5

        static let closeButtonPadding: CGFloat = 13
        static let closeButtonTopPadding: CGFloat = 5

        static let storyIndicatorBorderRadius: CGFloat = 5
        static let storyIndicatorBackgroundOpacity: CGFloat = 0.3
        static let storyIndicatorForegroundOpacity: CGFloat = 0.9

        static let storySwitcherSpacing: CGFloat = 0

        static let shareButtonVerticalPadding: CGFloat = 10
        static let shareButtonHorizontalPadding: CGFloat = 5
        static let shareButtonCornerRadius: CGFloat = 10
        static let shareButtonBorderSize: CGFloat = 1

        static let spaceBetweenShareAndStory: CGFloat = 15

        static let storyCornerRadius: CGFloat = 15
    }
}

// MARK: - Preview Provider

struct StoriesView_Previews: PreviewProvider {
    static var previews: some View {
        StoriesView()
    }
}