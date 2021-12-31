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

import Foundation
import SwiftUI
import CoreData
import ObvEngine


@available(iOS 13.0, *)
final class ReceivedMessageInfosHostingViewController: UIHostingController<ReceivedMessageInfosView> {

    private var store: ReceivedMessageInfosViewStore!
    
    init?(messageReceived: PersistedMessageReceived) {
        guard let store = ReceivedMessageInfosViewStore(messageReceived: messageReceived) else { return nil }
        self.store = store
        let view = ReceivedMessageInfosView(store: store)
        super.init(rootView: view)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}


@available(iOS 13.0, *)
fileprivate final class ReceivedMessageInfosViewStore: ObservableObject {
    
    let ownedCryptoId: ObvCryptoId
    @Published var timeBasedDeletionDateString: String?
    @Published var numberOfNewMessagesBeforeSuppression: Int?
    @Published var receivedDateString: String
    @Published var readDateString: String?

    let messageReceivedObjectID: NSManagedObjectID

    init?(messageReceived: PersistedMessageReceived) {
        guard let ownedCryptoId = messageReceived.discussion.ownedIdentity?.cryptoId else { return nil }
        self.ownedCryptoId = ownedCryptoId
        self.messageReceivedObjectID = messageReceived.objectID
        self.timeBasedDeletionDateString = nil
        self.numberOfNewMessagesBeforeSuppression = nil
        self.receivedDateString = ReceivedMessageInfosViewStore.dateFormater.string(from: messageReceived.timestamp)
        self.readDateString = ReceivedMessageInfosViewStore.dateStringFromDate(messageReceived.sortedMetadata.first(where: { $0.kind == .read })?.date)
        refreshRetentionInformation()
    }
    
    private static let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .medium
        df.locale = Locale.current
        return df
    }()

    static func dateStringFromDate(_ date: Date?) -> String? {
        date == nil ? nil : dateFormater.string(from: date!)
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
        guard let messageReceived = try? PersistedMessageReceived.get(with: messageReceivedObjectID, within: context) as? PersistedMessageReceived else { return nil }
        guard let timeInterval = messageReceived.discussion.effectiveTimeIntervalRetention else { return nil }
        let deletionDate = Date(timeInterval: timeInterval, since: messageReceived.timestamp)
        return ReceivedMessageInfosViewStore.dateFormater.string(from: deletionDate)
    }

    private func computeNumberOfNewMessagesBeforeSuppression(within context: NSManagedObjectContext) -> Int? {
        guard let messageReceived = try? PersistedMessageReceived.get(with: messageReceivedObjectID, within: context) as? PersistedMessageReceived else { return nil }
        let discussion = messageReceived.discussion
        guard let countBasedRetention = discussion.effectiveCountBasedRetention else { return nil }
        var totalNumberOfMessagesInDiscussionAfterThisMessage = 0
        do {
            let count = try PersistedMessageSent.countAllSentMessages(after: messageReceivedObjectID, discussion: discussion)
            totalNumberOfMessagesInDiscussionAfterThisMessage += count
        } catch { return nil }
        do {
            let count = try PersistedMessageReceived.countAllSentMessages(after: messageReceivedObjectID, discussion: discussion)
            totalNumberOfMessagesInDiscussionAfterThisMessage += count
        } catch { return nil }
        let numberOfNewMessagesBeforeSuppression = countBasedRetention - totalNumberOfMessagesInDiscussionAfterThisMessage
        return numberOfNewMessagesBeforeSuppression
    }

}


@available(iOS 13.0, *)
struct ReceivedMessageInfosView: View {
    
    @ObservedObject fileprivate var store: ReceivedMessageInfosViewStore
    
    var body: some View {
        ReceivedMessageInfosInnerView(ownedCryptoId: store.ownedCryptoId,
                                      receivedDateString: store.receivedDateString,
                                      readDateString: store.readDateString,
                                      timeBasedDeletionDateString: store.timeBasedDeletionDateString,
                                      numberOfNewMessagesBeforeSuppression: store.numberOfNewMessagesBeforeSuppression,
                                      messageObjectID: store.messageReceivedObjectID,
                                      dateStringFromDate: ReceivedMessageInfosViewStore.dateStringFromDate)
            .environment(\.managedObjectContext, ObvStack.shared.viewContext)
    }
    
}


@available(iOS 13.0, *)
struct ReceivedMessageInfosInnerView: View {
    
    let ownedCryptoId: ObvCryptoId
    let receivedDateString: String
    let readDateString: String?
    let timeBasedDeletionDateString: String?
    let numberOfNewMessagesBeforeSuppression: Int?
    var messageObjectID: NSManagedObjectID
    let dateStringFromDate: (Date?) -> String?

    var body: some View {
        List {
            MessageMetadatasSectionView(messageObjectID: messageObjectID,
                                        ownedCryptoId: ownedCryptoId,
                                        stringFromDate: dateStringFromDate)
            Section {
                if let readDateString = self.readDateString {
                    ReceivedMessageStatusView(forStatus: .read, dateAsString: readDateString)
                }
                ReceivedMessageStatusView(forStatus: .new, dateAsString: receivedDateString)
            }
            if timeBasedDeletionDateString != nil || numberOfNewMessagesBeforeSuppression != nil {
                MessageRetentionInfoSectionView(timeBasedDeletionDateString: timeBasedDeletionDateString,
                                                numberOfNewMessagesBeforeSuppression: numberOfNewMessagesBeforeSuppression)
            }
        }.listStyle(GroupedListStyle())
    }
    
}
