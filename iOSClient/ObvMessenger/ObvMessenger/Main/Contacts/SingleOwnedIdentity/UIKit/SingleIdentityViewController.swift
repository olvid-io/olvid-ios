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
import os.log
import ObvEngine
import CoreData

class SingleIdentityViewController: UIViewController {

    private static let nibName = "SingleOwnedIdentityViewController"
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    private let persistedObvOwnedIdentity: PersistedObvOwnedIdentity
    private var obvOwnedIdentity: ObvOwnedIdentity?
    private var notificationTokens = [NSObjectProtocol]()
    private var transientTokens = [NSObjectProtocol]()

    weak var delegate: SingleOwnedIdentityViewControllerDelegate?
    
    // Views
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var mainStackView: UIStackView!

    @IBOutlet weak var topStackView: UIStackView!
    @IBOutlet weak var circlePlaceholder: UIView!
    @IBOutlet weak var titleLabel: UILabel!
    
    @IBOutlet weak var publishedOlvidCardPlaceholder: UIView!
    private var publishedOlvidCardView: OlvidCardView!
    private var circledInitials: CircledInitials!
    private var publishedOlvidCardShareButton: UIButton!
    private var showQRCodeButton: UIButton!
    private var latestOlvidCardDiscardButton: UIButton!
    private var latestOlvidCardPublishButton: UIButton!
    
    @IBOutlet weak var refreshSubscriptionStatusButton: UIButton!
    @IBOutlet weak var fallbackOnFreeVersionButton: UIButton!
    
    // Other variables

    let olvidCardsSideConstants: CGFloat = 16.0
    let customSpacingAfterTopStackView: CGFloat = 32.0

    
    // Initializer
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        scrollView.alwaysBounceVertical = true
        mainStackView.setCustomSpacing(customSpacingAfterTopStackView, after: topStackView)
        extendedLayoutIncludesOpaqueBars = true

        circlePlaceholder.backgroundColor = .clear
        titleLabel.textColor = AppTheme.shared.colorScheme.label
        
        publishedOlvidCardView = (Bundle.main.loadNibNamed(OlvidCardView.nibName, owner: nil, options: nil)!.first as! OlvidCardView)
        publishedOlvidCardPlaceholder.backgroundColor = .clear
        publishedOlvidCardPlaceholder.addSubview(publishedOlvidCardView)
        publishedOlvidCardPlaceholder.pinAllSidesToSides(of: publishedOlvidCardView, sideConstants: olvidCardsSideConstants)

        circledInitials = (Bundle.main.loadNibNamed(CircledInitials.nibName, owner: nil, options: nil)!.first as! CircledInitials)
        circledInitials.withShadow = true
        circlePlaceholder.addSubview(circledInitials)
        circlePlaceholder.pinAllSidesToSides(of: circledInitials)

        refreshSubscriptionStatusButton.setTitle(NSLocalizedString("SUBSCRIPTION_STATUS", comment: ""), for: .normal)
        fallbackOnFreeVersionButton.setTitle(NSLocalizedString("Fallback to free version", comment: ""), for: .normal)
        
        do {
            obvOwnedIdentity = try obvEngine.getOwnedIdentity(with: persistedObvOwnedIdentity.cryptoId)
        } catch {
            os_log("Could not get an ObvOwnedIdentity from engine", log: log, type: .fault)
        }

