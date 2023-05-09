/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */
  


import CoreData
import ObvUI
import ObvTypes
import UIKit


/// We implement the list of groups using a plain collection view. Since we require this view controller to be used under iOS 13, we cannot use modern  techniques (such as list in collection views or UIContentConfiguration).
final class NewAllGroupsViewController: ShowOwnedIdentityButtonUIViewController, ViewControllerWithEllipsisCircleRightBarButtonItem, NSFetchedResultsControllerDelegate, UICollectionViewDelegate, HeaderViewDelegate, UISearchResultsUpdating {
    
    // Delegates
    
    weak var delegate: NewAllGroupsViewControllerDelegate?

    init(ownedCryptoId: ObvCryptoId) {
        self.frc = Self.configureFrc(ownedCryptoId: ownedCryptoId, with: nil)
        super.init(ownedCryptoId: ownedCryptoId, logCategory: "NewAllGroupsViewController")
        self.title = CommonString.Word.Groups
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var frc: NSFetchedResultsController<DisplayedContactGroup>
    private var collectionView: UICollectionView!
    private let viewForCreatingFirstGroup = ViewForCreatingFirstGroup()
    private var constraintsWhenViewForCreatingFirstGroupIsShown = [NSLayoutConstraint]()
    private var constraintsWhenViewForCreatingFirstGroupIsHidden = [NSLayoutConstraint]()
    private var dataSource: UICollectionViewDiffableDataSource<Int, NSManagedObjectID>! = nil
    private var viewDidLoadWasCalled = false

    // Implementing search using this view controller as the search results controller
    
    private let searchController = UISearchController(searchResultsController: nil)
    private var searchPredicate: NSPredicate? {
        didSet {
            self.frc = Self.configureFrc(ownedCryptoId: currentOwnedCryptoId, with: searchPredicate)
            self.frc.delegate = self
            try? self.frc.performFetch()
            collectionView.reloadData()
        }
    }
    
    
    private var searchInProgress: Bool {
        searchPredicate != nil
    }
    
    
    /// Used both when performing the initial configuration of the frc, and each time we perform a fetch.
    private static func configureFrc(ownedCryptoId: ObvCryptoId, with searchPredicate: NSPredicate?) -> NSFetchedResultsController<DisplayedContactGroup> {
        let fetchRequest = DisplayedContactGroup.getFetchRequestForAllDisplayedContactGroup(ownedIdentity: ownedCryptoId,
                                                                                            andPredicate: searchPredicate)
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: ObvStack.shared.viewContext,
                                          sectionNameKeyPath: DisplayedContactGroup.Predicate.Key.sectionName.rawValue,
                                          cacheName: nil)
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadWasCalled = true
        
        configureHierarchy()
        configureDataSource()
        
        var rightBarButtonItems = [UIBarButtonItem]()
        
        if #available(iOS 14, *) {
            let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem()
            rightBarButtonItems.append(ellipsisButton)
        } else {
            let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem(selector: #selector(ellipsisButtonTappedSelector))
            rightBarButtonItems.append(ellipsisButton)
        }
        
        navigationItem.rightBarButtonItems = rightBarButtonItems

        collectionView.delegate = self
        // The following line allows to make the UIButton located in the header more responsive
        collectionView.delaysContentTouches = false
        
        configureSearchController()
        
    }
    
    
    // MARK: - Switching current owned identity

