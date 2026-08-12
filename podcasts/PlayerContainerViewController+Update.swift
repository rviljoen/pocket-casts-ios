import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import UIKit

extension PlayerContainerViewController {
    func updateColors() {
        view.backgroundColor = .clear
        guard let episode = PlaybackManager.shared.currentEpisode else { return }
        ImageManager.sharedManager.imageForEpisode(episode, size: .page) { [weak self] image in
            let blurred = image.flatMap { Self.gaussianBlur($0, radius: 50) } ?? image
            DispatchQueue.main.async {
                self?.backgroundImageView.image = blurred
            }
        }
    }

    private static func gaussianBlur(_ image: UIImage, radius: CGFloat) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage,
              let cgImage = CIContext().createCGImage(output, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    @objc func update() {
        guard PlaybackManager.shared.currentEpisode != nil else {
            closeNowPlaying()

            return
        }

        updateColors()
        updateAvailableTabs()
    }

    private func updateAvailableTabs() {
        #if !APPCLIP
        guard let playingEpisode = PlaybackManager.shared.currentEpisode else { return }

        // Update the colors when the episode changes
        tabsView.themeDidChange()

        let shouldShowNotes = (playingEpisode is Episode)
        let shouldShowChapters = PlaybackManager.shared.chapterCount() > 0
        let shouldShowBookmarks = true

        // check to see if the visible views are already configured correctly
        if shouldShowNotes == showingNotes,
            shouldShowChapters == showingChapters,
            shouldShowBookmarks == showingBookmarks {
            return
        }

        mainScrollView.setContentOffset(CGPoint.zero, animated: false)
        tabsView.currentTab = 0
        showNotesItem.removeFromParent()
        showNotesItem.view.removeFromSuperview()
        showingNotes = false

        chaptersItem.removeFromParent()
        chaptersItem.view.removeFromSuperview()
        showingChapters = false

        bookmarksItem.removeFromParent()
        bookmarksItem.view.removeFromSuperview()
        showingBookmarks = false

        tabsView.tabs = [.nowPlaying]

        var previousTab: PlayerItemViewController = nowPlayingItem

        if shouldShowNotes {
            showingNotes = true
            tabsView.tabs += [.showNotes]

            addTab(showNotesItem, previousTab: &previousTab)
        }

        if shouldShowChapters {
            showingChapters = true
            tabsView.tabs += [.chapters]

            addTab(chaptersItem, previousTab: &previousTab)
        }

        if shouldShowBookmarks {
            showingBookmarks = true
            tabsView.tabs += [.bookmarks]

            addTab(bookmarksItem, previousTab: &previousTab)
        }
        #endif
    }

    private func addTab(_ tab: PlayerItemViewController, previousTab: inout PlayerItemViewController) {
        guard addTab(tab, after: previousTab) else { return }

        previousTab = tab
    }

    @discardableResult
    func addTab(_ tab: PlayerItemViewController, after afterTab: PlayerItemViewController? = nil) -> Bool {
        guard let tabView = tab.view else { return false }

        tab.willBeAddedToPlayer()
        mainScrollView.addSubview(tabView)
        addChild(tab)

        let previousAnchor = afterTab?.view.map { $0.trailingAnchor } ?? mainScrollView.leadingAnchor

        finalScrollViewConstraint?.isActive = false
        let finalConstraint = tab.view.trailingAnchor.constraint(equalTo: mainScrollView.trailingAnchor)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: previousAnchor),
            tabView.topAnchor.constraint(equalTo: mainScrollView.topAnchor),
            tabView.bottomAnchor.constraint(equalTo: mainScrollView.bottomAnchor),
            tabView.widthAnchor.constraint(equalTo: mainScrollView.widthAnchor),
            tabView.heightAnchor.constraint(equalTo: mainScrollView.heightAnchor),
            finalConstraint
        ])

        finalScrollViewConstraint = finalConstraint
        return true
    }
}