        let buttonItems: [UIBarButtonItem]
        if #available(iOS 13, *) {
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
            let editBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "pencil.circle", withConfiguration: symbolConfiguration), style: .plain, target: self, action: #selector(editPublishedDetails))
            let settingsBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "gear", withConfiguration: symbolConfiguration), style: .plain, target: self, action: #selector(presentSettings))
            buttonItems = [settingsBarButtonItem, editBarButtonItem]
        } else {
            let editBarButtonItem = UIBarButtonItem(barButtonSystemItem: .compose, target: self, action: #selector(editPublishedDetails))
            let settingsBarButtonItem = UIBarButtonItem(title: CommonString.Word.Settings, style: .plain, target: self, action: #selector(presentSettings))
            buttonItems = [settingsBarButtonItem, editBarButtonItem]
        }
        self.navigationItem.rightBarButtonItems = buttonItems

        title = CommonString.Title.myId
        circledInitials.identityColors = persistedObvOwnedIdentity.cryptoId.colors
        configureTheOlvidCards(animated: false)
        self.configureTopTitle()

        notificationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeUpdatedOwnedIdentity(within: NotificationCenter.default, queue: .main) { [weak self] ownedIdentity in
                self?.processUpdatedOwnedIdentityNotification(obvOwnedIdentity: ownedIdentity)
            },
        ])
        observePersistedIdentityChanges()
        observeIdentityColorStyleDidChangeNotifications()
    }
    
    
    private func observeIdentityColorStyleDidChangeNotifications() {
        let token = ObvMessengerInternalNotification.observeIdentityColorStyleDidChange(queue: OperationQueue.main) { [weak self] in
            guard let _self = self else { return }
            self?.circledInitials.identityColors = _self.persistedObvOwnedIdentity.cryptoId.colors
            self?.configureTheOlvidCards(animated: false)
        }
        self.notificationTokens.append(token)
    }

    
    private func configureTopTitle() {
        titleLabel.text = persistedObvOwnedIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
        circledInitials.showCircledText(from: persistedObvOwnedIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName))
    }
    
    // Initialisers
    
    init(persistedObvOwnedIdentity: PersistedObvOwnedIdentity) {
        self.persistedObvOwnedIdentity = persistedObvOwnedIdentity
        super.init(nibName: SingleIdentityViewController.nibName, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func observePersistedIdentityChanges() {
        let NotificationName = Notification.Name.NSManagedObjectContextDidSave
        let token = NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let userInfo = notification.userInfo else { return }
            if let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>, !updatedObjects.isEmpty {
                let updatedPersistedObvOwnedIdentity = updatedObjects.filter { $0 is PersistedObvOwnedIdentity } as! Set<PersistedObvOwnedIdentity>
                if !updatedPersistedObvOwnedIdentity.isEmpty {
                    DispatchQueue.main.async {
                        _self.configureTopTitle()
                    }
                }
            }
        }
        notificationTokens.append(token)
    }
    
    private func processUpdatedOwnedIdentityNotification(obvOwnedIdentity: ObvOwnedIdentity) {
        assert(Thread.isMainThread)
        self.obvOwnedIdentity = obvOwnedIdentity
        configureTopTitle()
        configureTheOlvidCards(animated: true)
    }

    
    private let df: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .full
        return df
    }()

    @IBAction func refreshSubscriptionStatusButtonTapped(_ sender: Any) {
        showHUD(type: .spinner)
        let ownedCryptoId = persistedObvOwnedIdentity.cryptoId
        DispatchQueue(label: "Queue for refreshing API permissions").async { [weak self] in
            // Before performing a query to the engine, we subscribe to the appropriate notification to allow user feedback
            self?.transientTokens.append(ObvEngineNotificationNew.observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within: NotificationCenter.default, queue: OperationQueue.main, block: { (_, _, _, _) in
                guard let _self = self else { return }
                guard !_self.transientTokens.isEmpty else { return }
                _self.transientTokens.forEach { NotificationCenter.default.removeObserver($0) }
                self?.transientTokens.removeAll()
                // Instead of looking at the engine information, we query the local app db (after 1 second), as it should contain the updated information
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) {
                    let df = _self.df
                    guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { return }
                    let apiKeyStatus = ownedIdentity.apiKeyStatus
                    let alertMessage: String
                    switch apiKeyStatus {
                    case .unknown:
                        alertMessage = NSLocalizedString("No active subscription", comment: "")
                    case .valid:
                        if let date = ownedIdentity.apiKeyExpirationDate {
                            alertMessage = String.localizedStringWithFormat(NSLocalizedString("Valid until %@", comment: ""), df.string(from: date))
                        } else {
                            alertMessage = NSLocalizedString("Valid license", comment: "")
                        }
                    case .licensesExhausted:
                        alertMessage = NSLocalizedString("This subscription is already associated to another user", comment: "")
                    case .expired:
                        if let date = ownedIdentity.apiKeyExpirationDate {
                            alertMessage = String.localizedStringWithFormat(NSLocalizedString("Expired since %@", comment: ""), df.string(from: date))
                        } else {
                            alertMessage = NSLocalizedString("Subscription expired", comment: "")
                        }
                    case .free:
                        if let date = ownedIdentity.apiKeyExpirationDate {
                            alertMessage = String.localizedStringWithFormat(NSLocalizedString("Premium features are available for free until %@", comment: ""), df.string(from: date))
                        } else {
                            alertMessage = NSLocalizedString("Premium features tryout", comment: "")
                        }
                    case .freeTrial:
                        if let date = ownedIdentity.apiKeyExpirationDate {
                            alertMessage = String.localizedStringWithFormat(NSLocalizedString("Premium features available until %@", comment: ""), df.string(from: date))
                        } else {
                            alertMessage = NSLocalizedString("Premium features free trial", comment: "")
                        }
                    case .awaitingPaymentGracePeriod:
                        if let date = ownedIdentity.apiKeyExpirationDate {
                            alertMessage = String.localizedStringWithFormat(NSLocalizedString("GRACE_PERIOD_ENDS_ON_%@)", comment: ""), df.string(from: date))
                        } else {
                            alertMessage = NSLocalizedString("BILLING_GRACE_PERIOD", comment: "")
                        }
                    case .awaitingPaymentOnHold:
                        alertMessage = NSLocalizedString("GRACE_PERIOD_ENDED", comment: "")
                    case .freeTrialExpired:
                        alertMessage = NSLocalizedString("FREE_TRIAL_EXPIRED", comment: "")
                    }
                    let alert = UIAlertController(title: NSLocalizedString("SUBSCRIPTION_STATUS", comment: ""),
                                                  message: alertMessage,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction.init(title: CommonString.Word.Ok, style: .default))
                    self?.hideHUD()
                    self?.present(alert, animated: true)
                }
            }))
            // Call the engine
            try? self?.obvEngine.refreshAPIPermissions(for: ownedCryptoId)
        }
    }
    
    @IBAction func fallbackOnFreeVersionButtonTapped(_ sender: Any) {
        userWantsToFallbackOnFreeVersion(confirmed: false)
    }
    
    
    private func userWantsToFallbackOnFreeVersion(confirmed: Bool) {
        guard confirmed else {
            let alert = UIAlertController(title: NSLocalizedString("Fallback to free version", comment: ""),
                                          message: NSLocalizedString("FALLBACK_FREE_VERSION_WARNING", comment: ""),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .destructive, handler: { [weak self] (_) in
                self?.userWantsToFallbackOnFreeVersion(confirmed: true)
            }))
            present(alert, animated: true)
            return
        }
        
        // We liste to engine notification to give the user some feedback
        transientTokens.append(ObvEngineNotificationNew.observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate) in
            guard let _self = self else { return }
            guard !_self.transientTokens.isEmpty else { return }
            _self.transientTokens.forEach { NotificationCenter.default.removeObserver($0) }
            _self.transientTokens.removeAll()
            guard self?.persistedObvOwnedIdentity.cryptoId == ownedIdentity else { return }
            guard apiKeyStatus == .free else { return }
            self?.showHUD(type: .text(text: "✔"))
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                self?.hideHUD()
            }
        })

        guard let hardcodedAPIKey = ObvMessengerConstants.hardcodedAPIKey else {
            assertionFailure()
            return
        }
        
        showHUD(type: .spinner)
        
        ObvMessengerInternalNotification.userRequestedNewAPIKeyActivation(ownedCryptoId: persistedObvOwnedIdentity.cryptoId, apiKey: hardcodedAPIKey)
            .postOnDispatchQueue()
    }

    
}

