/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import CoreData
import os.log
import ObvEngine

class SingleContactViewController: UIViewController, SomeSingleContactViewController {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    // Views

    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var mainStackView: UIStackView!

    @IBOutlet weak var topStackView: UIStackView!
    @IBOutlet weak var circlePlaceholder: UIView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var alternateTitleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    
    @IBOutlet weak var channelBeingEstablishedView: UIView!
    @IBOutlet weak var channelBeingEstablishedTitleLabel: UILabel!
    @IBOutlet weak var channelBeingEstablishedExplanationLabel: UILabel!
    @IBOutlet weak var activityIndicatorPlaceholder: UIView!
    
    @IBOutlet weak var olvidCardVersionChooserPlaceholder: UIView!
    private var olvidCardChooserView: ExplanationCardView!
    
    @IBOutlet weak var firstOlvidCardPlaceholder: UIView!
    private var firstOlvidCardView: OlvidCardView!

    @IBOutlet weak var secondOlvidCardPlaceholder: UIView!
    private var secondOlvidCardView: OlvidCardView!
    
    private var introduceContactButton: UIButton!
    private var qrCodeButton: UIButton!
    private var updateOlvidCardButton: UIButton!
    private var showQRCodeButton: UIButton!

    @IBOutlet weak var paddingView: UIView!
    
    @IBOutlet weak var groupsStackView: UIStackView!
    @IBOutlet weak var groupsLabel: UILabel!
    @IBOutlet weak var groupsLabelLeadingPaddingConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var channelEstablishingExplanationStackElement: ObvRoundedRectView!

    @IBOutlet weak var trustOriginsSpinnerView: UIView!
    @IBOutlet weak var trustOriginsSpinner: UIActivityIndicatorView!
    @IBOutlet weak var trustOriginsStackView: UIStackView!
    @IBOutlet weak var trustOriginsLabel: UILabel!
    @IBOutlet weak var trustOriginsLabelLeadingPaddingConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var advancedStackView: UIStackView!
    @IBOutlet weak var advancedLabel: UILabel!
    @IBOutlet weak var advancedLabelLeadingPaddingConstraint: NSLayoutConstraint!
    @IBOutlet weak var advancedButtonRestartChannelPlaceholder: UIView!
    @IBOutlet weak var advancedButtonRestartChannel: ObvButtonBorderless!
    @IBOutlet weak var advancedShowContactInfosButtonPlaceholder: UIView!
    @IBOutlet weak var advancedShowContactInfosButton: ObvButtonBorderless!
    
    @IBOutlet weak var startDiscussionButton: ObvFloatingButton!
    
    @IBOutlet weak var mainStackViewBottomConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var deleteView: UIView!
    @IBOutlet weak var deleteButton: UIButton!
    
