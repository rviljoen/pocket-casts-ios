import UIKit
import PocketCastsServer

class ChaptersViewController: PlayerItemViewController {
    var isTogglingChapters = false
    var showsCompactPlayerHeader = false

    var numberOfDeselectedChapters = 0

    @IBOutlet var chaptersTable: UITableView! {
        didSet {
            registerCells()
            chaptersTable.backgroundView = nil
        }
    }

    private(set) lazy var header: ChaptersHeader = {
        let header = ChaptersHeader()
        header.delegate = self
        return header
    }()

    private let compactHeaderView = UIView()
    private let compactArtworkView = UIImageView()
    private let compactEpisodeTitleLabel = UILabel()
    private let compactPodcastTitleLabel = UILabel()
    private var tableTopConstraint: NSLayoutConstraint?

    lazy var playbackManager: PlaybackManager = PlaybackManager.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        chaptersTable.sectionHeaderTopPadding = 0
        setupCompactHeaderIfNeeded()
    }

    override func willBeAddedToPlayer() {
        updateColors()
        addObservers()
        updateCompactHeader()
    }

    override func willBeRemovedFromPlayer() {
        removeAllCustomObservers()
    }

    override func themeDidChange() {
        update()
    }

    func scrollToCurrentlyPlayingChapter(animated: Bool) {
        let currentChapter = PlaybackManager.shared.currentChapters()

        guard let index = playbackManager.index(for: currentChapter) else {
            return
        }

        // scroll far enough to at least see the current chapter + a few more
        chaptersTable.scrollToRow(at: IndexPath(item: index, section: 0), at: .middle, animated: animated)
    }

    private func addObservers() {
        addCustomObserver(Constants.Notifications.episodeDurationChanged, selector: #selector(update))
        addCustomObserver(Constants.Notifications.playbackStarted, selector: #selector(update))
        addCustomObserver(Constants.Notifications.playbackPaused, selector: #selector(update))
        addCustomObserver(Constants.Notifications.playbackTrackChanged, selector: #selector(update))
        addCustomObserver(Constants.Notifications.podcastChaptersDidUpdate, selector: #selector(update))
        addCustomObserver(Constants.Notifications.podcastChapterChanged, selector: #selector(update))
        addCustomObserver(UIApplication.willEnterForegroundNotification, selector: #selector(update))
        addCustomObserver(ServerNotifications.iapPurchaseCompleted, selector: #selector(enableOrDisableChapterSelectionIfUserJustPurchased))
        addCustomObserver(.episodeEmbeddedArtworkLoaded, selector: #selector(update))
    }

    @objc private func update() {
        chaptersTable.reloadData()
        updateColors()
        updateCompactHeader()
    }

    @objc private func enableOrDisableChapterSelectionIfUserJustPurchased() {
        DispatchQueue.main.async { [weak self] in
            self?.isTogglingChapters = PaidFeature.deselectChapters.isUnlocked ? true : false
            self?.header.isTogglingChapters = self?.isTogglingChapters ?? false
            self?.header.update()
            self?.chaptersTable.reloadSections([0], with: .automatic)
        }
    }

    private func updateColors() {
        view.backgroundColor = PlayerColorHelper.playerBackgroundColor01()
        chaptersTable.backgroundColor = PlayerColorHelper.playerBackgroundColor01()
        header.backgroundColor = PlayerColorHelper.playerBackgroundColor01()
        compactEpisodeTitleLabel.textColor = ThemeColor.playerContrast01()
        compactPodcastTitleLabel.textColor = ThemeColor.playerContrast02()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            updateSize()
        }
    }

    func updateSize() {
        /// Forces headers & cells to recalculate their heights
        chaptersTable.beginUpdates()
        chaptersTable.endUpdates()
    }

    private func setupCompactHeaderIfNeeded() {
        guard showsCompactPlayerHeader else {
            return
        }

        tableTopConstraint = view.constraints.first(where: { constraint in
            (constraint.firstItem as? UIView) === chaptersTable && constraint.firstAttribute == .top
        })
        tableTopConstraint?.isActive = false

        compactHeaderView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(compactHeaderView)

        compactArtworkView.translatesAutoresizingMaskIntoConstraints = false
        compactArtworkView.layer.cornerRadius = 8
        compactArtworkView.layer.masksToBounds = true
        compactArtworkView.contentMode = .scaleAspectFill
        compactHeaderView.addSubview(compactArtworkView)

        compactEpisodeTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        compactEpisodeTitleLabel.font = .font(ofSize: 16, weight: .semibold, scalingWith: .title3)
        compactEpisodeTitleLabel.adjustsFontForContentSizeCategory = true
        compactEpisodeTitleLabel.numberOfLines = 2
        compactHeaderView.addSubview(compactEpisodeTitleLabel)

        compactPodcastTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        compactPodcastTitleLabel.font = .font(ofSize: 13, weight: .medium, scalingWith: .body)
        compactPodcastTitleLabel.adjustsFontForContentSizeCategory = true
        compactPodcastTitleLabel.numberOfLines = 1
        compactHeaderView.addSubview(compactPodcastTitleLabel)

        NSLayoutConstraint.activate([
            compactHeaderView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            compactHeaderView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            compactHeaderView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),

            compactArtworkView.leadingAnchor.constraint(equalTo: compactHeaderView.leadingAnchor),
            compactArtworkView.topAnchor.constraint(equalTo: compactHeaderView.topAnchor),
            compactArtworkView.widthAnchor.constraint(equalToConstant: 56),
            compactArtworkView.heightAnchor.constraint(equalToConstant: 56),
            compactArtworkView.bottomAnchor.constraint(lessThanOrEqualTo: compactHeaderView.bottomAnchor),

            compactEpisodeTitleLabel.topAnchor.constraint(equalTo: compactHeaderView.topAnchor, constant: 2),
            compactEpisodeTitleLabel.leadingAnchor.constraint(equalTo: compactArtworkView.trailingAnchor, constant: 12),
            compactEpisodeTitleLabel.trailingAnchor.constraint(equalTo: compactHeaderView.trailingAnchor),

            compactPodcastTitleLabel.topAnchor.constraint(equalTo: compactEpisodeTitleLabel.bottomAnchor, constant: 6),
            compactPodcastTitleLabel.leadingAnchor.constraint(equalTo: compactEpisodeTitleLabel.leadingAnchor),
            compactPodcastTitleLabel.trailingAnchor.constraint(equalTo: compactEpisodeTitleLabel.trailingAnchor),
            compactPodcastTitleLabel.bottomAnchor.constraint(equalTo: compactHeaderView.bottomAnchor, constant: -2),

            chaptersTable.topAnchor.constraint(equalTo: compactHeaderView.bottomAnchor, constant: 12)
        ])
    }

    private func updateCompactHeader() {
        guard showsCompactPlayerHeader,
              let episode = PlaybackManager.shared.currentEpisode() else {
            return
        }

        compactEpisodeTitleLabel.text = episode.displayableTitle()
        compactPodcastTitleLabel.text = episode.subTitle()

        if let chapterArtwork = PlaybackManager.shared.currentChapters().artwork {
            compactArtworkView.image = chapterArtwork
        } else {
            compactArtworkView.image = nil
            ImageManager.sharedManager.loadImage(episode: episode, imageView: compactArtworkView, size: .page)
        }
    }
}
