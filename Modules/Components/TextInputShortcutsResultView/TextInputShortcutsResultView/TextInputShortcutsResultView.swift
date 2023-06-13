/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

import UIKit
import Platform_Base
import UI_CircledInitialsView_CircledInitialsConfiguration
import class ObvUI.NewCircledInitialsView

/// This view is supposed to be displayed inline within a discussion. At the time of writing (2023-04-03), it is only used for displaying a collection of mentionnable users.
///
/// Please use ``TextInputShortcutsResultView/placementLayoutGuide`` for specifying its geometry
@MainActor
@available(iOSApplicationExtension 14.0, *)
public final class TextInputShortcutsResultView: UIView {
    private enum Constants {
        /// The appearance for our list layout, if you update this, please make sure to update the configurations for the cell
        static let listAppearance: UICollectionLayoutListConfiguration.Appearance = .plain

        static let placementLayoutGuideIdentifier = "io.olvid.messenger.text-input-shortcuts-result-view.placement-layout-guide"

        /// This is a special height, to be used when our content doesn't have a height so that it can calculate its content size, this also happens to be the the inset for our alignment rect when we have no content
        static let placeholderHeight: CGFloat = 42

        static let maximumNumberOfPreviewItems = 3

        /// To handle for later, refactor `NewCircledInitialsView` to not use auto-layout
        static let cellAvatarSize: CGSize = .init(width: 32,
                                                  height: 32)

        static let transitionDuration: TimeInterval = 0.2

        static let deselectionDuration: TimeInterval = 0.15
    }

    /// This layout guide has a few tricks up its sleave to automagically show and hide itself
    public let placementLayoutGuide: UILayoutGuide

    /// First magic trick
    private var placementLayoutGuideTopConstraintEqualToOurTopConstraint: NSLayoutConstraint!

    /// Second magic trick
    private var placementLayoutGuideTopConstraintEqualToOurBottomConstraint: NSLayoutConstraint!

    private weak var backgroundBlurEffectView: UIVisualEffectView!

    private let shortcutsTableCollectionViewLayout: UICollectionViewCompositionalLayout

    private weak var shortcutsTableCollectionView: UICollectionView!

    private var shortcutsDiffableDatasource: UICollectionViewDiffableDataSource<Section, Item>!

    public weak var delegate: TextInputShortcutsResultViewDelegate?

    /// Helper property to check if our table view has no content
    ///
    /// Checks done:
    ///   - ``shortcutsDiffableDatasource`` has no items
    ///   - ``shortcutsTableCollectionView``'s content size has 0 for one of its dimensions
    @inline(__always)
    private var shortcutsTableCollectionViewHasNoContent: Bool {
        if shortcutsDiffableDatasource.snapshot().numberOfItems == 0 {
            return true
        }

        let contentSize = shortcutsTableCollectionView.contentSize

        return contentSize.width <= 0 || contentSize.height <= 0
    }

    public override var intrinsicContentSize: CGSize {
        guard shortcutsTableCollectionViewHasNoContent == false else {
            return .init(width: UIView.noIntrinsicMetric,
                         height: Constants.placeholderHeight)
        }

        return .init(width: bounds.width, // since we're a list, we're assuming that the cells are full width
                     height: shortcutsTableCollectionViewContentHeight())
    }

    /// Desiginated initializer for this class, please pass it an instance of `UIBlurEffect`, the same one that is used for its sibiling
    /// - Parameter blurEffect: An instance of `UIBlurEffect`
    public init(blurEffect: UIBlurEffect) {
        let placementLayoutGuide = UILayoutGuide()

        placementLayoutGuide.identifier = Constants.placementLayoutGuideIdentifier

        self.placementLayoutGuide = placementLayoutGuide

        shortcutsTableCollectionViewLayout = {
            let configuration = UICollectionLayoutListConfiguration(appearance: Constants.listAppearance)..{
                $0.backgroundColor = .clear

                $0.showsSeparators = true

                if #available(iOS 14.5, *) {
                    $0.separatorConfiguration = .init(listAppearance: Constants.listAppearance)..{
                        if #available(iOS 15, *) {
                            $0.visualEffect = UIVibrancyEffect(blurEffect: blurEffect, style: .separator)
                        }
                    }
                }
            }