    @MainActor
    override func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        await super.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        guard viewDidLoadWasCalled else { return }
        self.frc = Self.configureFrc(ownedCryptoId: newOwnedCryptoId, with: nil)
        self.frc.delegate = self
        try? self.frc.performFetch()
        collectionView.reloadData()
    }

    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        clearSelection(animated: animated)
    }
    
    
    private func configureSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = true
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    
    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "Used because iOS 13 does not support UIMenu on UIBarButtonItem")
    @objc private func ellipsisButtonTappedSelector() {
        ellipsisButtonTapped(sourceBarButtonItem: navigationItem.rightBarButtonItem)
    }

    
    func clearSelection(animated: Bool) {
        collectionView.indexPathsForSelectedItems?.forEach({ (indexPath) in
            collectionView.deselectItem(at: indexPath, animated: animated)
        })
    }

    
    // MARK: Configuring the view hierarchy

    private func configureHierarchy() {
        
        viewForCreatingFirstGroup.translatesAutoresizingMaskIntoConstraints = false
        viewForCreatingFirstGroup.delegate = self
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        collectionView.backgroundColor = .clear
        
        constraintsWhenViewForCreatingFirstGroupIsHidden = [
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ]

        constraintsWhenViewForCreatingFirstGroupIsShown = [
            viewForCreatingFirstGroup.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            viewForCreatingFirstGroup.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            viewForCreatingFirstGroup.bottomAnchor.constraint(equalTo: collectionView.topAnchor),
            viewForCreatingFirstGroup.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),

            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ]

        NSLayoutConstraint.activate(constraintsWhenViewForCreatingFirstGroupIsHidden)
        viewForCreatingFirstGroup.isHidden = true

        collectionView.register(ObvSubtitleCollectionViewCell.self, forCellWithReuseIdentifier: "GroupCell")
        collectionView.register(HeaderView.self, forSupplementaryViewOfKind: ElementKind.sectionHeader.rawValue, withReuseIdentifier: HeaderView.reuseIdentifier)
        collectionView.register(FooterView.self, forSupplementaryViewOfKind: ElementKind.sectionFooter.rawValue, withReuseIdentifier: FooterView.reuseIdentifier)

    }

    enum ElementKind: String {
        case sectionHeader = "section-header-element-kind"
        case sectionFooter = "section-footer-element-kind"
    }
    
    private func createLayout() -> UICollectionViewLayout {
        
        let estimatedHeight = CGFloat(100)
        let layoutSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                               heightDimension: .estimated(estimatedHeight))
        
        let item = NSCollectionLayoutItem(layoutSize: layoutSize)
        
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: layoutSize,
                                                       subitem: item,
                                                       count: 1)
        
        let section = NSCollectionLayoutSection(group: group)

        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                heightDimension: .estimated(44))
        let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: headerSize,
            elementKind: NewAllGroupsViewController.ElementKind.sectionHeader.rawValue,
            alignment: .top)
        sectionHeader.pinToVisibleBounds = true

        let footerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0),
                                                heightDimension: .estimated(16))
        let sectionFooter = NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: footerSize,
            elementKind: NewAllGroupsViewController.ElementKind.sectionFooter.rawValue,
            alignment: .bottom)
        sectionFooter.pinToVisibleBounds = false

        section.boundarySupplementaryItems = [sectionHeader, sectionFooter]

        let config = UICollectionViewCompositionalLayoutConfiguration()
        config.interSectionSpacing = 10
        let layout = UICollectionViewCompositionalLayout(section: section, configuration: config)
        
        return layout
        
    }

    
    // MARK: Configure the data source

    private func configureDataSource() {
        
        self.frc.delegate = self

        dataSource = UICollectionViewDiffableDataSource<Int, NSManagedObjectID>(collectionView: collectionView) { [weak self] (collectionView: UICollectionView, indexPath: IndexPath, objectID: NSManagedObjectID) -> UICollectionViewCell? in
            let groupCell = collectionView.dequeueReusableCell(withReuseIdentifier: "GroupCell", for: indexPath) as! ObvSubtitleCollectionViewCell
            if let displayedContactGroup = try? DisplayedContactGroup.get(objectID: objectID, within: ObvStack.shared.viewContext) {
                self?.configure(groupCell: groupCell, with: displayedContactGroup)
            } else {
                assertionFailure()
            }
            return groupCell
        }

        dataSource.supplementaryViewProvider = { [weak self] (collectionView: UICollectionView, kind: String, indexPath: IndexPath) -> UICollectionReusableView? in
            guard let element = ElementKind(rawValue: kind) else { assertionFailure(); return nil }
            switch element {
            case .sectionHeader:
                guard let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: HeaderView.reuseIdentifier, for: indexPath) as? HeaderView else {
                    assertionFailure(); return nil
                }
                self?.configure(headerView: headerView, at: indexPath)
                headerView.delegate = self
                return headerView
            case .sectionFooter:
                return collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: FooterView.reuseIdentifier, for: indexPath)
            }
        }

        try? frc.performFetch()

    }

    
    private func configure(groupCell: ObvSubtitleCollectionViewCell, with displayedContactGroup: DisplayedContactGroup) {
        let badge: ObvSubtitleCollectionViewCell.BadgeType
        if displayedContactGroup.updateInProgress {
            badge = .spinner
        } else {
            switch displayedContactGroup.publishedDetailsStatus {
            case .noNewPublishedDetails:
                badge = .none
            case .seenPublishedDetails:
                badge = .symbol(systemIcon: .personTextRectangle, color: .secondaryLabel)
            case .unseenPublishedDetails:
                badge = .symbol(systemIcon: .personTextRectangle, color: .red)
            }
        }
        let configuration = ObvSubtitleCollectionViewCell.Configuration(
            title: displayedContactGroup.displayedTitle,
            subtitle: displayedContactGroup.subtitle,
            circledInitialsConfiguration: displayedContactGroup.circledInitialsConfiguration,
            badge: badge
        )
        groupCell.configure(with: configuration)
    }
    
    
    private func configure(headerView: HeaderView, at indexPath: IndexPath) {
        let numberOfSections = frc.sections?.count ?? 0
        switch numberOfSections {
        case 0:
            assertionFailure()
        case 1:
            // We must determine if we only have administrated groups, or joined groups
            guard let displayedGroup = frc.fetchedObjects?.first else { return }
            if displayedGroup.ownPermissionAdmin {
                let configuration = HeaderView.Configuration(
                    title: NSLocalizedString("GROUPS_THAT_YOU_ADMINISTER", comment: ""),
                    showGroupCreationButton: !searchInProgress)
                headerView.configure(with: configuration)
            } else {
                let configuration = HeaderView.Configuration(
                    title: NSLocalizedString("Groups joined", comment: ""),
                    showGroupCreationButton: false)
                headerView.configure(with: configuration)
            }
        case 2:
            switch indexPath.section {
            case 0:
                let configuration = HeaderView.Configuration(
                    title: NSLocalizedString("GROUPS_THAT_YOU_ADMINISTER", comment: ""),
                    showGroupCreationButton: !searchInProgress)
                headerView.configure(with: configuration)
            case 1:
                let configuration = HeaderView.Configuration(
                    title: NSLocalizedString("Groups joined", comment: ""),
                    showGroupCreationButton: false)
                headerView.configure(with: configuration)
            default:
                assertionFailure()
            }
        default:
            assertionFailure()
        }
    }
    
    
    /// This method is used when deeplinks need to navigate through the hierarchy
    func selectRowOfDisplayedContactGroup(_ displayedContactGroup: DisplayedContactGroup) {
        guard let indexPath = frc.indexPath(forObject: displayedContactGroup) else { return }
        collectionView.selectItem(at: indexPath, animated: true, scrollPosition: .centeredVertically)
    }

    
    // MARK: NSFetchedResultsControllerDelegate
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {

        let collectionView = self.collectionView!
        guard let dataSource = collectionView.dataSource as? UICollectionViewDiffableDataSource<Int, NSManagedObjectID> else { assertionFailure(); return }
        
        let newSnapshot = snapshot as NSDiffableDataSourceSnapshot<Int, NSManagedObjectID>
        
        showOrHideViewForCreatingFirstGroup()
        
        dataSource.apply(newSnapshot, animatingDifferences: true)

    }
    
    
    private func showOrHideViewForCreatingFirstGroup() {
        if frc.fetchedObjects?.first(where: { $0.ownPermissionAdmin }) != nil || searchInProgress {
            // We should hide the view allowing to create the first administrated group since we will show a list of administrated groups (and thus a header) in the first section of the collection view. We also hide the view if a search is in progress
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) { [weak self] in
                self?.viewForCreatingFirstGroup.isHidden = true
            } completion: { [weak self] _ in
                guard let _self = self else { return }
                NSLayoutConstraint.deactivate(_self.constraintsWhenViewForCreatingFirstGroupIsShown)
                NSLayoutConstraint.activate(_self.constraintsWhenViewForCreatingFirstGroupIsHidden)
                _self.viewForCreatingFirstGroup.removeFromSuperview()
            }
        } else {
            // Since we do not have an administrated group yet, we want to show the view allowing to create the first administrated group
            if viewForCreatingFirstGroup.superview == nil {
                self.view.addSubview(viewForCreatingFirstGroup)
            }
            NSLayoutConstraint.deactivate(constraintsWhenViewForCreatingFirstGroupIsHidden)
            NSLayoutConstraint.activate(constraintsWhenViewForCreatingFirstGroupIsShown)
            viewForCreatingFirstGroup.isHidden = false
        }
    }
    
    
    // MARK: UICollectionViewDelegate
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let displayedContactGroup = frc.object(at: indexPath)
        switch displayedContactGroup.group {
        case .groupV1(let group):
            delegate?.userDidSelect(group, within: navigationController)
        case .groupV2(let group):
            delegate?.userDidSelect(group, within: navigationController)
            return
        case .none:
            return
        }
    }
    
    
    // MARK: HeaderViewDelegate
    
    func userWantsToAddContactGroup() {
        delegate?.userWantsToAddContactGroup()
    }
    
    
    // MARK: UISearchResultsUpdating
    
    func updateSearchResults(for searchController: UISearchController) {
        if let searchedText = searchController.searchBar.text, !searchedText.isEmpty {
            self.searchPredicate = DisplayedContactGroup.Predicate.searchPredicate(searchedText)
        } else {
            self.searchPredicate = nil
        }
    }
    
}



