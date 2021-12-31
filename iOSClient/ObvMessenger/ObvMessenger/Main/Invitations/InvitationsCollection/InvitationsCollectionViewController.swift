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
import ObvTypes
import ObvEngine

final class InvitationsCollectionViewController: ShowOwnedIdentityButtonUIViewController, ViewControllerWithEllipsisCircleRightBarButtonItem {

    private static let nibName = "InvitationsCollectionViewController"

    @IBOutlet weak var collectionViewPlaceholder: UIView!
    private let collectionViewLayout: UICollectionViewLayout
    private let collectionView: UICollectionView
    private var collectionViewSizeChanged = false
    
    // All insets *must* have the same left and right values
    private let collectionViewLayoutInsetFirstSection = UIEdgeInsets(top: 8, left: 8, bottom: 0, right: 8)
    private let collectionViewLayoutInsetSecondSection = UIEdgeInsets(top: 0, left: 8, bottom: 8, right: 8)

    private var notificationTokens = [NSObjectProtocol]()

    var fetchedResultsController: NSFetchedResultsController<PersistedInvitation>! = nil
    
    var currentNumberOfInvitations: Int {
        return fetchedResultsController.sections![0].numberOfObjects
    }
    
    private var doDisplayHelpCell = false
    
    private var keyboardIsShown = false
    
    weak var delegate: InvitationsCollectionViewControllerDelegate?
    
    private var contactsForWhichASASWasEntered = Set<ObvCryptoId>() // Allows to track when bad SAS are entered
    
    // Required within the implementation of NSFetchedResultsControllerDelegate
    private var sectionChanges = [(cvSectionIndex: Int, type: NSFetchedResultsChangeType)]()
    private var itemChanges = [(persistedInvitation: PersistedInvitation, indexPath: IndexPath?, type: NSFetchedResultsChangeType, newIndexPath: IndexPath?)]()

    private var observationTokens = [NSObjectProtocol]()
    private var currentKbdHeight: CGFloat = 0.0
    private static let typicalDurationKbdAnimation: TimeInterval = 0.25
    let animatorForCollectionViewContent = UIViewPropertyAnimator(duration: typicalDurationKbdAnimation*2.3, dampingRatio: 0.65)
    private var activeTextField: UITextField?
    
    var extraBottomInset: CGFloat = 0.0
    
    // MARK: - Initializer
    
    init(ownedCryptoId: ObvCryptoId, collectionViewLayout: UICollectionViewLayout) {
        self.collectionViewLayout = collectionViewLayout
        self.collectionView = UICollectionView.init(frame: CGRect.zero, collectionViewLayout: collectionViewLayout)
        super.init(ownedCryptoId: ownedCryptoId, logCategory: "InvitationsCollectionViewController")
        self.title = CommonString.Word.Invitations
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Mappings between IndexPath

extension InvitationsCollectionViewController {
    
    func frcIndexPathFrom(cvIndexPath: IndexPath) -> IndexPath {
        return IndexPath(item: cvIndexPath.item, section: cvIndexPath.section-1)
    }

    func cvIndexPathFrom(frcIndexPath: IndexPath) -> IndexPath {
        return IndexPath(item: frcIndexPath.item, section: frcIndexPath.section+1)
    }

    func cvSectionIndexFrom(frcSectionIndex: Int) -> Int {
        return frcSectionIndex + 1
    }
}

// MARK: - View controller life cycle

extension InvitationsCollectionViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        registerCells()
        configureFlowLayoutForAutoSizingCells()
        configureTheFetchedResultsController()

        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        self.collectionViewPlaceholder.backgroundColor = AppTheme.shared.colorScheme.systemFill
        
        self.collectionViewPlaceholder.addSubview(self.collectionView)
        self.collectionViewPlaceholder.pinAllSidesToSides(of: self.collectionView)
        
        self.collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.collectionView.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        self.collectionView.keyboardDismissMode = .interactive

        self.collectionView.alwaysBounceVertical = true
        self.extraBottomInset = 16 + 56 // It's height + bottom margin
        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        
        registerTextDidBeginEditingNotification()
        registerTextDidEndEditingNotification()
        registerKeyboardNotifications()
        observeIdentityColorStyleDidChangeNotifications()
        
        if #available(iOS 14, *) {
            navigationItem.rightBarButtonItem = getConfiguredEllipsisCircleRightBarButtonItem()
        } else if #available(iOS 13.0, *) {
            navigationItem.rightBarButtonItem = getConfiguredEllipsisCircleRightBarButtonItem(selector: #selector(ellipsisButtonTappedSelector))
        }

    }
    
    
    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "Used because iOS 13 does not support UIMenu on UIBarButtonItem")
    @objc private func ellipsisButtonTappedSelector() {
        ellipsisButtonTapped(sourceBarButtonItem: navigationItem.rightBarButtonItem)
    }

    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] (_) in
            self?.collectionView.collectionViewLayout.invalidateLayout()
            self?.collectionView.reloadData()
        }
    }
    
    private func observeIdentityColorStyleDidChangeNotifications() {
        let token = ObvMessengerInternalNotification.observeIdentityColorStyleDidChange(queue: OperationQueue.main) { [weak self] in
            self?.collectionView.reloadData()
        }
        self.notificationTokens.append(token)
    }

    
    private func configureFlowLayoutForAutoSizingCells() {
        if let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            flowLayout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        }
    }
    
    
    private func registerCells() {
        self.collectionView.register(UINib(nibName: HelpCardCollectionViewCell.nibName, bundle: nil), forCellWithReuseIdentifier: HelpCardCollectionViewCell.identifier)
        self.collectionView.register(UINib(nibName: TitledCardCollectionViewCell.nibName, bundle: nil), forCellWithReuseIdentifier: TitledCardCollectionViewCell.identifier)
        self.collectionView.register(UINib(nibName: ButtonsCardCollectionViewCell.nibName, bundle: nil), forCellWithReuseIdentifier: ButtonsCardCollectionViewCell.identifier)
        self.collectionView.register(UINib(nibName: SasCardCollectionViewCell.nibName, bundle: nil), forCellWithReuseIdentifier: SasCardCollectionViewCell.identifier)
        self.collectionView.register(UINib(nibName: SasAcceptedCardCollectionViewCell.nibName, bundle: nil), forCellWithReuseIdentifier: SasAcceptedCardCollectionViewCell.identifier)
        self.collectionView.register(UINib(nibName: AcceptGroupInviteCollectionViewCell.nibName, bundle: nil), forCellWithReuseIdentifier: AcceptGroupInviteCollectionViewCell.identifier)
        self.collectionView.register(UINib(nibName: MultipleButtonsCollectionViewCell.nibName, bundle: nil), forCellWithReuseIdentifier: MultipleButtonsCollectionViewCell.identifier)
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Mark all the invitations as "old"
        
        let ownedCryptoId = self.ownedCryptoId
        let log = self.log
        ObvStack.shared.performBackgroundTask { (context) in
            guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else { return }
            do {
                try PersistedInvitation.markAllAsOld(for: persistedOwnedIdentity)
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not mark invitations as old", log: log, type: .error)
            }
        }
        
    }
}


