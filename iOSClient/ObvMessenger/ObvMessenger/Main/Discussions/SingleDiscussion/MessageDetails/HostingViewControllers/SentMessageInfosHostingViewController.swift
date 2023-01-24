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

import Foundation
import SwiftUI
import CoreData
import ObvTypes



final class SentMessageInfosHostingViewController: UIHostingController<SentMessageInfosView> {

    private var store: SentMessageInfosViewStore!
    
    init?(messageSent: PersistedMessageSent) {
        assert(messageSent.managedObjectContext?.concurrencyType == .mainQueueConcurrencyType)
        guard let store = SentMessageInfosViewStore(messageSent: messageSent) else { return nil }
        self.store = store
        let view = SentMessageInfosView(store: store)
        super.init(rootView: view)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = Strings.title
        let doneButton = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissPresentedViewController))
        self.navigationItem.setRightBarButton(doneButton, animated: false)
    }

    @objc private func dismissPresentedViewController() {
        if let presentationController = self.navigationController?.presentationController,
           let presentationControllerDelegate = presentationController.delegate {
            presentationControllerDelegate.presentationControllerWillDismiss?(presentationController)
            self.dismiss(animated: true) {
                presentationControllerDelegate.presentationControllerDidDismiss?(presentationController)
            }
        } else {
            self.dismiss(animated: true)
        }
    }

    struct Strings {
        static let title = NSLocalizedString("MESSAGE_INFO", comment: "Title of the screen displaying informations about a specific message within a discussion")
    }

}