// MARK: - ObvSubtitleCollectionViewCell

fileprivate final class ObvSubtitleCollectionViewCell: UICollectionViewCell {
        
    struct Configuration: Equatable {
        let title: String?
        let subtitle: String?
        let circledInitialsConfiguration: CircledInitialsConfiguration
        let badge: BadgeType
    }
    
    enum BadgeType: Equatable {
        case none
        case symbol(systemIcon: SystemIcon, color: UIColor)
        case spinner
        static func == (lhs: BadgeType, rhs: BadgeType) -> Bool {
            switch lhs {
            case .none:
                switch rhs {
                case .none:
                    return true
                default:
                    return false
                }
            case .symbol(let systemIcon1, let color1):
                switch rhs {
                case .symbol(let systemIcon2, let color2):
                    return systemIcon1 == systemIcon2 && color1 == color2
                default:
                    return false
                }
            case .spinner:
                switch rhs {
                case .spinner:
                    return true
                default:
                    return false
                }
            }
        }
    }

    private let backgroundUIView = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let circledInitials = NewCircledInitialsView()
    private let labelsContainer = UIView()
    private let accessoryView = UIImageView()
    private let accessoryViewBackground = UIImageView()
    private let badgeView = UIImageView()
    private let spinnerView = UIActivityIndicatorView(style: .medium)
    private let badgeContainerView = UIView()
    private let bottomSeparatorView = UIView()

    private var mandatoryConstrainsWhenShowingSublabel = [NSLayoutConstraint]()
    private var mandatoryConstrainsWhenHidingSublabel = [NSLayoutConstraint]()

    private var badgeContainerViewWidthAnchorConstraint: NSLayoutConstraint! // Part of the mandatory constraints (either 0 or badgeSize + 2*badgePadding)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isSelected: Bool {
        didSet {
            if isSelected {
                accessoryViewBackground.isHidden = false
                accessoryView.tintColor = .white
            } else {
                accessoryViewBackground.isHidden = true
                accessoryView.tintColor = AppTheme.shared.colorScheme.adaptiveOlvidBlue
            }
            debugPrint(self.isSelected)
        }
    }
    
    private let circleSize: CGFloat = 56.0
    fileprivate static let leadingPadding: CGFloat = 16.0
    fileprivate static let trailingPadding: CGFloat = 16.0
    private static let horizontalSpacingBetweenCircleAndLabels: CGFloat = 20.0
    fileprivate static let verticalTopBottomPadding: CGFloat = 5.0
    private let textToSecondaryTextVerticalPadding: CGFloat = 4.0

    private var titleFont: UIFont {
        let textStyle = UIFont.TextStyle.callout
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle).withDesign(.rounded)?.withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        return UIFont(descriptor: fontDescriptor, size: 0)
    }

    private var subtitleFont: UIFont {
        let textStyle = UIFont.TextStyle.footnote
        let fontDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle).withDesign(.rounded) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: textStyle)
        return UIFont(descriptor: fontDescriptor, size: 0)
    }
    
    private let badgeSize: CGFloat = 15
    private let badgePadding: CGFloat = 8

    private func setupInternalViews() {
        
        backgroundColor = .clear
        
        contentView.addSubview(backgroundUIView)
        backgroundUIView.translatesAutoresizingMaskIntoConstraints = false
        backgroundUIView.backgroundColor = appTheme.colorScheme.secondarySystemBackground

        backgroundUIView.addSubview(circledInitials)
        circledInitials.translatesAutoresizingMaskIntoConstraints = false
        
        backgroundUIView.addSubview(labelsContainer)
        labelsContainer.translatesAutoresizingMaskIntoConstraints = false
        
        backgroundUIView.addSubview(accessoryViewBackground)
        accessoryViewBackground.translatesAutoresizingMaskIntoConstraints = false
        let accessoryViewBackgroundSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 21.0, weight: .regular)
        accessoryViewBackground.image = UIImage(systemIcon: .circleFill, withConfiguration: accessoryViewBackgroundSymbolConfiguration)
        accessoryViewBackground.contentMode = .scaleAspectFit
        accessoryViewBackground.tintColor = AppTheme.shared.colorScheme.adaptiveOlvidBlue
        accessoryViewBackground.isHidden = true

        backgroundUIView.addSubview(accessoryView)
        accessoryView.translatesAutoresizingMaskIntoConstraints = false
        let accessoryViewSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13.0, weight: .regular) // See also the constraint on the view width
        accessoryView.image = UIImage(systemIcon: .chevronRight, withConfiguration: accessoryViewSymbolConfiguration)
        accessoryView.contentMode = .scaleAspectFit
        accessoryView.tintColor = AppTheme.shared.colorScheme.adaptiveOlvidBlue

        backgroundUIView.addSubview(badgeContainerView)
        badgeContainerView.translatesAutoresizingMaskIntoConstraints = false
        badgeContainerView.backgroundColor = .none

        badgeContainerView.addSubview(badgeView)
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        // The badge image is set during configuration
        badgeView.contentMode = .scaleAspectFit
        
        badgeContainerView.addSubview(spinnerView)
        spinnerView.translatesAutoresizingMaskIntoConstraints = false

        labelsContainer.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = appTheme.colorScheme.label
        titleLabel.font = titleFont
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1

        labelsContainer.addSubview(subtitleLabel)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.textColor = appTheme.colorScheme.secondaryLabel
        subtitleLabel.font = subtitleFont
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 1

        backgroundUIView.addSubview(bottomSeparatorView)
        bottomSeparatorView.translatesAutoresizingMaskIntoConstraints = false
        bottomSeparatorView.backgroundColor = AppTheme.appleTableSeparatorColor
        
        // Mandatory constraint that we need to access later
        
        badgeContainerViewWidthAnchorConstraint = badgeContainerView.widthAnchor.constraint(equalToConstant: 0)

        let mandatoryConstraints: [NSLayoutConstraint] = [
            
            backgroundUIView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundUIView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            backgroundUIView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            backgroundUIView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            circledInitials.leadingAnchor.constraint(equalTo: backgroundUIView.leadingAnchor, constant: Self.leadingPadding),
            circledInitials.trailingAnchor.constraint(equalTo: labelsContainer.leadingAnchor, constant: -Self.horizontalSpacingBetweenCircleAndLabels),
            circledInitials.centerYAnchor.constraint(equalTo: backgroundUIView.centerYAnchor),
            circledInitials.widthAnchor.constraint(equalToConstant: circleSize),

            labelsContainer.trailingAnchor.constraint(equalTo: badgeContainerView.leadingAnchor),
            labelsContainer.centerYAnchor.constraint(equalTo: backgroundUIView.centerYAnchor),
            
            badgeContainerViewWidthAnchorConstraint,
            badgeContainerView.heightAnchor.constraint(greaterThanOrEqualTo: badgeView.heightAnchor),
            badgeContainerView.topAnchor.constraint(equalTo: backgroundUIView.topAnchor),
            badgeContainerView.trailingAnchor.constraint(equalTo: accessoryView.leadingAnchor),
            badgeContainerView.bottomAnchor.constraint(equalTo: backgroundUIView.bottomAnchor),
            
            badgeView.centerXAnchor.constraint(equalTo: badgeContainerView.centerXAnchor),
            badgeView.centerYAnchor.constraint(equalTo: badgeContainerView.centerYAnchor),

            spinnerView.centerXAnchor.constraint(equalTo: badgeContainerView.centerXAnchor),
            spinnerView.centerYAnchor.constraint(equalTo: badgeContainerView.centerYAnchor),

            accessoryView.trailingAnchor.constraint(equalTo: backgroundUIView.trailingAnchor, constant: -Self.trailingPadding),
            accessoryView.centerYAnchor.constraint(equalTo: backgroundUIView.centerYAnchor),
            accessoryView.widthAnchor.constraint(equalToConstant: 15),
            
            bottomSeparatorView.leadingAnchor.constraint(equalTo: labelsContainer.leadingAnchor),
            bottomSeparatorView.trailingAnchor.constraint(equalTo: backgroundUIView.trailingAnchor),
            bottomSeparatorView.bottomAnchor.constraint(equalTo: backgroundUIView.bottomAnchor),
            bottomSeparatorView.heightAnchor.constraint(equalToConstant: AppTheme.appleTableSeparatorHeight),

            backgroundUIView.heightAnchor.constraint(greaterThanOrEqualTo: circledInitials.heightAnchor, multiplier: 1.0, constant: 2*Self.verticalTopBottomPadding),
            backgroundUIView.heightAnchor.constraint(greaterThanOrEqualTo: labelsContainer.heightAnchor, multiplier: 1.0, constant: 2*Self.verticalTopBottomPadding),

            accessoryViewBackground.centerXAnchor.constraint(equalTo: accessoryView.centerXAnchor),
            accessoryViewBackground.centerYAnchor.constraint(equalTo: accessoryView.centerYAnchor),

        ]
        
        mandatoryConstrainsWhenShowingSublabel = [
            titleLabel.topAnchor.constraint(equalTo: labelsContainer.topAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: labelsContainer.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor, constant: -textToSecondaryTextVerticalPadding),
            titleLabel.leadingAnchor.constraint(equalTo: labelsContainer.leadingAnchor),

            subtitleLabel.trailingAnchor.constraint(equalTo: labelsContainer.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: labelsContainer.bottomAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: labelsContainer.leadingAnchor),
        ]

        mandatoryConstrainsWhenHidingSublabel = [
            titleLabel.topAnchor.constraint(equalTo: labelsContainer.topAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: labelsContainer.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: labelsContainer.bottomAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: labelsContainer.leadingAnchor),
        ]

        let nonMandatoryConstraints: [NSLayoutConstraint] = [
            contentView.heightAnchor.constraint(equalToConstant: 0),
        ]
        nonMandatoryConstraints.forEach({ $0.priority = .defaultLow })
               
        NSLayoutConstraint.activate(mandatoryConstraints)
        NSLayoutConstraint.activate(mandatoryConstrainsWhenShowingSublabel)
        NSLayoutConstraint.activate(nonMandatoryConstraints)
        
    }

    
    private var appliedConfiguration: Configuration?

    
    func configure(with configuration: Configuration) {
        guard appliedConfiguration != configuration else { return }
        defer { appliedConfiguration = configuration }
        titleLabel.text = configuration.title
        if let subtitle = configuration.subtitle, !subtitle.isEmpty {
            titleLabel.numberOfLines = 1
            NSLayoutConstraint.deactivate(mandatoryConstrainsWhenHidingSublabel)
            NSLayoutConstraint.activate(mandatoryConstrainsWhenShowingSublabel)
            subtitleLabel.isHidden = false
            subtitleLabel.text = subtitle
        } else {
            titleLabel.numberOfLines = 2
            subtitleLabel.text = nil
            subtitleLabel.isHidden = true
            NSLayoutConstraint.deactivate(mandatoryConstrainsWhenShowingSublabel)
            NSLayoutConstraint.activate(mandatoryConstrainsWhenHidingSublabel)
        }
        circledInitials.configureWith(configuration.circledInitialsConfiguration)
        switch configuration.badge {
        case .none:
            badgeContainerViewWidthAnchorConstraint.constant = 0
            badgeView.tintColor = nil
            badgeView.isHidden = true
            spinnerView.isHidden = true
        case .symbol(systemIcon: let systemIcon, color: let color):
            badgeContainerViewWidthAnchorConstraint.constant = badgeSize + 2*badgePadding
            badgeView.tintColor = color
            let badgeViewSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: badgeSize, weight: .regular) // See also the constraint on the view width
            badgeView.image = UIImage(systemIcon: systemIcon, withConfiguration: badgeViewSymbolConfiguration)
            badgeView.isHidden = false
            spinnerView.isHidden = true
        case .spinner:
            badgeContainerViewWidthAnchorConstraint.constant = badgeSize + 2*badgePadding
            badgeView.isHidden = true
            spinnerView.isHidden = false
            spinnerView.startAnimating()
        }
    }
    
}