    private static func makeError(message: String) -> Error { NSError(domain: "SingleContactViewController", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { SingleContactViewController.makeError(message: message) }

    // Delegate
    
    weak var delegate: SingleContactViewControllerDelegate?    
    
    // Model
    
    let persistedObvContactIdentity: PersistedObvContactIdentity
    private var obvContactIdentity: ObvContactIdentity!
    
    // Other variables
    
    private let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .medium
        df.timeStyle = .medium
        df.locale = Locale.current
        return df
    }()
    
    private var notificationTokens = [NSObjectProtocol]()

    let olvidCardsSideConstants: CGFloat = 16.0
    let customSpacingBetweenSections: CGFloat = 24.0
    let customSpacingAfterTopStackView: CGFloat = 32.0
    let sectionLabelsLeadingPaddingConstraint: CGFloat = 20.0
    
    // Subviews set in viewDidLoad
    
    var circledInitials: CircledInitials!
    
    
    // Initializer
    
    init(persistedObvContactIdentity: PersistedObvContactIdentity) throws {
        self.persistedObvContactIdentity = persistedObvContactIdentity
        super.init(nibName: nil, bundle: nil)
        guard let ownedIdentity = persistedObvContactIdentity.ownedIdentity else {
            throw SingleContactViewController.makeError(message: "Could not find owned identity. This is ok if it was just deleted.")
        }
        self.obvContactIdentity = try obvEngine.getContactIdentity(with: persistedObvContactIdentity.cryptoId, ofOwnedIdentityWith: ownedIdentity.cryptoId)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
}


// MARK: - UIViewController lifecycle and helpers

extension SingleContactViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.largeTitleDisplayMode = .never
        
        view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        scrollView.alwaysBounceVertical = true
        mainStackView.setCustomSpacing(customSpacingAfterTopStackView, after: topStackView)
        extendedLayoutIncludesOpaqueBars = true

        circlePlaceholder.backgroundColor = .clear
        titleLabel.textColor = AppTheme.shared.colorScheme.label
        alternateTitleLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        subtitleLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        paddingView.backgroundColor = .clear
        
        channelBeingEstablishedView.accessibilityIdentifier = "channelBeingEstablishedView"
        channelBeingEstablishedView.backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        channelBeingEstablishedTitleLabel.textColor = AppTheme.shared.colorScheme.label
        channelBeingEstablishedExplanationLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        activityIndicatorPlaceholder.backgroundColor = .clear
        let activityIndicator = DotsActivityIndicatorView()
        activityIndicatorPlaceholder.addSubview(activityIndicator)
        activityIndicatorPlaceholder.pinAllSidesToSides(of: activityIndicator)
        activityIndicator.startAnimating()
        circledInitials = (Bundle.main.loadNibNamed(CircledInitials.nibName, owner: nil, options: nil)!.first as! CircledInitials)
        circledInitials.withShadow = true
        circlePlaceholder.addSubview(circledInitials)
        circlePlaceholder.pinAllSidesToSides(of: circledInitials)

        olvidCardVersionChooserPlaceholder.backgroundColor = .clear
        olvidCardChooserView = (Bundle.main.loadNibNamed(ExplanationCardView.nibName, owner: nil, options: nil)!.first as! ExplanationCardView)
        olvidCardChooserView.backgroundColor = .clear
        olvidCardChooserView.titleLabel.text = Strings.OlvidCardChooser.title
        olvidCardChooserView.bodyLabel.text = Strings.OlvidCardChooser.body
        olvidCardChooserView.iconImageView.image = UIImage(named: "account_card_no_borders")
        olvidCardChooserView.iconImageView.tintColor = AppTheme.shared.colorScheme.secondaryLabel
        updateOlvidCardButton = ObvButton()
        updateOlvidCardButton.setTitle(CommonString.Word.Update, for: .normal)
        updateOlvidCardButton.addTarget(self, action: #selector(acceptPublishedCardButtonTapped), for: .touchUpInside)
        olvidCardChooserView.addButton(updateOlvidCardButton)
        olvidCardVersionChooserPlaceholder.addSubview(olvidCardChooserView)
        olvidCardVersionChooserPlaceholder.pinAllSidesToSides(of: olvidCardChooserView, sideConstants: olvidCardsSideConstants)
        
        firstOlvidCardPlaceholder.backgroundColor = .clear
        firstOlvidCardView = (Bundle.main.loadNibNamed(OlvidCardView.nibName, owner: nil, options: nil)!.first as! OlvidCardView)
        firstOlvidCardPlaceholder.addSubview(firstOlvidCardView)
        firstOlvidCardPlaceholder.pinAllSidesToSides(of: firstOlvidCardView, sideConstants: olvidCardsSideConstants)

        introduceContactButton = ObvButton()
        introduceContactButton.setTitle(CommonString.Word.Introduce, for: .normal)
        introduceContactButton.addTarget(self, action: #selector(introduceToButtonTapped), for: .touchUpInside)
        firstOlvidCardView.addButton(introduceContactButton)

        qrCodeButton = ObvButton()
        qrCodeButton.setTitle(CommonString.Title.qrCode, for: .normal)
        qrCodeButton.addTarget(self, action: #selector(presentLargeContactIdentityViewController), for: .touchUpInside)
        firstOlvidCardView.addButton(qrCodeButton)

        secondOlvidCardPlaceholder.backgroundColor = .clear
        secondOlvidCardView = (Bundle.main.loadNibNamed(OlvidCardView.nibName, owner: nil, options: nil)!.first as! OlvidCardView)
        secondOlvidCardPlaceholder.addSubview(secondOlvidCardView)
        secondOlvidCardPlaceholder.pinAllSidesToSides(of: secondOlvidCardView, sideConstants: olvidCardsSideConstants)

        groupsLabel.textColor = AppTheme.shared.colorScheme.label
        groupsLabelLeadingPaddingConstraint.constant = sectionLabelsLeadingPaddingConstraint
        mainStackView.setCustomSpacing(customSpacingBetweenSections, after: groupsStackView)

        trustOriginsLabel.textColor = AppTheme.shared.colorScheme.label
        trustOriginsLabelLeadingPaddingConstraint.constant = sectionLabelsLeadingPaddingConstraint
        
        advancedLabel.textColor = AppTheme.shared.colorScheme.label
        advancedLabel.text = CommonString.Word.Advanced
        advancedLabelLeadingPaddingConstraint.constant = sectionLabelsLeadingPaddingConstraint
        advancedButtonRestartChannel.setTitle(Strings.buttonRestartChannelTitle, for: .normal)
        advancedShowContactInfosButton.setTitle(Strings.advancedShowContactInfosButtonTitle, for: .normal)
        
        advancedButtonRestartChannelPlaceholder.backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        advancedShowContactInfosButtonPlaceholder.backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        
        deleteView.backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        deleteButton.setTitle(CommonString.Word.Delete, for: .normal)
        deleteButton.setTitleColor(.red, for: .normal)
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)
        
        var items = [UIBarButtonItem]()
        
        items += [UIBarButtonItem(barButtonSystemItem: UIBarButtonItem.SystemItem.compose,
                                  target: self,
                                  action: #selector(nicknameButtonTapped))]
        
        if #available(iOS 13, *) {} else {
            items += [UIBarButtonItem.space()]
        }
        
        items += [UIBarButtonItem(systemName: "phone.fill", style: .plain, target: self, action: #selector(callButtonTapped))]

        navigationItem.rightBarButtonItems = items

        chooseAppropriateStackElementDependingOnChannelAvailability(animate: false)
        
        configureViewsBasedOnPersistedObvContactIdentity()
        
        configureTheOlvidCards(animated: false)
        configureAndAddTheContactGroupsTVC()
        configureAndAddTheTrustOriginsTVC()
        
        observeContactWasDeletedNotifications()
        observeNewPersistedObvContactDeviceNotifications()
        observeDeletedPersistedObvContactDeviceNotifications()
        observeUpdatedContactIdentityNotifications()
        observeIdentityColorStyleDidChangeNotifications()

    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super .viewWillAppear(animated)
        
        chooseAppropriateStackElementDependingOnChannelAvailability(animate: false)
        
        observeContactUpdates()
    }
    
}

// MARK: - Configure views depending on the PersistedObvContact

extension SingleContactViewController {
    
    private func configureViewsBasedOnPersistedObvContactIdentity() {
        
        let displayName = persistedObvContactIdentity.customDisplayName ?? persistedObvContactIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
        title = displayName
        circledInitials.identityColors = persistedObvContactIdentity.cryptoId.colors
        circledInitials.showCircledText(from: displayName)
        circledInitials.showPhoto(fromUrl: persistedObvContactIdentity.customPhotoURL ?? persistedObvContactIdentity.photoURL)
        if let customDisplayName = persistedObvContactIdentity.customDisplayName {
            titleLabel.text = customDisplayName
            alternateTitleLabel.text = persistedObvContactIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
            alternateTitleLabel.isHidden = false
        } else {
            titleLabel.text = persistedObvContactIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
            alternateTitleLabel.text = nil
            alternateTitleLabel.isHidden = true
        }
        let subtitle = persistedObvContactIdentity.identityCoreDetails.getDisplayNameWithStyle(.positionAtCompany)
        subtitleLabel.isHidden = subtitle.isEmpty
        subtitleLabel.text = subtitle
    }
    
}

// MARK: - Configuring the OlvidCards

extension SingleContactViewController {
    
    func configureTheOlvidCards(animated: Bool) {
        guard self.olvidCardChooserView != nil else { return }
        guard self.secondOlvidCardView != nil else { return }
        guard self.firstOlvidCardView != nil else { return }
        
        let animator = animated ? UIViewPropertyAnimator(duration: 0.4, curve: .easeInOut) : nil
        
        configureTheSecondOlvidCardAndTheOlvidCardChooserView(animator: animator)
        configureTheFirstOlvidCard(animator: animator)
        
        if animated {
            animator!.startAnimation()
        }
        
    }
    
    
    /// If there is no published details, or if these details are identical to the trusted details, the first Olvid card is the only one we show. In that case, we use a green label with the text "Olvid Card".
    /// If the published details are different from the trusted details, this first card shows the published details, with a red label with the text "Olvid Card - Published".
    /// In all cases, this card is the only one showing a QR code, as well as the buttons allowing to share, introduce. The "Update" button is on the second card.
    /// If there are published details, this card shows them. Otherwise, it shows the trusted details.
    private func configureTheFirstOlvidCard(animator: UIViewPropertyAnimator?) {
        
        let detailsToShow = self.obvContactIdentity.publishedIdentityDetails ?? self.obvContactIdentity.trustedIdentityDetails
        
        let cardTypeText: String
        let cardTypeStyle: OlvidCardView.CardTypeStyle
        if let publishedIdentityDetails = self.obvContactIdentity.publishedIdentityDetails, publishedIdentityDetails != self.obvContactIdentity.trustedIdentityDetails {
            cardTypeText = Strings.olvidCardPublished.uppercased()
            cardTypeStyle = .red
        } else {
            cardTypeText = Strings.olvidCard.uppercased()
            cardTypeStyle = .green
        }
        
        guard let animator = animator else {
            firstOlvidCardView.configure(with: detailsToShow, cryptoId: self.obvContactIdentity.cryptoId, cardTypeText: cardTypeText, cardTypeStyle: cardTypeStyle)
            return
        }
        
        animator.addAnimations { [weak self] in
            guard let _self = self else { return }
            _self.firstOlvidCardView.configure(with: detailsToShow, cryptoId: _self.obvContactIdentity.cryptoId, cardTypeText: cardTypeText, cardTypeStyle: cardTypeStyle)
        }
        
    }

    
    private func configureTheSecondOlvidCardAndTheOlvidCardChooserView(animator: UIViewPropertyAnimator?) {
        
        let placeholdersAreHidden: Bool
        if let publishedDetails = self.obvContactIdentity.publishedIdentityDetails, publishedDetails != self.obvContactIdentity.trustedIdentityDetails {
            placeholdersAreHidden = false
        } else {
            placeholdersAreHidden = true
        }
        
        guard let animator = animator else {
            let cardTypeText = Strings.olvidCardTrusted.uppercased()
            secondOlvidCardView.configure(with: self.obvContactIdentity.trustedIdentityDetails, cryptoId: obvContactIdentity.cryptoId, cardTypeText: cardTypeText, cardTypeStyle: .green)
            secondOlvidCardPlaceholder.isHidden = placeholdersAreHidden
            secondOlvidCardPlaceholder.alpha = placeholdersAreHidden ? 0.0 : 1.0
            olvidCardVersionChooserPlaceholder.isHidden = placeholdersAreHidden
            olvidCardVersionChooserPlaceholder.alpha = placeholdersAreHidden ? 0.0 : 1.0
            return
        }
        
        // We animate the card label changes
        animator.addAnimations { [weak self] in
            guard let _self = self else { return }
            let cardTypeText = Strings.olvidCardTrusted.uppercased()
            _self.secondOlvidCardView.configure(with: _self.obvContactIdentity.trustedIdentityDetails, cryptoId: _self.obvContactIdentity.cryptoId, cardTypeText: cardTypeText, cardTypeStyle: .green)
        }
        
        // If there is a change in the iHidden property, we animate it too
        
        guard secondOlvidCardPlaceholder.isHidden != placeholdersAreHidden else { return }
        
        if placeholdersAreHidden {
            
            // We must hide the card
            animator.addAnimations { [weak self] in
                self?.secondOlvidCardPlaceholder.alpha = 0.0
                self?.olvidCardVersionChooserPlaceholder.alpha = 0.0
            }
            let animator2 = UIViewPropertyAnimator(duration: 0.4, curve: .easeInOut)
            animator2.addAnimations { [weak self] in
                self?.secondOlvidCardPlaceholder.isHidden = placeholdersAreHidden
                self?.olvidCardVersionChooserPlaceholder.isHidden = placeholdersAreHidden
            }
            animator.addCompletion { (_) in
                animator2.startAnimation()
            }
            
        } else {
            
            // We must show the card
            // For some reason, we could not make the animator work properly in this case
            
            UIView.animate(withDuration: 0.4, animations: { [weak self] in
                self?.secondOlvidCardPlaceholder.isHidden = placeholdersAreHidden
                self?.olvidCardVersionChooserPlaceholder.isHidden = placeholdersAreHidden
            }) { (_) in
                UIView.animate(withDuration: 0.4, animations: { [weak self] in
                    self?.secondOlvidCardPlaceholder.alpha = 1.0
                    self?.olvidCardVersionChooserPlaceholder.alpha = 1.0
                })
            }
            
        }
        
    }

}


// MARK: - Changes on notifications

extension SingleContactViewController {
    
    private func observeIdentityColorStyleDidChangeNotifications() {
        let token = ObvMessengerInternalNotification.observeIdentityColorStyleDidChange(queue: OperationQueue.main) { [weak self] in
            self?.configureViewsBasedOnPersistedObvContactIdentity()
            self?.configureTheOlvidCards(animated: false)
        }
        self.notificationTokens.append(token)
    }
    
    private func observeUpdatedContactIdentityNotifications() {
        notificationTokens.append(ObvEngineNotificationNew.observeUpdatedContactIdentity(within: NotificationCenter.default) { [weak self] (obvContactIdentity, _, _) in
            guard let _self = self else { return }
            guard _self.obvContactIdentity.cryptoId == obvContactIdentity.cryptoId else { return }
            DispatchQueue.main.async {
                _self.obvContactIdentity = obvContactIdentity
                _self.configureTheOlvidCards(animated: true)
            }
        })        
    }
    
}


// MARK: - Reacting to button taps

extension SingleContactViewController {
    
    @objc func acceptPublishedCardButtonTapped() {
        guard let publishedDetails = self.obvContactIdentity.publishedIdentityDetails else { return }
        delegate?.userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(with: obvContactIdentity.cryptoId, using: publishedDetails)
    }
    

    @objc func introduceToButtonTapped() {
        assert(Thread.current.isMainThread)
        guard let ownedIdentity = persistedObvContactIdentity.ownedIdentity else {
            os_log("Could not find owned identity. This is ok if it was just deleted.", log: log, type: .error)
            return
        }
        let contactsPresentationVC = ContactsPresentationViewController(ownedCryptoId: ownedIdentity.cryptoId, presentedContactCryptoId: persistedObvContactIdentity.cryptoId) {
            self.dismissPresentedViewController()
        }
        contactsPresentationVC.title = Strings.contactsTVCTitle(persistedObvContactIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName))
        present(contactsPresentationVC, animated: true)
    }


    @IBAction func discussionButtonTapped(_ sender: Any) {
        assert(persistedObvContactIdentity.managedObjectContext == ObvStack.shared.viewContext)
        delegate?.userWantsToDisplay(persistedDiscussion: persistedObvContactIdentity.oneToOneDiscussion)
    }
    

    @IBAction func advancedShowContactInfosButtonTapped(_ sender: Any) {
        
        let singleContactDetailedInfosViewController = SingleContactDetailedInfosViewController(persistedObvContactIdentity: self.persistedObvContactIdentity)
        let nav = ObvNavigationController(rootViewController: singleContactDetailedInfosViewController)
        let closeButton = UIBarButtonItem.forClosing(target: self, action: #selector(dismissPresentedViewController))
        singleContactDetailedInfosViewController.navigationItem.setLeftBarButton(closeButton, animated: false)
        self.present(nav, animated: true)
        
    }

    
    @objc
    func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }

    
    @objc func presentLargeContactIdentityViewController() {
        guard let obvContactIdentity = self.obvContactIdentity else { return }
        let details = obvContactIdentity.publishedIdentityDetails ?? obvContactIdentity.trustedIdentityDetails // We accept to show trusted details only if the user never published any details
        let largeOlvidCardVC = LargeOlvidCardViewController(publishedIdentityDetails: details, genericIdentity: obvContactIdentity.getGenericIdentity())
        self.present(largeOlvidCardVC, animated: true)
    }

    

}



// MARK: - Helpers

extension SingleContactViewController {
    
    
    private func configureAndAddTheContactGroupsTVC() {
        // Configure the table view for group discussions
        do {
            let frc = PersistedContactGroup.getFetchedResultsControllerForAllContactGroups(for: persistedObvContactIdentity, within: ObvStack.shared.viewContext)
            let contactGroupsTVC = ContactGroupsTableViewController(fetchedResultsController: frc)
            contactGroupsTVC.cellBackgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
            
            let blockOnNewHeight = { [weak self] (height: CGFloat) in
                // If the contact doesn't belong to any group, we hide the groups view from the stack
                _ = self?.groupsStackView.isHidden = (height == 0)
            }
            contactGroupsTVC.constraintHeightToContentHeight(blockOnNewHeight: blockOnNewHeight)
            contactGroupsTVC.view.translatesAutoresizingMaskIntoConstraints = false
            contactGroupsTVC.delegate = self

            contactGroupsTVC.willMove(toParent: self)
            self.addChild(contactGroupsTVC)
            contactGroupsTVC.didMove(toParent: self)
            
            self.groupsStackView.addArrangedSubview(contactGroupsTVC.view)
            
        }

    }
    
    
    private func configureAndAddTheTrustOriginsTVC() {
        let log = self.log
        trustOriginsSpinner.color = AppTheme.shared.colorScheme.tertiaryLabel
        guard let ownedCryptoId = persistedObvContactIdentity.ownedIdentity?.cryptoId else {
            os_log("Could not find owned identity. This is ok if it was just deleted.", log: log, type: .error)
            return
        }
        let contactCryptoId = persistedObvContactIdentity.cryptoId
        DispatchQueue(label: "displayTrustOrigins").async { [weak self] in
            
            guard let trustOrigins = try? self?.obvEngine.getTrustOriginsOfContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId) else { return }
            
            DispatchQueue.main.async {

                let trustOriginsTVC = TrustOriginsTableViewController(trustOrigins: trustOrigins)
                trustOriginsTVC.cellBackgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground

                let blockOnNewHeight = { [weak self] (height: CGFloat) in
                    _ = self?.trustOriginsSpinnerView.isHidden = (height != 0)
                }
                trustOriginsTVC.constraintHeightToContentHeight(blockOnNewHeight: blockOnNewHeight)
                trustOriginsTVC.view.translatesAutoresizingMaskIntoConstraints = false

                trustOriginsTVC.willMove(toParent: self)
                self?.addChild(trustOriginsTVC)
                trustOriginsTVC.didMove(toParent: self)

                self?.trustOriginsStackView.addArrangedSubview(trustOriginsTVC.view)
                
            }
        }
    }
    
}

// MARK: - Resync the contact with informations from the engine
// Just in case a notification was missed

extension SingleContactViewController {
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let contactCryptoId = self.persistedObvContactIdentity.cryptoId
        guard let ownedCryptoId = self.persistedObvContactIdentity.ownedIdentity?.cryptoId else {
            os_log("Could not find owned identy. This is ok if it was just deleted.", log: log, type: .error)
            return
        }

        resyncWithEngine(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
        markUnseenPublishedDetailsAsSeen(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
        
    }
        
    
    private func markUnseenPublishedDetailsAsSeen(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) {
        ObvMessengerInternalNotification.userDidSeeNewDetailsOfContact(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            .postOnDispatchQueue()
    }

    
    private func resyncWithEngine(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        ObvMessengerInternalNotification.resyncContactIdentityDevicesWithEngine(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            .postOnDispatchQueue()
        ObvMessengerInternalNotification.resyncContactIdentityDetailsStatusWithEngine(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            .postOnDispatchQueue()
    }
    
}




// MARK: - Activating the Discussion Button

extension SingleContactViewController {
    
    private func chooseAppropriateStackElementDependingOnChannelAvailability(animate: Bool) {
        let noChannelWithContact = persistedObvContactIdentity.devices.isEmpty
        let block = { [weak self] in
            self?.channelEstablishingExplanationStackElement.isHidden = !noChannelWithContact
            self?.startDiscussionButton.isHidden = noChannelWithContact
        }
        if animate {
            UIView.animate(withDuration: 0.3, animations: block)
        } else {
            block()
        }
    }
    
    
    private func observeNewPersistedObvContactDeviceNotifications() {
        
        let NotificationName = Notification.Name.NSManagedObjectContextDidSave
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard let context = notification.object as? NSManagedObjectContext else { return }
            guard context.concurrencyType != .mainQueueConcurrencyType else { return }
            context.performAndWait {
                
                guard let userInfo = notification.userInfo else { return }
                guard let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> else { return }
                guard !insertedObjects.isEmpty else { return }
                let insertedPersistedObvContactDevice = insertedObjects.filter { $0 is PersistedObvContactDevice } as! Set<PersistedObvContactDevice>
                guard !insertedPersistedObvContactDevice.isEmpty else { return }
                let appropriateDevices = insertedPersistedObvContactDevice.filter { $0.identity?.objectID == self?.persistedObvContactIdentity.objectID }
                guard !appropriateDevices.isEmpty else { return }
                // If we reach this point, a new device was added to the contact identity. We can enable the discussion button.
                DispatchQueue.main.async { [weak self] in
                    self?.chooseAppropriateStackElementDependingOnChannelAvailability(animate: true)
                }
                
            }
        }
        notificationTokens.append(token)
        
    }
    
    
    private func observeDeletedPersistedObvContactDeviceNotifications() {
        let token = ObvMessengerInternalNotification.observeDeletedPersistedObvContactDevice(queue: OperationQueue.main) { [weak self] (contactCryptoId) in
            guard let _self = self else { return }
            guard contactCryptoId == _self.obvContactIdentity.cryptoId else { return }
            _self.chooseAppropriateStackElementDependingOnChannelAvailability(animate: true)
        }
        notificationTokens.append(token)
    }
    
}

// MARK: - Deleting/Editing the contact

extension SingleContactViewController {
    
    @objc func callButtonTapped() {
        let contactID = persistedObvContactIdentity.typedObjectID
        ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: [contactID], groupId: nil)
            .postOnDispatchQueue()
    }
    
    
    @objc func nicknameButtonTapped() {
        delegate?.userWantsToEditContactNickname(persistedContactObjectId: persistedObvContactIdentity.objectID)
    }
    
    
    @objc func deleteButtonTapped() {

        ObvMessengerInternalNotification.userWantsToDeleteContact(contactCryptoId: self.obvContactIdentity.cryptoId,
                                                                  ownedCryptoId: self.obvContactIdentity.ownedIdentity.cryptoId,
                                                                  viewController: self,
                                                                  completionHandler: { _ in })
            .postOnDispatchQueue()
        
    }
    
    
    private func observeContactWasDeletedNotifications() {
        let token = ObvMessengerInternalNotification.observePersistedContactWasDeleted(queue: OperationQueue.main) { [weak self] (deletedObjectID, _) in
            guard let _self = self else { return }
            guard deletedObjectID == _self.persistedObvContactIdentity.objectID else { return }
            if _self.navigationController?.presentingViewController != nil {
                _self.navigationController?.dismiss(animated: true, completion: nil)
            } else {
                _self.navigationController?.popViewController(animated: true)
            }
        }
        notificationTokens.append(token)
    }
}


// MARK: - Listening to changes made to the contact

extension SingleContactViewController {
    
    private func observeContactUpdates() {
        let NotificationName = Notification.Name.NSManagedObjectContextDidSave
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let context = notification.object as? NSManagedObjectContext else { return }
            guard context.concurrencyType != .mainQueueConcurrencyType else { return }
            context.performAndWait {
                guard let userInfo = notification.userInfo else { return }
                guard let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> else { return }
                guard !updatedObjects.isEmpty else { return }
                let updatedContacts = updatedObjects.filter { $0 is PersistedObvContactIdentity } as! Set<PersistedObvContactIdentity>
                guard !updatedContacts.isEmpty else { return }
                let objectIDs = updatedContacts.map { $0.objectID }
                guard objectIDs.contains(_self.persistedObvContactIdentity.objectID) else { return }
                DispatchQueue.main.async {
                    _self.persistedObvContactIdentity.managedObjectContext?.mergeChanges(fromContextDidSave: notification)
                    _self.configureViewsBasedOnPersistedObvContactIdentity()
                }
            }
        }
        notificationTokens.append(token)
    }
    
}


// MARK: - Reacting to other actions

extension SingleContactViewController {
    
    @IBAction func restartChannelEstablishmentButtonTapped(_ sender: Any) {
        
        guard let ownedIdentity = persistedObvContactIdentity.ownedIdentity else {
            os_log("Could not find owned identity. This is ok if it was just deleted.", log: log, type: .error)
            return
        }
        
        let alert = UIAlertController(title: Strings.AlertRestartChannelEstablishment.title,
                                      message: Strings.AlertRestartChannelEstablishment.message,
                                      preferredStyleForTraitCollection: self.traitCollection)
        let restartAction = UIAlertAction(title: CommonString.Word.Yes, style: .default) { [weak self] (action) in
            guard let _self = self else { return }
            
            let contactCryptoId = _self.persistedObvContactIdentity.cryptoId
            let ownedCryptoId = ownedIdentity.cryptoId
            
            ObvMessengerInternalNotification.userWantsToRestartChannelEstablishmentProtocol(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
                .postOnDispatchQueue()

        }
        let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: UIAlertAction.Style.cancel)
        alert.addAction(restartAction)
        alert.addAction(cancelAction)
        DispatchQueue.main.async { [weak self] in
            self?.present(alert, animated: true)
        }
        
    }

    
    @IBAction func reCreateAllChannelsButtonTapped(_ sender: Any) {
        
        guard let ownedIdentity = persistedObvContactIdentity.ownedIdentity else {
            os_log("Could not find owned identity. This is ok if it was just deleted.", log: log, type: .error)
            return
        }

        let alert = UIAlertController(title: Strings.AlertRestartChannelEstablishment.title,
                                      message: Strings.AlertRestartChannelEstablishment.message,
                                      preferredStyleForTraitCollection: self.traitCollection)
        let restartAction = UIAlertAction(title: CommonString.Word.Yes, style: UIAlertAction.Style.default) { [weak self] (action) in
            guard let _self = self else { return }
            
            let contactCryptoId = _self.persistedObvContactIdentity.cryptoId
            let ownedCryptoId = ownedIdentity.cryptoId
            
            ObvMessengerInternalNotification.userWantsToReCreateChannelEstablishmentProtocol(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
                .postOnDispatchQueue()
            
        }
        let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: UIAlertAction.Style.cancel)
        alert.addAction(restartAction)
        alert.addAction(cancelAction)
        DispatchQueue.main.async { [weak self] in
            self?.present(alert, animated: true)
        }
        
    }

}


// MARK: - ContactGroupsTableViewControllerDelegate

extension SingleContactViewController: ContactGroupsTableViewControllerDelegate {

    func userDidSelect(_ contactGroup: PersistedContactGroup) {
        
        delegate?.userWantsToDisplay(persistedContactGroup: contactGroup, within: navigationController)
        
    }
    
}