fileprivate final class SentMessageInfosViewStore: ObservableObject {
    
    let ownedCryptoId: ObvCryptoId
    @Published var sortedInfos: [RecipientAndInfos]
    @Published var timeBasedDeletionDateString: String?
    @Published var numberOfNewMessagesBeforeSuppression: Int?
    let allSentFyleMessageJoinWithStatus: [SentFyleMessageJoinWithStatus]

    let messageSentObjectID: NSManagedObjectID
    private var notificationTokens = [NSObjectProtocol]()

    @MainActor
    init?(messageSent: PersistedMessageSent) {
        guard let ownedCryptoId = messageSent.discussion.ownedIdentity?.cryptoId else { return nil }
        self.ownedCryptoId = ownedCryptoId
        self.sortedInfos = SentMessageInfosViewStore.computeRecipientAndInfos(from: messageSent.unsortedRecipientsInfos)
        self.messageSentObjectID = messageSent.objectID
        self.timeBasedDeletionDateString = nil
        self.numberOfNewMessagesBeforeSuppression = nil
        self.allSentFyleMessageJoinWithStatus = messageSent.fyleMessageJoinWithStatuses
        observePersistedMessageSentRecipientInfosUpdates()
        refreshRetentionInformation()
    }
    
    
    deinit {
        notificationTokens.forEach { token in
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    
    private static func computeRecipientAndInfos(from unsortedInfos: Set<PersistedMessageSentRecipientInfos>) -> [RecipientAndInfos] {
        let readInfos = unsortedInfos
            .filter { $0.timestampRead != nil }
            .sorted { $0.timestampRead! < $1.timestampRead! }
            .sorted { $0.recipientName < $1.recipientName }
            .sorted { $0.recipientCryptoId < $1.recipientCryptoId }
            .map({ RecipientAndInfos(infos: $0, dateStringFromDate: dateStringFromDate) })
        let deliveredInfos = unsortedInfos
            .filter { $0.timestampRead == nil && $0.timestampDelivered != nil }
            .sorted { $0.timestampDelivered! < $1.timestampDelivered! }
            .sorted { $0.recipientName < $1.recipientName }
            .sorted { $0.recipientCryptoId < $1.recipientCryptoId }
            .map({ RecipientAndInfos(infos: $0, dateStringFromDate: dateStringFromDate) })
        let sentInfos = unsortedInfos
            .filter { $0.timestampRead == nil && $0.timestampDelivered == nil && $0.timestampMessageSent != nil }
            .sorted { $0.timestampMessageSent! < $1.timestampMessageSent! }
            .sorted { $0.recipientName < $1.recipientName }
            .sorted { $0.recipientCryptoId < $1.recipientCryptoId }
            .map({ RecipientAndInfos(infos: $0, dateStringFromDate: dateStringFromDate) })
        let pendingInfos = unsortedInfos
            .filter { $0.timestampRead == nil && $0.timestampDelivered == nil && $0.timestampMessageSent == nil }
            .sorted { $0.recipientName < $1.recipientName }
            .sorted { $0.recipientCryptoId < $1.recipientCryptoId }
            .map({ RecipientAndInfos(infos: $0, dateStringFromDate: dateStringFromDate) })
        return readInfos + deliveredInfos + sentInfos + pendingInfos
    }


    static func dateStringFromDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        return dateFormater.string(from: date)
    }
    
    
    private static let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .medium
        df.locale = Locale.current
        return df
    }()

    
    private func observePersistedMessageSentRecipientInfosUpdates() {
        let NotificationName = Notification.Name.NSManagedObjectContextDidSave
        notificationTokens.append(NotificationCenter.default.addObserver(forName: NotificationName, object: nil, queue: nil) { [weak self] (notification) in
            guard let messageSentObjectID = self?.messageSentObjectID else { return }
            guard let context = notification.object as? NSManagedObjectContext else { return }
            guard context.concurrencyType != .mainQueueConcurrencyType else { return }
            context.perform {
                guard let userInfo = notification.userInfo else { return }
                guard let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> else { return }
                guard !updatedObjects.isEmpty else { return }
                let updatedInfos = updatedObjects.compactMap { $0 as? PersistedMessageSentRecipientInfos }
                guard !updatedInfos.isEmpty else { return }
                let relevantUpdatedInfos = updatedInfos.filter({ $0.messageSent.objectID == messageSentObjectID })
                guard !relevantUpdatedInfos.isEmpty else { return }
                DispatchQueue.main.async {
                    ObvStack.shared.viewContext.mergeChanges(fromContextDidSave: notification)
                    guard let messageSent = try? PersistedMessageSent.get(with: messageSentObjectID, within: ObvStack.shared.viewContext) as? PersistedMessageSent else { return }
                    withAnimation {
                        self?.objectWillChange.send()
                        self?.sortedInfos = SentMessageInfosViewStore.computeRecipientAndInfos(from: messageSent.unsortedRecipientsInfos)
                    }
                }
            }
        })
    }


    private func refreshRetentionInformation() {
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            let timeBasedDeletionDateString = self?.computeTimeBasedDeletionDate(within: context)
            let numberOfNewMessagesBeforeSuppression = self?.computeNumberOfNewMessagesBeforeSuppression(within: context)
            DispatchQueue.main.async {
                withAnimation {
                    self?.timeBasedDeletionDateString = timeBasedDeletionDateString
                    self?.numberOfNewMessagesBeforeSuppression = numberOfNewMessagesBeforeSuppression
                }
            }
        }
    }
    
    
    private func computeTimeBasedDeletionDate(within context: NSManagedObjectContext) -> String? {
        guard let messageSent = try? PersistedMessageSent.get(with: messageSentObjectID, within: context) as? PersistedMessageSent else { return nil }
        guard messageSent.wasSentOrCouldNotBeSentToOneOrMoreRecipients else { return nil }
        guard let timeInterval = messageSent.discussion.effectiveTimeIntervalRetention else { return nil }
        let deletionDate = Date(timeInterval: timeInterval, since: messageSent.timestamp)
        return SentMessageInfosViewStore.dateFormater.string(from: deletionDate)
    }
    
    
    private func computeNumberOfNewMessagesBeforeSuppression(within context: NSManagedObjectContext) -> Int? {
        guard let messageSent = try? PersistedMessageSent.get(with: messageSentObjectID, within: context) as? PersistedMessageSent else { return nil }
        guard messageSent.wasSentOrCouldNotBeSentToOneOrMoreRecipients else { return nil }
        let discussion = messageSent.discussion
        guard let countBasedRetention = discussion.effectiveCountBasedRetention else { return nil }
        var totalNumberOfMessagesInDiscussionAfterThisMessage = 0
        do {
            let count = try PersistedMessageSent.countAllSentMessages(after: messageSentObjectID, discussion: discussion)
            totalNumberOfMessagesInDiscussionAfterThisMessage += count
        } catch { return nil }
        do {
            let count = try PersistedMessageReceived.countAllSentMessages(after: messageSentObjectID, discussion: discussion)
            totalNumberOfMessagesInDiscussionAfterThisMessage += count
        } catch { return nil }
        let numberOfNewMessagesBeforeSuppression = countBasedRetention - totalNumberOfMessagesInDiscussionAfterThisMessage
        return numberOfNewMessagesBeforeSuppression
    }
    
}


fileprivate struct RecipientAndInfos: Identifiable {
    let id: Data
    let recipientName: String
    let readTimestampAsString: String?
    let deliveredTimestampAsString: String?
    let sentTimestampAsString: String?
    let couldNotBeSentToServer: Bool

    init(infos: PersistedMessageSentRecipientInfos, dateStringFromDate: (Date?) -> String?) {
        self.id = infos.recipientCryptoId.getIdentity()
        self.recipientName = infos.recipientName
        self.readTimestampAsString = dateStringFromDate(infos.timestampRead)
        self.deliveredTimestampAsString = dateStringFromDate(infos.timestampDelivered)
        self.sentTimestampAsString = dateStringFromDate(infos.timestampMessageSent)
        self.couldNotBeSentToServer = infos.couldNotBeSentToServer
    }
}