// MARK: - NSFetchedResultsControllerDelegate

extension InvitationsCollectionViewController: NSFetchedResultsControllerDelegate {
    
    private func configureTheFetchedResultsController() {
        fetchedResultsController = PersistedInvitation.getFetchedResultsControllerForOwnedIdentity(with: ownedCryptoId, within: ObvStack.shared.viewContext)
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
        } catch let error {
            fatalError("Failed to fetch entities: \(error.localizedDescription)")
        }
        doDisplayHelpCell = (currentNumberOfInvitations == 0)
    }

    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        let cvSectionIndex = cvSectionIndexFrom(frcSectionIndex: sectionIndex)
        sectionChanges.append((cvSectionIndex, type))
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        guard let persistedInvitation = anObject as? PersistedInvitation else { return }
        var cvIndexPath: IndexPath? = nil
        if let ip = indexPath {
            cvIndexPath = cvIndexPathFrom(frcIndexPath: ip)
        }
        var cvNewIndexPath: IndexPath? = nil
        if let ip = newIndexPath {
            cvNewIndexPath = cvIndexPathFrom(frcIndexPath: ip)
        }
            itemChanges.append((persistedInvitation, cvIndexPath, type, cvNewIndexPath))
    }
    
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        
        var objectsToReload = Set<PersistedInvitation>()
        
        collectionView.performBatchUpdates({
            
            while let (cvSectionIndex, type) = sectionChanges.popLast() {
                
                switch type {
                case .insert:
                    collectionView.insertSections(IndexSet(integer: cvSectionIndex))
                case .delete:
                    collectionView.deleteSections(IndexSet(integer: cvSectionIndex))
                case .move, .update:
                    break
                @unknown default:
                    assertionFailure()
                }

            }
            
            while let (persistedInvitation, indexPath, type, newIndexPath) = itemChanges.popLast() {
                
                switch type {
                case .insert:
                    collectionView.insertItems(at: [newIndexPath!])
                case .delete:
                    collectionView.deleteItems(at: [indexPath!])
                case .update:
                    collectionView.deleteItems(at: [indexPath!])
                    collectionView.insertItems(at: [indexPath!])
                case .move:
                    // It is likely that the current cell does not correpond to the one required by the updated invitation. We cannot simply configure the cell again. So we add it the the set of objects to reload
                    collectionView.moveItem(at: indexPath!, to: newIndexPath!)
                    objectsToReload.insert(persistedInvitation)
                @unknown default:
                    assertionFailure()
                }

                
            }
        }, completion: { [weak self] (_) -> Void in
            guard let _self = self else { return }
            // Display or hide the help cell, depending on the number of current inventations
            if _self.doDisplayHelpCell && _self.currentNumberOfInvitations > 0 {
                _self.doDisplayHelpCell = false
                _self.collectionView.reloadSections([0])
            } else if !_self.doDisplayHelpCell && _self.currentNumberOfInvitations == 0 {
                _self.doDisplayHelpCell = true
                _self.collectionView.reloadSections([0])
            }
            
            // Update the objects that require it
            var cvIndexPathsToReload = Set<IndexPath>()
            for persistedInvitation in objectsToReload {
                guard let frcIndexPath = _self.fetchedResultsController.indexPath(forObject: persistedInvitation) else { continue }
                let cvIndexPath = _self.cvIndexPathFrom(frcIndexPath: frcIndexPath)
                cvIndexPathsToReload.insert(cvIndexPath)
            }
            DispatchQueue(label: "ReloadPersistedInvitationsQueue").asyncAfter(deadline: DispatchTime.now() + .milliseconds(200), execute: {
                DispatchQueue.main.async {
                    _self.collectionView.reloadItems(at: Array(cvIndexPathsToReload))
                }
            })
        })
    }
}


