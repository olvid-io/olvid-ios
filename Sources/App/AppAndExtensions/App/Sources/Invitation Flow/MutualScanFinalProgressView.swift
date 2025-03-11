/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

import SwiftUI
import ObvTypes
import ObvEngine
import ObvUICoreData
import ObvUI


/// View shown to confirm that the contact will be added as soon as network is back. When both devices are in normal condition, this view shows a spinner and is automatically dismissed as soon as the contact's one2one discussion is added.
struct MutualScanFinalProgressView: View {
    
    @ObservedObject var model: MutualScanFinalProgressViewModel
    
    var body: some View {
        
        if model.showSpinner {
            
            ProgressView()
                .task {
                    await model.startTrustEstablishmentWithMutualScanProtocol()
                }

        } else {
            
            VStack {
                
                ObvCardView {
                    VStack(alignment: .leading) {
                        if let contact = model.contactIdentity, let discussion = model.discussionWithContact {
                            HStack {
                                IdentityCardContentView(model: SingleContactIdentity(persistedContact: contact, observeChangesMadeToContact: false))
                                Spacer()
                            }
                            Text("\(contact.customOrShortDisplayName)_WAS_ADDED_TO_YOUR_CONTACTS")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            OlvidButton(style: .blue, title: Text("DISCUSS_WITH_\(contact.customOrShortDisplayName)"), systemIcon: .bubble, action: { model.userWantsToNavigateToDiscussionWithContact(discussion: discussion) })
                                .padding(.top, 4)
                        } else {
                            HStack {
                                IdentityCardContentView(model: SingleIdentity(mutualScanUrl: model.mutualScanUrl))
                                Spacer()
                            }
                            Text("\(model.mutualScanUrl.fullDisplayName)_WILL_SOON_BE_ADDED_TO_YOUR_CONTACTS_WHEN_MUTUAL_SCAN_PROTOCOL_IS_OVER")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            HStack {
                                Spacer()
                                Button("Ok", action: model.userWantsToNavigateToLatestDiscussions)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding()
             
                Spacer()
                
            }

        }
        
    }

}


// MARK: - Model of the MutualScanFinalProgressView

final class MutualScanFinalProgressViewModel: ObservableObject {
    
    let ownedCryptoId: ObvCryptoId
    let mutualScanUrl: ObvMutualScanUrl
    @Published private(set) var contactIdentity: PersistedObvContactIdentity? /// Only set if the contact is already known, or when the contact become available
    @Published private(set) var discussionWithContact: PersistedOneToOneDiscussion?
    @Published private(set) var showSpinner = true
    private var observationTokens = [NSObjectProtocol]()
    private let generator = UINotificationFeedbackGenerator()

    init(ownedCryptoId: ObvCryptoId, mutualScanUrl: ObvMutualScanUrl, contactIdentity: PersistedObvContactIdentity?) {
        self.ownedCryptoId = ownedCryptoId
        self.mutualScanUrl = mutualScanUrl
        self.contactIdentity = contactIdentity
        observeNotifications()
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    private func observeNotifications() {
        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observePersistedContactWasInserted { [weak self] contactID, ownedCryptoId, contactCryptoId, _ in
                guard let self else { return }
                guard ownedCryptoId == self.ownedCryptoId, contactCryptoId == mutualScanUrl.cryptoId else { return }
                ObvStack.shared.viewContext.perform { [weak self] in
                    guard let self else { return }
                    guard let persistedContact = try? PersistedObvContactIdentity.getManagedObject(withPermanentID: contactID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
                    self.contactIdentity = persistedContact
                }
            },
            ObvMessengerCoreDataNotification.observePersistedDiscussionWasInsertedOrReactivated { [weak self] ownedCryptoId, discussionIdentifier in
                guard let self else { return }
                guard ownedCryptoId == self.ownedCryptoId else { return }
                ObvStack.shared.viewContext.perform { [weak self] in
                    guard let self else { return }
                    guard let oneToOneDiscussion = try? PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: ownedCryptoId, discussionId: discussionIdentifier, within: ObvStack.shared.viewContext) as? PersistedOneToOneDiscussion else { return }
                    guard oneToOneDiscussion.contactIdentity?.cryptoId == mutualScanUrl.cryptoId else { return }
                    if self.showSpinner {
                        // If we are still showing the spinner, the protocol was fast enough to simply dismiss this view and navigate to the single discussion
                        generator.notificationOccurred(.success)
                        let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: ownedCryptoId, objectPermanentID: oneToOneDiscussion.discussionPermanentID)
                        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                            .postOnDispatchQueue()
                    } else {
                        // If we are no longer showing the spinner, it means that the protocol required a long time to finish. We update this view.
                        self.discussionWithContact = oneToOneDiscussion
                    }
                }

            },
        ])
    }

    /// Called as soon as the view appears
    @MainActor
    fileprivate func startTrustEstablishmentWithMutualScanProtocol() async {
        
        // We consider that the fact that the user scanned the mutual scan URL of the other contact means she wants to enter in contact.
        // We don't ask for confirmation an start the protocol right away.
                
        ObvMessengerInternalNotification.userWantsToStartTrustEstablishmentWithMutualScanProtocol(ownedCryptoId: ownedCryptoId, mutualScanUrl: mutualScanUrl)
            .postOnDispatchQueue()
        
        // In rare situations, the contact might already exist. This is the case when performing a mutual scan to add a new "trust origin".
        // If this is the case, we immediately navigate to the discussion we have with the contact.
        
        if let oneToOneDiscussion = try? PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: self.ownedCryptoId, discussionId: .oneToOne(id: .contactCryptoId(contactCryptoId: mutualScanUrl.cryptoId)), within: ObvStack.shared.viewContext),
           oneToOneDiscussion.status == .active {
            generator.notificationOccurred(.success)
            let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: ownedCryptoId, objectPermanentID: oneToOneDiscussion.discussionPermanentID)
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
            return
        }
        
        // We give some time to the protocol to execute. When network conditions are good, this is enough for the protocol to finish. In that case,
        // this view will simply be dismissed and we navigate to the new one2one discussion.
        // If the protocol takes longer (e.g., when there is no network), this view will be updated.
        
        try? await Task.sleep(seconds: 3)
        
        DispatchQueue.main.async { [weak self] in
            self?.showSpinner = false
        }

    }
    
    
    fileprivate func userWantsToNavigateToDiscussionWithContact(discussion: PersistedOneToOneDiscussion) {
        let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: ownedCryptoId, objectPermanentID: discussion.discussionPermanentID)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }
    
    
    fileprivate func userWantsToNavigateToLatestDiscussions() {
        let deepLink = ObvDeepLink.latestDiscussions(ownedCryptoId: ownedCryptoId)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }
    
}
