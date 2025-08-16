import Foundation

extension UIScrollView {
    func applyInsetForMiniPlayer(additionalBottomInset: CGFloat = 0) {
        let existingInset = contentInset
        contentInset = UIEdgeInsets(top: existingInset.top, left: existingInset.left, bottom: existingInset.bottom + Constants.Values.miniPlayerOffset + additionalBottomInset, right: existingInset.right)

        let existingScrollIndicatorInset = verticalScrollIndicatorInsets
        verticalScrollIndicatorInsets = UIEdgeInsets(top: existingScrollIndicatorInset.top, left: existingScrollIndicatorInset.left, bottom: existingScrollIndicatorInset.bottom + Constants.Values.miniPlayerOffset + additionalBottomInset, right: existingScrollIndicatorInset.right)
    }

    func updateContentInset(multiSelectEnabled: Bool, ignoreMiniPlayer: Bool = false) {
        let existingInset = contentInset
        let multiSelectFooterOffset: CGFloat = multiSelectEnabled ? 80 : 0

        // Check if using UITabAccessory (iOS 26.0+) - no mini player offset needed
        let miniPlayerOffset: CGFloat
        if #available(iOS 26.0, *), isUsingTabAccessory() {
            miniPlayerOffset = 0  // UITabAccessory handles content layout automatically
        } else {
            miniPlayerOffset = (ignoreMiniPlayer || PlaybackManager.shared.currentEpisode() == nil) ? 0 : Constants.Values.miniPlayerOffset
        }

        contentInset = UIEdgeInsets(top: existingInset.top, left: existingInset.left, bottom: miniPlayerOffset + multiSelectFooterOffset, right: existingInset.right)

        let existingScrollIndicatorInset = verticalScrollIndicatorInsets
        verticalScrollIndicatorInsets = UIEdgeInsets(top: existingScrollIndicatorInset.top, left: existingScrollIndicatorInset.left, bottom: miniPlayerOffset + multiSelectFooterOffset, right: existingScrollIndicatorInset.right)
    }

    @available(iOS 26.0, *)
    private func isUsingTabAccessory() -> Bool {
        // Check if the main tab bar controller has a bottom accessory
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let tabBarController = window.rootViewController as? UITabBarController else {
            return false
        }
        return tabBarController.bottomAccessory != nil
    }
}