            return UICollectionViewCompositionalLayout.list(using: configuration)
        }()

        super.init(frame: .zero)

        addLayoutGuide(placementLayoutGuide)

        _configureViews(blurEffect: blurEffect)
    }

    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func _configureViews(blurEffect: UIBlurEffect) {
        translatesAutoresizingMaskIntoConstraints = false

        setContentHuggingPriority(.required, for: .vertical)

        backgroundColor = .clear

        isOpaque = false

        clipsToBounds = true

        insetsLayoutMarginsFromSafeArea = false

        let backgroundBlurEffectView = UIVisualEffectView(effect: blurEffect)

        backgroundBlurEffectView.contentView.isUserInteractionEnabled = true

        backgroundBlurEffectView.translatesAutoresizingMaskIntoConstraints = false

        let collectionView = UICollectionView(frame: .zero,
                                              collectionViewLayout: shortcutsTableCollectionViewLayout)

        collectionView.insetsLayoutMarginsFromSafeArea = false

        collectionView.delegate = self

        collectionView.isOpaque = false

        collectionView.backgroundColor = .clear

        collectionView.translatesAutoresizingMaskIntoConstraints = false

        let customDefaultBackgroundConfiguration = UIBackgroundConfiguration.listPlainCell()..{
            $0.visualEffect = UIVibrancyEffect(blurEffect: blurEffect, style: .secondaryFill)
        }

        let defaultCellRegistration = UICollectionView.CellRegistration<_SuggestionCell, TextShortcutItem> { cell, indexPath, item in
            cell.customDefaultBackgroundConfiguration = customDefaultBackgroundConfiguration

            var configuration = cell.defaultContentConfiguration()

            configuration.text = item.title

            configuration.secondaryText = item.subtitle

            if let accessory = item.accessory {
                let cellAccessory: UICellAccessory

                switch accessory {
                case .circledInitialsView(configuration: let configuration):
                    if let firstAccessory = cell.accessories.first,
                       case .customView(let customView) = firstAccessory.accessoryType,
                       let circledInitialsView = customView as? NewCircledInitialsView {
                        circledInitialsView.configure(with: configuration)

                        cellAccessory = firstAccessory
                    } else {
                        let circledInitialsView = NewCircledInitialsView()

                        circledInitialsView.bounds.size = Constants.cellAvatarSize

                        circledInitialsView.configure(with: configuration)

                        circledInitialsView.layoutIfNeeded()

                        cellAccessory = .customView(configuration: .init(customView: circledInitialsView,
                                                                         placement: .leading(displayed: .always),
                                                                         isHidden: false,
                                                                         reservedLayoutWidth: .custom(Constants.cellAvatarSize.width),
                                                                         tintColor: nil,
                                                                         maintainsFixedSize: false))
                    }
                }

                cell.accessories = [cellAccessory]
            }

            cell.isOpaque = false

            cell.contentConfiguration = configuration

            cell.backgroundConfiguration = .clear()
        }

        shortcutsDiffableDatasource = .init(collectionView: collectionView) { collectionView, indexPath, itemIdentifier in
            switch itemIdentifier {
            case .suggestion(shortcut: let shortcut):
                return collectionView.dequeueConfiguredReusableCell(using: defaultCellRegistration, for: indexPath, item: shortcut)
            }
        }

        addSubview(backgroundBlurEffectView)

        backgroundBlurEffectView.contentView.addSubview(collectionView)

        self.backgroundBlurEffectView = backgroundBlurEffectView

        self.shortcutsTableCollectionView = collectionView

        _setupConstraints()
    }

    private func _setupConstraints() {
        placementLayoutGuideTopConstraintEqualToOurTopConstraint = placementLayoutGuide.topAnchor.constraint(equalTo: topAnchor)

        placementLayoutGuideTopConstraintEqualToOurBottomConstraint = placementLayoutGuide.topAnchor.constraint(equalTo: bottomAnchor)

        if shortcutsTableCollectionViewHasNoContent {
            placementLayoutGuideTopConstraintEqualToOurTopConstraint.isActive = true
        } else {
            placementLayoutGuideTopConstraintEqualToOurBottomConstraint.isActive = true
        }

        NSLayoutConstraint.activate([
            placementLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            placementLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor),

            placementLayoutGuide.heightAnchor.constraint(equalTo: heightAnchor)
        ])

        let viewsDictionary = ["backgroundBlurEffectView": backgroundBlurEffectView!,
                               "shortcutsTableCollectionView": shortcutsTableCollectionView!]

        NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "H:|[backgroundBlurEffectView]|",
                                                                   options: [],
                                                                   metrics: nil,
                                                                   views: viewsDictionary))

        NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "V:|[backgroundBlurEffectView]|",
                                                                   options: [],
                                                                   metrics: nil,
                                                                   views: viewsDictionary))

        NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "H:|[shortcutsTableCollectionView]|",
                                                                   options: [],
                                                                   metrics: nil,
                                                                   views: viewsDictionary))

        NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "V:|[shortcutsTableCollectionView]|",
                                                                   options: [],
                                                                   metrics: nil,
                                                                   views: viewsDictionary))
    }

    /// Method to configure the current shortcuts that are available, and if their presentation should be animated
    /// - Parameters:
    ///   - items: The new shortcut items to display
    ///   - animated: Animate the presentation
    public func configure(with items: [TextShortcutItem], animated: Bool) {
        let snapshot = NSDiffableDataSourceSnapshot<Section, Item>()..{
            $0.appendSections([.main])

            $0.appendItems(items.map(Item.suggestion(shortcut:)),
                           toSection: .main)
        }

        guard snapshot.itemIdentifiers != shortcutsDiffableDatasource.snapshot().itemIdentifiers else {
            return
        }

        guard animated else {
            if #available(iOS 15.5, *) {
                shortcutsDiffableDatasource.applySnapshotUsingReloadData(snapshot)
            } else {
                shortcutsDiffableDatasource.apply(snapshot, animatingDifferences: false)

                shortcutsTableCollectionView.reloadData()
            }

            invalidateIntrinsicContentSize()

            superview?.layoutIfNeeded()

            _invalidateLayoutPostContentSizeChangeBeforeAnimation()

            superview?.layoutIfNeeded()

            return
        }

        let previousNumberOfItems = shortcutsDiffableDatasource.snapshot().numberOfItems

        let additionalAnimationBlock: (() -> Void)?

        let animationCompletionBlock: ((UIViewAnimatingPosition) -> Void)?

        if items.isEmpty == false && previousNumberOfItems == 0 {
            shortcutsDiffableDatasource.apply(snapshot, animatingDifferences: false)

            invalidateIntrinsicContentSize()

            superview?.layoutIfNeeded()

            additionalAnimationBlock = nil

            animationCompletionBlock = nil
        } else if items.isEmpty == false && previousNumberOfItems > 0 {
            additionalAnimationBlock = {
                if previousNumberOfItems < items.count,
                   #available(iOS 15.5, *) {
                    self.shortcutsDiffableDatasource.applySnapshotUsingReloadData(snapshot)
                } else {
                    self.shortcutsDiffableDatasource.apply(snapshot, animatingDifferences: true)
                }

                self.invalidateIntrinsicContentSize()

                self.superview?.layoutIfNeeded()
            }

            animationCompletionBlock = nil
        } else {
            let snapshotView = shortcutsTableCollectionView.snapshotView(afterScreenUpdates: true)

            shortcutsDiffableDatasource.apply(snapshot, animatingDifferences: false)

            if let snapshotView {
                backgroundBlurEffectView.contentView.addSubview(snapshotView)
            }

            additionalAnimationBlock = nil

            animationCompletionBlock = { position in
                snapshotView?.removeFromSuperview()

                guard position == .end else {
                    return
                }

                self.invalidateIntrinsicContentSize()

                self.superview?.layoutIfNeeded()
            }
        }

        let propertyAnimator = UIViewPropertyAnimator.runningPropertyAnimator(withDuration: Constants.transitionDuration,
                                                                              delay: 0,
                                                                              options: []) {
            additionalAnimationBlock?()

            self._invalidateLayoutPostContentSizeChangeBeforeAnimation()
            
            self.superview?.layoutIfNeeded()
        }

        if let animationCompletionBlock {
            propertyAnimator.addCompletion(animationCompletionBlock)
        }
    }

    private func _invalidateLayoutPostContentSizeChangeBeforeAnimation() {
        if shortcutsTableCollectionViewHasNoContent {
            placementLayoutGuideTopConstraintEqualToOurBottomConstraint.isActive = false

            placementLayoutGuideTopConstraintEqualToOurTopConstraint.isActive = true
        } else {
            placementLayoutGuideTopConstraintEqualToOurTopConstraint.isActive = false

            placementLayoutGuideTopConstraintEqualToOurBottomConstraint.isActive = true
        }
    }

    /// Helper method that returns a sanitized version of ``shortcutsTableCollectionView``'s content height, clamping it the height of its first three items
    /// - Returns: A clamped value of the content height, or 0 if it has no items
    private func shortcutsTableCollectionViewContentHeight() -> CGFloat {
        let datasourceSnapshot = shortcutsDiffableDatasource.snapshot()

        guard datasourceSnapshot.numberOfSections == 1 else {
            assertionFailure("expected to have one section")
            return 0
        }

        let numberOfItems = datasourceSnapshot.numberOfItems(inSection: .main)

        guard numberOfItems > 0 else {
            return 0
        }

        var lastItemAttributes: UICollectionViewLayoutAttributes?

        for i in (0..<min(numberOfItems, Constants.maximumNumberOfPreviewItems)).reversed() {
            let indexPath = IndexPath(item: i, section: 0)

            guard let attributes = shortcutsTableCollectionViewLayout.layoutAttributesForItem(at: indexPath) else {
                continue
            }

            lastItemAttributes = attributes

            break
        }

        guard let lastItemAttributes else {
            assertionFailure("failed to fetch item attribtues…")

            return 0
        }

        return lastItemAttributes.frame.maxY
    }
}

@available(iOSApplicationExtension 14.0, *)
extension TextInputShortcutsResultView: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let delegate else {
            assert(delegate != nil, "we're missing our delegate")

            return
        }

        collectionView.isUserInteractionEnabled = false

        let itemIdentifier = shortcutsDiffableDatasource.itemIdentifier(for: indexPath)!

        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: Constants.deselectionDuration,
                                                       delay: 0) {
            collectionView.deselectItem(at: indexPath, animated: true)
        } completion: { _ in
            collectionView.isUserInteractionEnabled = true

            switch itemIdentifier {
            case .suggestion(shortcut: let shortcut):
                delegate.textInputShortcutsResultView(self, didSelect: shortcut)
            }
        }
    }
}

@available(iOSApplicationExtension 14.0, *)
private extension TextInputShortcutsResultView {
    /// Denotes the available sections for our shortcuts
    ///
    /// - `main`: The main section
    enum Section {
        /// The main section
        case main
    }

    /// Denotes the available items for our shortcuts
    ///
    /// - `suggestion`: Denotes a generic suggestion
    enum Item: Hashable {
        /// Denotes a generic suggestion
        case suggestion(shortcut: TextShortcutItem)
    }
}
