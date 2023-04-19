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

import UIKit
import os.log
import CoreData
import OlvidUtils


final class ComposeMessageDataSourceWithDraft: NSObject, ComposeMessageDataSource, ObvErrorMaker {

    weak var collectionView: UICollectionView? {
        didSet {
            configureCollectionView()
        }
    }
    weak var filesViewer: FilesViewer?

    static let errorDomain = "ComposeMessageDataSourceWithDraft"
    
    private let persistedDraft: PersistedDraft
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ComposeMessageDataSourceWithDraft.self))
    private let fetchedResultsController: NSFetchedResultsController<PersistedDraftFyleJoin>
    private var itemChanges = [(type: NSFetchedResultsChangeType, indexPath: IndexPath?, newIndexPath: IndexPath?)]()


    
    init(draft: PersistedDraft) {
        self.persistedDraft = draft
        self.fetchedResultsController = ComposeMessageDataSourceWithDraft.configureTheFetchedResultsController(draft: draft)
        super.init()
        
        fetchedResultsController.delegate = self
        do {
            try fetchedResultsController.performFetch()
        } catch let error {
            fatalError("Failed to fetch entities: \(error.localizedDescription)")
        }

    }
    
    var draft: Draft {
        return persistedDraft
    }
    
    var body: String? {
        return draft.body
    }
        
    private func configureCollectionView() {
        guard let collectionView = self.collectionView else { return }
        collectionView.register(UINib(nibName: FyleCollectionViewCell.nibName, bundle: nil),
                                forCellWithReuseIdentifier: FyleCollectionViewCell.identifier)
        collectionView.dataSource = self
        collectionView.delegate = self
    }
    
    
    var replyTo: (displayName: String, messageElement: MessageCollectionViewCell.MessageElement)? {
        guard let msg = draft.replyTo else { return nil }
        let displayName: String
        if let sentMsg = msg as? PersistedMessageSent {
            displayName = sentMsg.discussion.ownedIdentity?.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName) ?? ""
        } else if let receivedMsg = msg as? PersistedMessageReceived {
            if let receivedMsgContactIdentity = receivedMsg.contactIdentity {
                displayName = receivedMsgContactIdentity.customDisplayName ?? receivedMsgContactIdentity.identityCoreDetails?.getDisplayNameWithStyle(.firstNameThenLastName) ?? receivedMsgContactIdentity.fullDisplayName
            } else {
                displayName = CommonString.deletedContact
            }
        } else {
            assertionFailure(); return nil
        }
        if let messageElement = MessageCollectionViewCell.extractMessageElements(from: msg) {
            return (displayName, messageElement)
        } else {
            return nil
        }
    }
    
    
    func saveBodyText(body: String) {
        let draftObjectID = persistedDraft.typedObjectID
        let log = self.log
        ObvStack.shared.performBackgroundTask { (context) in
            do {
                guard let writableDraft = try PersistedDraft.get(objectID: draftObjectID, within: context) else { throw Self.makeError(message: "Could not find persisted draft") }
                writableDraft.setContent(with: body)
                try context.save(logOnFailure: log)
            } catch {
                os_log("Could not save draft", log: log, type: .error)
            }
        }
        
    }
    
    
    func deleteReplyTo(completionHandler: @escaping (Error?) -> Void) throws {
        var error: Error? = nil
        let draftObjectID = persistedDraft.typedObjectID
        let log = self.log
        ObvStack.shared.performBackgroundTask { (context) in
            do {
                guard let writableDraft = try PersistedDraft.get(objectID: draftObjectID, within: context) else { return }
                writableDraft.removeReplyTo()
                try context.save(logOnFailure: log)
            } catch let _error {
                error = _error
            }
            completionHandler(error)
        }
    }
    
    var collectionViewIsEmpty: Bool {
        return fetchedResultsController.fetchedObjects?.isEmpty ?? true
    }
}


// MARK: - NSFetchedResultsControllerDelegate

extension ComposeMessageDataSourceWithDraft: NSFetchedResultsControllerDelegate {
    
    private static func configureTheFetchedResultsController(draft: PersistedDraft) -> NSFetchedResultsController<PersistedDraftFyleJoin> {
        
        let fetchRequest: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        fetchRequest.predicate = PersistedDraftFyleJoin.Predicate.withPersistedDraft(draft)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: PersistedDraftFyleJoin.Predicate.Key.index.rawValue, ascending: true)]
        
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: ObvStack.shared.viewContext,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)

        return fetchedResultsController
    }
    
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        itemChanges.append((type, indexPath, newIndexPath))
    }
    
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        
        guard let collectionView = self.collectionView else { return }
        
        collectionView.performBatchUpdates({
            
            while let (type, indexPath, newIndexPath) = itemChanges.popLast() {
                
                switch type {
                case .delete:
                    collectionView.deleteItems(at: [indexPath!])
                case .insert:
                    collectionView.insertItems(at: [newIndexPath!])
                case .move:
                    collectionView.moveItem(at: indexPath!, to: newIndexPath!)
                case .update:
                    collectionView.reloadItems(at: [indexPath!])
                @unknown default:
                    assertionFailure()
                }
                
                
            }
        })
    }
    
}


// MARK: - UICollectionViewDataSource

extension ComposeMessageDataSourceWithDraft: UICollectionViewDataSource {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard section == 0 else { return 0 }
        return fetchedResultsController.fetchedObjects?.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let join = fetchedResultsController.object(at: indexPath)
        let fyleCell = collectionView.dequeueReusableCell(withReuseIdentifier: FyleCollectionViewCell.identifier, for: indexPath) as! FyleCollectionViewCell
        fyleCell.configure(with: join)
        fyleCell.layoutIfNeeded()
        return fyleCell
    }
}


// MARK: - UICollectionViewDelegateFlowLayout

extension ComposeMessageDataSourceWithDraft: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return FyleCollectionViewCell.intrinsicSize
    }
    
}


// MARK: - Deleting draft fyle joins

extension ComposeMessageDataSourceWithDraft {

    func longPress(on indexPath: IndexPath) {
        let objectID = fetchedResultsController.object(at: indexPath).typedObjectID
        self.deleteDraftFyleJoin(draftFyleJoinObjectId: objectID)
    }

    func tapPerformed(on indexPath: IndexPath) {
        let objectID = fetchedResultsController.object(at: indexPath).typedObjectID
        self.deleteDraftFyleJoin(draftFyleJoinObjectId: objectID)
    }
    
    private func deleteDraftFyleJoin(draftFyleJoinObjectId: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) {
        ObvMessengerInternalNotification.userWantsToRemoveDraftFyleJoin(draftFyleJoinObjectID: draftFyleJoinObjectId).postOnDispatchQueue()
    }
    
}