// MARK: - UICollectionViewDataSource

extension InvitationsCollectionViewController: UICollectionViewDataSource {

    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }

    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch section {
        case 0:
            return doDisplayHelpCell ? 1 : 0
        case 1:
            return currentNumberOfInvitations
        default:
            return 0
        }
    }
    
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        switch indexPath.section {
        case 0:
            let helpCell = collectionView.dequeueReusableCell(withReuseIdentifier: HelpCardCollectionViewCell.identifier, for: indexPath)
            if let cell = helpCell as? InvitationCollectionCell {
                configureHelpCell(cell, in: collectionView)
            }
            return helpCell
        case 1:
            let frcIndexPath = frcIndexPathFrom(cvIndexPath: indexPath)
            let persistedInvitation = fetchedResultsController.object(at: frcIndexPath)
            let cell = dequeueReusableCell(for: persistedInvitation.obvDialog.category, in: collectionView, at: indexPath)
            if let cell = cell as? InvitationCollectionCell {
                configure(cell, with: persistedInvitation)
            }
            return cell
        default:
            return UICollectionViewCell()
        }
    }
    
    
    private func dequeueReusableCell(for category: ObvDialog.Category, in collectionView: UICollectionView, at indexPath: IndexPath) -> UICollectionViewCell {
        switch category {
        case .inviteSent:
            return collectionView.dequeueReusableCell(withReuseIdentifier: TitledCardCollectionViewCell.identifier, for: indexPath)
        case .invitationAccepted:
            return collectionView.dequeueReusableCell(withReuseIdentifier: TitledCardCollectionViewCell.identifier, for: indexPath)
        case .mutualTrustConfirmed:
            return collectionView.dequeueReusableCell(withReuseIdentifier: MultipleButtonsCollectionViewCell.identifier, for: indexPath)
        case .acceptInvite:
            return collectionView.dequeueReusableCell(withReuseIdentifier: ButtonsCardCollectionViewCell.identifier, for: indexPath)
        case .sasExchange:
            return collectionView.dequeueReusableCell(withReuseIdentifier: SasCardCollectionViewCell.identifier, for: indexPath)
        case .sasConfirmed:
            return collectionView.dequeueReusableCell(withReuseIdentifier: SasAcceptedCardCollectionViewCell.identifier, for: indexPath)
        case .acceptMediatorInvite:
            return collectionView.dequeueReusableCell(withReuseIdentifier: ButtonsCardCollectionViewCell.identifier, for: indexPath)
        case .mediatorInviteAccepted:
            return collectionView.dequeueReusableCell(withReuseIdentifier: TitledCardCollectionViewCell.identifier, for: indexPath)
        case .acceptGroupInvite:
            return collectionView.dequeueReusableCell(withReuseIdentifier: AcceptGroupInviteCollectionViewCell.identifier, for: indexPath)
        case .groupJoined:
            return collectionView.dequeueReusableCell(withReuseIdentifier: MultipleButtonsCollectionViewCell.identifier, for: indexPath)
        case .increaseMediatorTrustLevelRequired:
            return collectionView.dequeueReusableCell(withReuseIdentifier: MultipleButtonsCollectionViewCell.identifier, for: indexPath)
        case .increaseGroupOwnerTrustLevelRequired:
            return collectionView.dequeueReusableCell(withReuseIdentifier: MultipleButtonsCollectionViewCell.identifier, for: indexPath)
        case .autoconfirmedContactIntroduction:
            return collectionView.dequeueReusableCell(withReuseIdentifier: MultipleButtonsCollectionViewCell.identifier, for: indexPath)
        }
    }
    
    
    private func configureCell(atIndexPath indexPath: IndexPath, with persistedInvitation: PersistedInvitation) {
        guard indexPath.section == 1 else {
            return
        }
        let cell = collectionView.cellForItem(at: indexPath)
        if let cell = cell as? InvitationCollectionCell {
            configure(cell, with: persistedInvitation)
        }
    }
    
    
    private func configure(_ cellToConfigure: InvitationCollectionCell, with persistedInvitation: PersistedInvitation) {
        
        let newWidth = collectionView.bounds.width - collectionViewLayoutInsetFirstSection.left - collectionViewLayoutInsetFirstSection.right

        cellToConfigure.setWidth(to: newWidth)
        
        switch persistedInvitation.obvDialog.category {
            
        case .inviteSent(contactIdentity: let contactURLIdentity):
            guard var cell = cellToConfigure as? TitledCardCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            cell.title = contactURLIdentity.fullDisplayName
            cell.subtitle = Strings.InviteSent.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = contactURLIdentity.cryptoId.colors
            cell.details = Strings.InviteSent.details(contactURLIdentity.fullDisplayName)
            cell.buttonTitle = CommonString.Word.Abort
            cell.buttonAction = {
                [weak self] in self?.abandonInvitation(dialog: persistedInvitation.obvDialog, confirmed: false)
            }
            cell.useLeadingButton()
            
        case .acceptInvite(contactIdentity: let contactIdentity):
            guard var cell = cellToConfigure as? ButtonsCardCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            cell.title = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
            cell.subtitle = Strings.AcceptInvite.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = contactIdentity.cryptoId.colors
            cell.details = Strings.AcceptInvite.details(contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))
            cell.buttonTitle1 = CommonString.Word.Accept
            cell.buttonTitle2 = Strings.AcceptInvite.buttonTitle2
            cell.button1Action = {
                [weak self] in self?.acceptInvitation(dialog: persistedInvitation.obvDialog)
            }
            cell.button2Action = {
                [weak self] in self?.rejectInvitation(dialog: persistedInvitation.obvDialog, confirmed: false)
            }
            
        case .invitationAccepted(contactIdentity: let contactIdentity):
            guard var cell = cellToConfigure as? TitledCardCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            cell.title = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
            cell.subtitle = Strings.InvitationAccepted.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = contactIdentity.cryptoId.colors
            cell.details = Strings.InvitationAccepted.details(contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))
            cell.buttonTitle = CommonString.Word.Abort
            cell.buttonAction = {
                [weak self] in self?.abandonInvitation(dialog: persistedInvitation.obvDialog, confirmed: false)
            }
            cell.useLeadingButton()
            
        case .sasExchange(contactIdentity: let contactIdentity, sasToDisplay: let sasToDisplay, numberOfBadEnteredSas: let numberOfBadEnteredSas):
            guard var cell = cellToConfigure as? SasCardCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            let sas = String.init(data: sasToDisplay, encoding: .utf8) ?? ""
            cell.title = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
            cell.subtitle = Strings.SasExchange.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = contactIdentity.cryptoId.colors
            cell.details = Strings.SasExchange.details(contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName), sas)
            try? cell.setOwnSas(ownSas: sasToDisplay)
            cell.resetContactSas()
            cell.onSasInput = { [weak self] (enteredDigits) in
                self?.contactsForWhichASASWasEntered.insert(contactIdentity.cryptoId)
                self?.onSasInput(dialog: persistedInvitation.obvDialog, enteredDigits)
            }
            cell.onAbort = { [weak self] in
                self?.abandonInvitation(dialog: persistedInvitation.obvDialog, confirmed: false)
            }
            if numberOfBadEnteredSas > 0 && contactsForWhichASASWasEntered.contains(contactIdentity.cryptoId) {
                contactsForWhichASASWasEntered.remove(contactIdentity.cryptoId)
                let alert = UIAlertController(title: Strings.IncorrectSASAlert.title, message: Strings.IncorrectSASAlert.message, preferredStyle: .alert)
                let okAction = UIAlertAction(title: CommonString.Word.Ok, style: .default)
                alert.addAction(okAction)
                self.present(alert, animated: true)
            }
            
        case .sasConfirmed(contactIdentity: let contactIdentity, sasToDisplay: let sasToDisplay, sasEntered: _):
            guard var cell = cellToConfigure as? SasAcceptedCardCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            let sas = String.init(data: sasToDisplay, encoding: .utf8) ?? ""
            cell.title = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
            cell.subtitle = Strings.SasConfirmed.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = contactIdentity.cryptoId.colors
            cell.details = Strings.SasConfirmed.details(contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName), sas)
            try? cell.setOwnSas(ownSas: sasToDisplay)
            cell.buttonTitle = CommonString.Word.Abort
            cell.buttonAction = {
                [weak self] in self?.abandonInvitation(dialog: persistedInvitation.obvDialog, confirmed: false)
            }
            cell.useLeadingButton()
            
        case .mutualTrustConfirmed(contactIdentity: let contactIdentity):
            guard var cell = cellToConfigure as? MultipleButtonsCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            cell.title = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
            cell.subtitle = Strings.MutualTrustConfirmed.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = contactIdentity.cryptoId.colors
            cell.details = Strings.MutualTrustConfirmed.details(contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName))
            // Button for showing the new contact
            cell.addButton(title: Strings.showContactButtonTitle, style: .obvButtonBorderless) { [weak self] in
                guard let _self = self else { return }
                ObvStack.shared.performBackgroundTask { (context) in
                    guard let ownedIdentityObject = try? PersistedObvOwnedIdentity.get(cryptoId: _self.ownedCryptoId, within: context) else { return }
                    guard let contactIdendityObject = try? PersistedObvContactIdentity.get(cryptoId: contactIdentity.cryptoId, ownedIdentity: ownedIdentityObject) else { return }
                    let contactIdentityURI = contactIdendityObject.objectID.uriRepresentation()
                    let deepLink = ObvDeepLink.contactIdentityDetails(contactIdentityURI: contactIdentityURI)
                    ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                        .postOnDispatchQueue()
                }
            }
            // Button for discarding the invitation
            cell.addButton(title: CommonString.Word.Ok, style: .obvButton) { [weak self] in
                try? self?.obvEngine.deleteDialog(with: persistedInvitation.uuid)
            }

        case .acceptMediatorInvite(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
            guard var cell = cellToConfigure as? ButtonsCardCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            cell.title = "\(mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)) → \(contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))"
            cell.subtitle = Strings.AcceptMediatorInvite.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = mediatorIdentity.cryptoId.colors
            cell.details = Strings.AcceptMediatorInvite.details(mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full), contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))
            cell.buttonTitle1 = CommonString.Word.Accept
            cell.buttonTitle2 = Strings.AcceptMediatorInvite.buttonTitle2
            cell.button1Action = { [weak self] in
                self?.respondToAcceptMediatorInvite(dialog: persistedInvitation.obvDialog, acceptInvite: true)
            }
            cell.button2Action = { [weak self] in
                self?.respondToAcceptMediatorInvite(dialog: persistedInvitation.obvDialog, acceptInvite: false)
            }
            
        case .increaseMediatorTrustLevelRequired(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
            guard var cell = cellToConfigure as? MultipleButtonsCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            cell.title = "\(mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)) → \(contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))"
            cell.subtitle = Strings.IncreaseMediatorTrustLevelRequired.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = mediatorIdentity.cryptoId.colors
            cell.details = Strings.IncreaseMediatorTrustLevelRequired.details(mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full), contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))
            // Button for increasing the mediator TL
            do {
                let mediatorName = mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
                let title = Strings.IncreaseMediatorTrustLevelRequired.buttonTitle1(mediatorName)
                cell.addButton(title: title, style: .obvButton) { [weak self] in
                    self?.delegate?.rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: mediatorIdentity.cryptoId, contactFullDisplayName: mediatorName)

                }
            }
            // Button for inviting the introduced identity
            do {
                let remoteFullDisplayName = contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
                let title = Strings.IncreaseMediatorTrustLevelRequired.buttonTitle2(remoteFullDisplayName)
                cell.addButton(title: title, style: .obvButton) { [weak self] in
                    self?.delegate?.performTrustEstablishmentProtocolOfRemoteIdentity(remoteCryptoId: contactIdentity.cryptoId, remoteFullDisplayName: remoteFullDisplayName)
                }
            }
            // Button for aborting
            cell.addButton(title: CommonString.Word.Abort, style: .obvButtonBorderless) {
                [weak self] in self?.abandonInvitation(dialog: persistedInvitation.obvDialog, confirmed: false)
            }

        case .mediatorInviteAccepted(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
            guard var cell = cellToConfigure as? TitledCardCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            cell.title = "\(mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)) → \(contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))"
            cell.subtitle = Strings.MediatorInviteAccepted.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = mediatorIdentity.cryptoId.colors
            cell.details = Strings.MediatorInviteAccepted.details(mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full), contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))
            cell.buttonTitle = CommonString.Word.Abort
            cell.buttonAction = {
                [weak self] in self?.abandonInvitation(dialog: persistedInvitation.obvDialog, confirmed: false)
            }
            cell.useLeadingButton()
            
        case .autoconfirmedContactIntroduction(contactIdentity: let contactIdentity, mediatorIdentity: let mediatorIdentity):
            guard var cell = cellToConfigure as? MultipleButtonsCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            cell.title = "\(mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)) → \(contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))"
            cell.subtitle = Strings.AutoconfirmedContactIntroduction.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = contactIdentity.cryptoId.colors
            cell.details = Strings.AutoconfirmedContactIntroduction.details(mediatorIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full), contactIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))
            // Button for showing the new contact
            cell.addButton(title: Strings.showContactButtonTitle, style: .obvButtonBorderless) { [weak self] in
                guard let _self = self else { return }
                ObvStack.shared.performBackgroundTask { (context) in
                    guard let ownedIdentityObject = try? PersistedObvOwnedIdentity.get(cryptoId: _self.ownedCryptoId, within: context) else { return }
                    guard let contactIdendityObject = try? PersistedObvContactIdentity.get(cryptoId: contactIdentity.cryptoId, ownedIdentity: ownedIdentityObject) else { return }
                    let contactIdentityURI = contactIdendityObject.objectID.uriRepresentation()
                    let deepLink = ObvDeepLink.contactIdentityDetails(contactIdentityURI: contactIdentityURI)
                    ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                        .postOnDispatchQueue()
                }
            }
            // Button for discarding the invitation
            cell.addButton(title: CommonString.Word.Ok, style: .obvButton) { [weak self] in
                try? self?.obvEngine.deleteDialog(with: persistedInvitation.uuid)
            }

        case .acceptGroupInvite(groupMembers: let groupMembers, groupOwner: let groupOwner):
            guard var cell = cellToConfigure as? AcceptGroupInviteCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            cell.title = "\(groupOwner.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))"
            cell.subtitle = Strings.AcceptGroupInvite.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = groupOwner.cryptoId.colors
            cell.details = Strings.AcceptGroupInvite.details(groupOwner.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))
            cell.buttonTitle1 = CommonString.Word.Accept
            cell.buttonTitle2 = CommonString.Word.Decline
            cell.button1Action = { [weak self] in
                self?.acceptGroupInvite(dialog: persistedInvitation.obvDialog)
            }
            cell.button2Action = { [weak self] in
                self?.rejectGroupInvite(dialog: persistedInvitation.obvDialog, confirmed: false)
            }
            cell.setTitle(with: Strings.AcceptGroupInvite.subsubTitle)
            cell.setList(with: groupMembers.map { $0.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full) })

        case .groupJoined(groupOwner: let groupOwner, groupUid: let groupUid):
            guard var cell = cellToConfigure as? MultipleButtonsCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            cell.title = groupOwner.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
            cell.subtitle = Strings.GroupJoined.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = groupOwner.cryptoId.colors
            cell.details = Strings.GroupJoined.details(groupOwner.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName))
            cell.buttonsStackView.axis = .horizontal
            // Button for showing the Contact Group
            cell.addButton(title: Strings.GroupJoined.showGroupButtonTitle, style: .obvButtonBorderless) { [weak self] in
                guard let _self = self else { return }
                ObvStack.shared.performBackgroundTask { (context) in
                    let groupId = (groupUid, groupOwner.cryptoId)
                    guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: _self.ownedCryptoId, within: context) else { return }
                    guard let contactGroup = try? PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: ownedIdentity) else { return }
                    let contactGroupURI = contactGroup.objectID.uriRepresentation()
                    let deepLink = ObvDeepLink.contactGroupDetails(contactGroupURI: contactGroupURI)
                    ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                        .postOnDispatchQueue()
                }
            }
            // Button for discarding the invitation
            cell.addButton(title: CommonString.Word.Ok, style: .obvButton) { [weak self] in
                try? self?.obvEngine.deleteDialog(with: persistedInvitation.uuid)
            }

        case .increaseGroupOwnerTrustLevelRequired(groupOwner: let groupOwner):
            guard var cell = cellToConfigure as? MultipleButtonsCollectionViewCell else {
                os_log("The cell type (%{public}@) does not correspond to the dialog's category of the invitation (%{public}@)", log: log, type: .fault, String(describing: cellToConfigure), persistedInvitation.obvDialog.category.description)
                return
            }
            cell.title = "\(groupOwner.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))"
            cell.subtitle = Strings.IncreaseGroupOwnerTrustLevelRequired.subtitle
            cell.date = persistedInvitation.date
            cell.identityColors = groupOwner.cryptoId.colors
            cell.details = Strings.IncreaseGroupOwnerTrustLevelRequired.details(groupOwner.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))
            // Button for increasing the group owner TL
            do {
                let groupOwnerName = groupOwner.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
                let title = Strings.IncreaseGroupOwnerTrustLevelRequired.buttonTitle(groupOwnerName)
                cell.addButton(title: title, style: .obvButton) { [weak self] in
                    self?.delegate?.rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: groupOwner.cryptoId, contactFullDisplayName: groupOwnerName)
                    
                }
            }
            // Button for aborting
            cell.addButton(title: CommonString.Word.Reject, style: .obvButtonBorderless) { [weak self] in
                self?.rejectGroupInvite(dialog: persistedInvitation.obvDialog, confirmed: false)
            }
        }
        

        if let cell = cellToConfigure as? InvitationCollectionCell & CellContainingHeaderView {
            if persistedInvitation.actionRequired {
                cell.addChip(withText: Strings.chipTitleActionRequired)
            }
            switch persistedInvitation.status {
            case .new:
                cell.addChip(withText: Strings.chipTitleNew)
            case .updated:
                cell.addChip(withText: Strings.chipTitleUpdated)
            case .old:
                break
            }
        }
        
        (cellToConfigure as! UICollectionViewCell).layoutIfNeeded()
        
    }
    
    
    private func configureHelpCell(_ cell: InvitationCollectionCell, in collectionView: UICollectionView) {
        let newWidth = collectionView.bounds.width - collectionViewLayoutInsetFirstSection.left - collectionViewLayoutInsetFirstSection.right - collectionView.contentInset.left - collectionView.contentInset.right
        cell.setWidth(to: newWidth)
        (cell as! UICollectionViewCell).layoutIfNeeded()
    }
    

    private func acceptInvitation(dialog: ObvDialog) {
        DispatchQueue(label: "RespondingToInvitationDialog").async { [weak self] in
            switch dialog.category {
            case .acceptInvite:
                var localDialog = dialog
                try? localDialog.setResponseToAcceptInvite(acceptInvite: true)
                self?.obvEngine.respondTo(localDialog)
            default:
                break
            }
        }
    }
    
    
    private func rejectInvitation(dialog: ObvDialog, confirmed: Bool) {
        let currentTraitCollection = self.traitCollection
        DispatchQueue(label: "RespondingToInvitationDialog").async { [weak self] in
            switch dialog.category {
            case .acceptInvite:
                if confirmed {
                    var localDialog = dialog
                    try? localDialog.setResponseToAcceptInvite(acceptInvite: false)
                    self?.obvEngine.respondTo(localDialog)
                } else {
                    let alert = UIAlertController(title: Strings.AbandonInvitation.title, message: nil, preferredStyleForTraitCollection: currentTraitCollection)
                    alert.addAction(UIAlertAction(title: Strings.AbandonInvitation.actionTitleDiscard, style: .destructive, handler: { [weak self] _ in
                        self?.rejectInvitation(dialog: dialog, confirmed: true)
                    }))
                    alert.addAction(UIAlertAction(title: Strings.AbandonInvitation.actionTitleDontDiscard, style: .default))
                    alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
                    DispatchQueue.main.async { [weak self] in
                        self?.present(alert, animated: true, completion: nil)
                    }
                }
            default:
                break
            }
        }
    }
    
    
    private func respondToAcceptMediatorInvite(dialog: ObvDialog, acceptInvite: Bool) {
        DispatchQueue(label: "RespondingToMediatorInvitationDialog").async { [weak self] in
            switch dialog.category {
            case .acceptMediatorInvite:
                var localDialog = dialog
                try? localDialog.setResponseToAcceptMediatorInvite(acceptInvite: acceptInvite)
                self?.obvEngine.respondTo(localDialog)
            default:
                break
            }
        }
    }
    
    
    private func acceptGroupInvite(dialog: ObvDialog) {
        DispatchQueue(label: "RespondingToGroupInvitationDialog").async { [weak self] in
            switch dialog.category {
            case .acceptGroupInvite:
                var localDialog = dialog
                try? localDialog.setResponseToAcceptGroupInvite(acceptInvite: true)
                self?.obvEngine.respondTo(localDialog)
            default:
                break
            }
        }
    }
    
    
    private func rejectGroupInvite(dialog: ObvDialog, confirmed: Bool) {
        let currentTraitCollection = self.traitCollection
        DispatchQueue(label: "RespondingToGroupInvitationDialog").async { [weak self] in
            switch dialog.category {
            case .acceptGroupInvite,
                 .increaseGroupOwnerTrustLevelRequired:
                if confirmed {
                    var localDialog = dialog
                    switch dialog.category {
                    case .acceptGroupInvite:
                        try? localDialog.setResponseToAcceptGroupInvite(acceptInvite: false)
                    case .increaseGroupOwnerTrustLevelRequired:
                        try? localDialog.rejectIncreaseGroupOwnerTrustLevelRequired()
                    default:
                        return
                    }
                    self?.obvEngine.respondTo(localDialog)
                } else {
                    let alert = UIAlertController(title: Strings.AbandonInvitation.title, message: nil, preferredStyleForTraitCollection: currentTraitCollection)
                    alert.addAction(UIAlertAction(title: Strings.AbandonInvitation.actionTitleDiscard, style: .destructive, handler: { [weak self] _ in
                        self?.rejectGroupInvite(dialog: dialog, confirmed: true)
                    }))
                    alert.addAction(UIAlertAction(title: Strings.AbandonInvitation.actionTitleDontDiscard, style: .default))
                    alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
                    DispatchQueue.main.async { [weak self] in
                        self?.present(alert, animated: true, completion: nil)
                    }
                }
            default:
                break
            }
        }
    }

    
    private func onSasInput(dialog: ObvDialog, _ enteredDigits: String) {
        DispatchQueue(label: "RespondingToSasExchangeDialog").async { [weak self] in
            switch dialog.category {
            case .sasExchange:
                var localDialog = dialog
                try? localDialog.setResponseToSasExchange(otherSas: enteredDigits.data(using: .utf8)!)
                self?.obvEngine.respondTo(localDialog)
            default:
                break
            }
        }
    }
    
    private func abandonInvitation(dialog: ObvDialog, confirmed: Bool) {
        if confirmed {
            DispatchQueue(label: "AbandonInvitation").async { [weak self] in
                ((try? self?.obvEngine.abortProtocol(associatedTo: dialog)) as ()??)
            }
        } else {
            let alert = UIAlertController(title: Strings.AbandonInvitation.title, message: nil, preferredStyleForTraitCollection: self.traitCollection)
            alert.addAction(UIAlertAction(title: Strings.AbandonInvitation.actionTitleDiscard, style: .destructive, handler: { [weak self] _ in
                self?.abandonInvitation(dialog: dialog, confirmed: true)
            }))
            alert.addAction(UIAlertAction(title: Strings.AbandonInvitation.actionTitleDontDiscard, style: .default))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            DispatchQueue.main.async { [weak self] in
                self?.present(alert, animated: true, completion: nil)
            }
        }
    }

    
    private func deletePersistedInvitation(_ persistedInvitation: PersistedInvitation) {
        DispatchQueue(label: "Queue for deleting invitation").async { [weak self] in
            guard let _self = self else { return }
            do {
                try _self.obvEngine.deleteDialog(with: persistedInvitation.uuid)
            } catch {
                os_log("Could not delete persisted invitation", log: _self.log, type: .error)
            }
        }
    }
    
}