struct SentMessageInfosView: View {
    
    @ObservedObject fileprivate var store: SentMessageInfosViewStore
    
    var body: some View {
        SentMessageInfosInnerView(ownedCryptoId: store.ownedCryptoId,
                                  sortedInfos: store.sortedInfos,
                                  timeBasedDeletionDateString: store.timeBasedDeletionDateString,
                                  numberOfNewMessagesBeforeSuppression: store.numberOfNewMessagesBeforeSuppression,
                                  messageObjectID: store.messageSentObjectID,
                                  dateStringFromDate: SentMessageInfosViewStore.dateStringFromDate,
                                  allSentFyleMessageJoinWithStatus: store.allSentFyleMessageJoinWithStatus)
            .environment(\.managedObjectContext, ObvStack.shared.viewContext)
    }
    
}


struct SentMessageInfosInnerView: View {
    
    let ownedCryptoId: ObvCryptoId
    fileprivate let sortedInfos: [RecipientAndInfos]
    let timeBasedDeletionDateString: String?
    let numberOfNewMessagesBeforeSuppression: Int?
    var messageObjectID: NSManagedObjectID
    let dateStringFromDate: (Date?) -> String?
    let allSentFyleMessageJoinWithStatus: [SentFyleMessageJoinWithStatus]

    private var readInfos: [RecipientAndTimestamp] {
        sortedInfos.filter({ $0.readTimestampAsString != nil })
            .map({ RecipientAndTimestamp(id: $0.id, recipientName: $0.recipientName, timestampAsString: $0.readTimestampAsString!) })
    }
    
    private var deliveredInfos: [RecipientAndTimestamp] {
        sortedInfos.filter({ $0.readTimestampAsString == nil && $0.deliveredTimestampAsString != nil })
            .map({ RecipientAndTimestamp(id: $0.id, recipientName: $0.recipientName, timestampAsString: $0.deliveredTimestampAsString!) })
    }
    
    private var sentInfos: [RecipientAndTimestamp] {
        sortedInfos.filter({ $0.readTimestampAsString == nil && $0.deliveredTimestampAsString == nil && $0.sentTimestampAsString != nil })
            .map({ RecipientAndTimestamp(id: $0.id, recipientName: $0.recipientName, timestampAsString: $0.sentTimestampAsString!) })
    }
    
    private var pendingInfos: [Recipient] {
        // The only difference with failedInfos is that couldNotBeSentToServer is false
        sortedInfos.filter({ $0.readTimestampAsString == nil && $0.deliveredTimestampAsString == nil && $0.sentTimestampAsString == nil && !$0.couldNotBeSentToServer })
            .map({ Recipient(id: $0.id, recipientName: $0.recipientName) })
    }

    private var failedInfos: [Recipient] {
        // The only difference with pendingInfos is that couldNotBeSentToServer is true
        return sortedInfos.filter({ $0.readTimestampAsString == nil && $0.deliveredTimestampAsString == nil && $0.sentTimestampAsString == nil && $0.couldNotBeSentToServer })
            .map({ Recipient(id: $0.id, recipientName: $0.recipientName) })
    }

    var body: some View {
        List {
            MessageMetadatasSectionView(messageObjectID: messageObjectID,
                                        ownedCryptoId: ownedCryptoId,
                                        stringFromDate: dateStringFromDate)
            if sortedInfos.count == 1 {
                Section {
                    DateInfosOfSentMessageToSingleContact(dateRead: sortedInfos.first!.readTimestampAsString,
                                                          dateDelivered: sortedInfos.first!.deliveredTimestampAsString,
                                                          dateSent: sortedInfos.first!.sentTimestampAsString)
                }
            } else {
                DateInfosOfSentMessageToManyContactsInnerView(read: readInfos,
                                                              delivered: deliveredInfos,
                                                              sent: sentInfos,
                                                              pending: pendingInfos,
                                                              failed: failedInfos)
            }

            AllSentFyleMessageJoinWithStatusView(allSentFyleMessageJoinWithStatus: allSentFyleMessageJoinWithStatus)
            
            if timeBasedDeletionDateString != nil || numberOfNewMessagesBeforeSuppression != nil {
                MessageRetentionInfoSectionView(timeBasedDeletionDateString: timeBasedDeletionDateString,
                                                numberOfNewMessagesBeforeSuppression: numberOfNewMessagesBeforeSuppression)
            }
        }.listStyle(GroupedListStyle())
    }
    
}
