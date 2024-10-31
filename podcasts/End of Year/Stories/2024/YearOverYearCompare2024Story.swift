import SwiftUI
import PocketCastsServer
import PocketCastsDataModel

struct YearOverYearCompare2024Story: ShareableStory {
    @Environment(\.animated) var animated: Bool

    let plusOnly = true

    let subscriptionTier: SubscriptionTier
    let listeningTime: YearOverYearListeningTime

    private let foregroundColor = Color.black
    private let backgroundColor = Color(hex: "#EEB1F4")

    @ObservedObject private var animationViewModel = PlayPauseAnimationViewModel(duration: 0.8, animation: Animation.spring(_:))
    @State private var scale: Double = 1

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading) {
                Spacer()
                ZStack {
                    circles(parentSize: geometry.size)
                }
                .frame(width: geometry.size.width)//, height: geometry.size.height * 0.5)
                .modifier(animationViewModel.animate($scale, to: 1, after: 0.2))
                footerView()
            }
        }
        .onAppear {
            if animated {
                animationViewModel.play()
            }
        }
        .foregroundStyle(foregroundColor)
        .background(backgroundColor)
    }

    @ViewBuilder func circles(parentSize: CGSize) -> some View {
        HStack {
            let fontSizes = fontSizes()
            let circleSizes = circleSizes()
            let leadingCircleOffsets = circleOffset(leading: true, parentSize: parentSize)
            ZStack {
                let primaryColor = Color.white
                Circle()
                    .frame(width: parentSize.width * circleSizes.0)
                    .foregroundStyle(primaryColor)
                Text("2023")
                    .font(.custom("Humane-Medium", fixedSize: fontSizes.0))
                    .foregroundStyle(isSame ? primaryColor : backgroundColor)
            }
            .scaleEffect(CGSize(width: scale, height: scale))
            .offset(x: leadingCircleOffsets.x, y: leadingCircleOffsets.y)
            .rotationEffect(.degrees(15))
            let trailingCircleOffsets = circleOffset(leading: false, parentSize: parentSize)
            ZStack {
                let primaryColor = Color.black
                Circle()
                    .frame(width: parentSize.width * circleSizes.1)
                    .foregroundStyle(primaryColor)
                Text("2024")
                    .font(.custom("Humane-Medium", fixedSize: fontSizes.1))
                    .foregroundStyle(isSame ? primaryColor : backgroundColor)
            }
            .scaleEffect(CGSize(width: scale, height: scale))
            .offset(x: trailingCircleOffsets.x, y: trailingCircleOffsets.y)
            .rotationEffect(.degrees(-15))
        }
    }

    @ViewBuilder func footerView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SubscriptionBadge2024(subscriptionTier: subscriptionTier)
            Text(title)
                .font(.system(size: 31, weight: .bold))
            Text(description)
                .font(.system(size: 15, weight: .light))
        }
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    enum Comparison {
        case down(Double)
        case up(Double)
        case same
    }

    private func circleOffset(leading: Bool, parentSize: CGSize) -> (x: CGFloat, y: CGFloat) {
        let greater = -(parentSize.height * 0.15)
        let lesser = parentSize.height * 0.025
        switch comparison {
        case .down:
            if leading {
                return (20, greater)
            } else {
                return (-80, lesser)
            }
        case .up:
            if leading {
                return (20, greater - 100)
            } else {
                return (-80, -40)
            }
        case .same:
            if leading {
                return (20, -20)
            } else {
                return (-20, 20)
            }
        }
    }

    private var comparison: Comparison {
        comparison(in2023: listeningTime.totalPlayedTimeLastYear, in2024: listeningTime.totalPlayedTimeThisYear)
//        .up(0.1)
//        .down(0.1)
//        .same
    }

    var isSame: Bool {
        switch comparison {
        case .same:
            true
        default:
            false
        }
    }

    func fontSizes() -> (Double, Double) {
        let big: Double = 128
        let small: Double = 108
        switch comparison {
        case .down:
            return (big, small)
        case .up:
            return (small, big)
        case .same:
            return (small, big)
        }
    }

    func circleSizes() -> (Double, Double) {
        let big: Double = 0.95
        let small: Double = 0.70
        switch comparison {
        case .down:
            return (big, small)
        case .up:
            return (small, big)
        case .same:
            return (0.01, 0.01)
        }
    }

    func comparison(in2023: Double, in2024: Double) -> Comparison {
        // If the difference between them is < 10% in either direction, return .same:
        let difference = in2024 - in2023
        if abs(difference) < 0.1 {
            return .same
        } else if difference < 1 {
            return .up(difference)
        } else {
            return .down(difference)
        }
    }

    private var title: String {
        let maximumDifference: Double = 5
        let formatStyle = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))
        switch comparison {
        case .down(let difference):
            if difference > 1 {
                let formatted = min(difference, maximumDifference).formatted(formatStyle)
                return L10n.playback2024YearOverYearCompareTitleDownLot(formatted)
            } else {
                return L10n.playback2024YearOverYearCompareTitleDownLittle
            }
        case .up(let difference):
            if difference > 1 {
                let formatted = min(difference, maximumDifference).formatted(formatStyle)
                return L10n.playback2024YearOverYearCompareTitleUpLot(formatted)
            } else {
                return L10n.playback2024YearOverYearCompareTitleUpLittle
            }
        case .same:
            return L10n.playback2024YearOverYearCompareTitleSame
        }
    }

    private var description: String {
        switch comparison {
        case .down:
            L10n.playback2024YearOverYearCompareDescriptionDown
        case .up:
            L10n.playback2024YearOverYearCompareDescriptionUp
        case .same:
            L10n.playback2024YearOverYearCompareDescriptionSame
        }
    }
}

#Preview("Up") {
    YearOverYearCompare2024Story(subscriptionTier: .patron, listeningTime: YearOverYearListeningTime(totalPlayedTimeThisYear: 20, totalPlayedTimeLastYear: 300))
        .body.environment(\.animated, false)
}

#Preview("Down") {
    YearOverYearCompare2024Story(subscriptionTier: .patron, listeningTime: YearOverYearListeningTime(totalPlayedTimeThisYear: 300, totalPlayedTimeLastYear: 20))
        .body.environment(\.animated, false)
}

#Preview("Same") {
    YearOverYearCompare2024Story(subscriptionTier: .patron, listeningTime: YearOverYearListeningTime(totalPlayedTimeThisYear: 30, totalPlayedTimeLastYear: 30))
        .body.environment(\.animated, false)
}