// MARK: - UICollectionViewDelegateFlowLayout

extension InvitationsCollectionViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        switch section {
        case 0:
            return collectionViewLayoutInsetFirstSection
        case 1:
            return UIEdgeInsets.init(top: collectionViewLayoutInsetSecondSection.top,
                                     left: collectionViewLayoutInsetSecondSection.left,
                                     bottom: collectionViewLayoutInsetSecondSection.bottom + extraBottomInset,
                                     right: collectionViewLayoutInsetSecondSection.right)
        default:
            // Never occurs
            return UIEdgeInsets.zero
        }
    }
}


// MARK: - Handling keyboard appearance

extension InvitationsCollectionViewController {
    
    func registerTextDidBeginEditingNotification() {
        let NotificationType = MessengerInternalNotification.TextFieldDidBeginEditing.self
        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
            guard let activeTextField = NotificationType.parse(notification) else { return }
            self?.activeTextField = activeTextField
        }
        observationTokens.append(token)
    }

    func registerTextDidEndEditingNotification() {
        let NotificationType = MessengerInternalNotification.TextFieldDidEndEditing.self
        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
            guard let fieldThatEndEditing = NotificationType.parse(notification) else { return }
            guard let activeTextField = self?.activeTextField else { return }
            guard activeTextField == fieldThatEndEditing else { return }
            guard let activeSasView = self?.getSasViewCorrespondingToActiveTextField() else { return }
            _ = activeSasView.resignFirstResponder()
            self?.activeTextField = nil
        }
        observationTokens.append(token)
    }

    
    func registerKeyboardNotifications() {
        
        do {
            let token = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil) { [weak self] (notification) in
                self?.keyboardWillShow(notification)
            }
            observationTokens.append(token)
        }

        do {
            let token = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: nil) { [weak self] (notification) in
                self?.keyboardIsShown = true
            }
            observationTokens.append(token)
        }
        
        do {
            let token = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: nil) { [weak self] (notification) in
                guard self?.keyboardIsShown == true else { return }
                self?.keyboardWillHide(notification)
            }
            observationTokens.append(token)
        }
        
    }
    
    
    private func keyboardWillShow(_ notification: Notification) {
        
        defer {
            if animatorForCollectionViewContent.state != .active {
                animatorForCollectionViewContent.startAnimation()
            }
        }

        let kbdHeight = getKeyboardHeight(notification)
        let tabbarHeight = tabBarController?.tabBar.frame.height ?? 0.0

        guard let activeTextField = self.activeTextField else { return }
        guard let activeCell = getCellCorrespondingToActiveTextField() else { return }
        
        // If the active text field is visible on screen, do not scroll any further. Otherwise, scroll.
        
        var aRect = self.view.frame
        aRect.size.height -= kbdHeight
        let bottomLeftCornerOfActiveTextField = activeTextField.convert(CGPoint(x: 0, y: activeTextField.bounds.height), to: view)
        let doScrollAfterSettingTheCollectionViewBottomInset = !aRect.contains(bottomLeftCornerOfActiveTextField)
        
        setCollectionViewBottomInset(to: kbdHeight - tabbarHeight)

        guard doScrollAfterSettingTheCollectionViewBottomInset else { return }
        
        let cellOrigin = activeCell.convert(CGPoint.zero, to: self.collectionView)
        let cellHeight = activeCell.frame.height
        let collectionViewHeight = collectionView.bounds.height
        let newY = cellOrigin.y + cellHeight - collectionViewHeight + kbdHeight + collectionViewLayoutInsetSecondSection.bottom
        let newContentOffset = CGPoint(x: collectionView.contentOffset.x,
                                       y: max(0, newY))
        animatorForCollectionViewContent.addAnimations { [weak self] in
            self?.collectionView.contentOffset = newContentOffset
        }

    }
    
    private func keyboardWillHide(_ notification: Notification) {

        defer {
            if animatorForCollectionViewContent.state != .active {
                animatorForCollectionViewContent.startAnimation()
            }
        }

        animatorForCollectionViewContent.addAnimations { [weak self] in
            self?.setCollectionViewBottomInset(to: 0.0)
        }
    }
    

    private func getKeyboardHeight(_ notification: Notification) -> CGFloat {
        let userInfo = notification.userInfo!
        let kbSize = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! CGRect).size
        return kbSize.height
    }

    
    private func setCollectionViewBottomInset(to bottom: CGFloat) {
        collectionView.contentInset = UIEdgeInsets(top: collectionView.contentInset.top,
                                                   left: collectionView.contentInset.left,
                                                   bottom: bottom + extraBottomInset,
                                                   right: collectionView.contentInset.right)
        collectionView.scrollIndicatorInsets = UIEdgeInsets(top: collectionView.scrollIndicatorInsets.top,
                                                            left: collectionView.scrollIndicatorInsets.left,
                                                            bottom: bottom + extraBottomInset,
                                                            right: collectionView.scrollIndicatorInsets.right)
        
    }

    
    private func getCellCorrespondingToActiveTextField() -> UICollectionViewCell? {
        guard let activeTextField = self.activeTextField else { return nil }
        var currentSuperView = activeTextField.superview
        while currentSuperView != nil {
            if currentSuperView! is UICollectionViewCell {
                return (currentSuperView! as! UICollectionViewCell)
            } else {
                currentSuperView = currentSuperView!.superview
            }
        }
        return nil
    }
    
    
    private func getSasViewCorrespondingToActiveTextField() -> SasView? {
        guard let activeTextField = self.activeTextField else { return nil }
        var currentSuperView = activeTextField.superview
        while currentSuperView != nil {
            if currentSuperView! is SasView {
                return (currentSuperView! as! SasView)
            } else {
                currentSuperView = currentSuperView!.superview
            }
        }
        return nil
    }
}