// MARK: - HeaderView

fileprivate final class HeaderView: UICollectionReusableView {
    
    struct Configuration: Equatable {
        let title: String?
        let showGroupCreationButton: Bool
    }
    
    static let reuseIdentifier = "HeaderView"
    
    private let backgroundView = UIView()
    private let titleLabel = UILabel()
    private let separatorView = UIView()
    private var appliedConfiguration: Configuration?
    private let button = ObvImageButton()
    private var groupCreationButtonIsShown = false
    
    private var constraintsForShowingButton = [NSLayoutConstraint]()
    private var constraintsForHidingButton = [NSLayoutConstraint]()

    weak var delegate: HeaderViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    fileprivate static let verticalTopBottomPadding: CGFloat = 16
    
    private func setupInternalViews() {
        
        // We do not set the background color to .clear so as to hide other cells when they go "under" this header during scroll
        backgroundColor = appTheme.colorScheme.systemBackground
        
        self.addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = appTheme.colorScheme.secondarySystemBackground
        backgroundView.layer.cornerRadius = 16.0
        backgroundView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]

        backgroundView.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = appTheme.colorScheme.label
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        
        backgroundView.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(NSLocalizedString("CREATE_GROUP_WITH_OWN_PERMISSION_ADMIN", comment: ""), for: .normal)
        button.setImage(.person3Fill, for: .normal)
        
        backgroundView.addSubview(separatorView)
        separatorView.translatesAutoresizingMaskIntoConstraints = false
        separatorView.backgroundColor = AppTheme.appleTableSeparatorColor

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: self.topAnchor, constant: 20),
            backgroundView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -16),
            backgroundView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16),
        ])

        constraintsForShowingButton = [
            titleLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: Self.verticalTopBottomPadding),
            titleLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -Self.verticalTopBottomPadding),
            titleLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: ObvSubtitleCollectionViewCell.leadingPadding),
            
            button.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -ObvSubtitleCollectionViewCell.leadingPadding),
            button.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -Self.verticalTopBottomPadding),
            button.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: ObvSubtitleCollectionViewCell.leadingPadding),
        ]

        if #unavailable(iOS 15) {
            // Under iOS 14 and 13, this hack is required to prevent certain constraints to break
            constraintsForShowingButton.forEach({ $0.priority -= 1 })
        }
        
        constraintsForHidingButton = [
            titleLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: Self.verticalTopBottomPadding),
            titleLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -Self.verticalTopBottomPadding),
            titleLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: ObvSubtitleCollectionViewCell.leadingPadding),
        ]
        
        if #unavailable(iOS 15) {
            // Under iOS 14 and 13, this hack is required to prevent certain constraints to break
            constraintsForHidingButton.forEach({ $0.priority -= 1 })
        }
        
        if groupCreationButtonIsShown {
            NSLayoutConstraint.activate(constraintsForShowingButton)
            button.isHidden = false
        } else {
            NSLayoutConstraint.activate(constraintsForHidingButton)
            button.isHidden = true
        }
        
        NSLayoutConstraint.activate([
            separatorView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            separatorView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            separatorView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: AppTheme.appleTableSeparatorHeight),
        ])
        
        button.addTarget(self, action: #selector(createGroupButtonTapped), for: .touchUpInside)

    }
    
    
    @objc func createGroupButtonTapped() {
        delegate?.userWantsToAddContactGroup()
    }
    
    
    func configure(with configuration: Configuration) {
        guard appliedConfiguration != configuration else { return }
        self.appliedConfiguration = configuration
        self.titleLabel.text = configuration.title
        if groupCreationButtonIsShown != configuration.showGroupCreationButton {
            groupCreationButtonIsShown = configuration.showGroupCreationButton
            if groupCreationButtonIsShown {
                NSLayoutConstraint.deactivate(constraintsForHidingButton)
                NSLayoutConstraint.activate(constraintsForShowingButton)
                button.isHidden = false
            } else {
                NSLayoutConstraint.deactivate(constraintsForShowingButton)
                NSLayoutConstraint.activate(constraintsForHidingButton)
                button.isHidden = true
            }
        }
    }

}