// MARK: - Configuring the OlvidCards

extension SingleIdentityViewController {
    
    func configureTheOlvidCards(animated: Bool) {
        guard self.obvOwnedIdentity != nil else { return }
        guard self.publishedOlvidCardView != nil else { return }

        let animator = UIViewPropertyAnimator(duration: 0.4, curve: .easeInOut)
        
        configureThePublishedOlvidCard(animated: animated, animator: animator)

        if animated {
            animator.startAnimation()
        }
        
    }
    
    
    private func configureThePublishedOlvidCard(animated: Bool, animator: UIViewPropertyAnimator) {
        
        guard let obvOwnedIdentity = self.obvOwnedIdentity else { return }
        
        let cardTypeText = Strings.olvidCardPublished.uppercased()
        publishedOlvidCardView.configure(with: obvOwnedIdentity.publishedIdentityDetails, cryptoId: obvOwnedIdentity.cryptoId, cardTypeText: cardTypeText, cardTypeStyle: .green)
        
        if publishedOlvidCardShareButton == nil {
            publishedOlvidCardShareButton = ObvButton()
            publishedOlvidCardShareButton.setTitle(CommonString.Word.Invite, for: .normal)
            publishedOlvidCardShareButton.addTarget(self, action: #selector(sharePublishedDetails), for: .touchUpInside)
            publishedOlvidCardView.addButton(publishedOlvidCardShareButton)
        }
        
        if showQRCodeButton == nil {
            showQRCodeButton = ObvButton()
            showQRCodeButton.setTitle(CommonString.Title.qrCode, for: .normal)
            showQRCodeButton.addTarget(self, action: #selector(presentLargeOwnedIdentityViewController(recognizer:)), for: .touchUpInside)
            publishedOlvidCardView.addButton(showQRCodeButton)
        }
        
    }
    
    
    @objc func editPublishedDetails() {
        delegate?.editOwnedPublishedIdentityDetails()
    }
    
    @objc func presentSettings() {
        guard let cryptoId = obvOwnedIdentity?.cryptoId else { assertionFailure(); return }
        let vc = SettingsFlowViewController.create(ownedCryptoId: cryptoId)
        let closeButton = UIBarButtonItem.forClosing(target: self, action: #selector(dismissPresentedViewController))
        vc.viewControllers.first?.navigationItem.setLeftBarButton(closeButton, animated: false)
        present(vc, animated: true)
    }
    
    @objc func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }
 
    @objc func sharePublishedDetails(sender: UIButton) {
        ObvMessengerInternalNotification.userWantsToShareOwnPublishedDetails(ownedCryptoId: persistedObvOwnedIdentity.cryptoId, sourceView: sender)
            .postOnDispatchQueue()
    }

    
    @objc private func presentLargeOwnedIdentityViewController(recognizer: UITapGestureRecognizer) {
        guard let obvOwnedIdentity = self.obvOwnedIdentity else { return }
        let largeOlvidCardVC = LargeOlvidCardViewController(publishedIdentityDetails: obvOwnedIdentity.publishedIdentityDetails, genericIdentity: obvOwnedIdentity.getGenericIdentity())
        self.present(largeOlvidCardVC, animated: true)
    }
}