protocol HeaderViewDelegate: AnyObject {
    func userWantsToAddContactGroup()
}


// MARK: - FooterView

fileprivate final class FooterView: UICollectionReusableView {
    
    static let reuseIdentifier = "FooterView"
    
    /// Since the corner radius of this background view is 16.0, we need to set its height to 32.0 to obtain a nice visual result.
    /// Since 32.0 is to large a height for this view, we do not pin the top anchor of this background view to the top of this view.
    private let backgroundView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupInternalViews() {
        
        backgroundColor = AppTheme.shared.colorScheme.systemBackground
        clipsToBounds = true

        self.addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = appTheme.colorScheme.secondarySystemBackground
        backgroundView.layer.cornerRadius = 16.0
        backgroundView.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner]

        NSLayoutConstraint.activate([
            self.heightAnchor.constraint(equalToConstant: 16.0),
            backgroundView.heightAnchor.constraint(equalToConstant: 32.0),
            backgroundView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -16),
            backgroundView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16),
        ])

    }
    
}


fileprivate final class ViewForCreatingFirstGroup: UIView {
    
    private let backgroundView = UIView()
    private let titleLabel = UILabel()
    private let button = ObvImageButton()

    weak var delegate: HeaderViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupInternalViews() {
        
        backgroundColor = .none
        
        self.addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.backgroundColor = appTheme.colorScheme.secondarySystemBackground
        backgroundView.layer.cornerRadius = 16.0

        backgroundView.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = appTheme.colorScheme.label
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.text = NSLocalizedString("GROUPS_THAT_YOU_ADMINISTER", comment: "")
        
        backgroundView.addSubview(button)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(NSLocalizedString("CREATE_FIRST_GROUP_WITH_OWN_PERMISSION_ADMIN", comment: ""), for: .normal)
        button.setImage(.person3Fill, for: .normal)
        
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: self.topAnchor, constant: 20),
            backgroundView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -16),
            backgroundView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16),

            titleLabel.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: HeaderView.verticalTopBottomPadding),
            titleLabel.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -HeaderView.verticalTopBottomPadding),
            titleLabel.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: ObvSubtitleCollectionViewCell.leadingPadding),
            
            button.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -ObvSubtitleCollectionViewCell.leadingPadding),
            button.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -HeaderView.verticalTopBottomPadding),
            button.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: ObvSubtitleCollectionViewCell.leadingPadding),
        ])

        button.addTarget(self, action: #selector(createGroupButtonTapped), for: .touchUpInside)

    }

    
    @objc func createGroupButtonTapped() {
        delegate?.userWantsToAddContactGroup()
    }

}
