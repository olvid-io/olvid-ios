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
import os.log


final class ComposeMessageViewSendMessageAdapterWithDraft: ComposeMessageViewSendMessageDelegate {
    
    // API
    
    private let draft: PersistedDraft
    
    // Variables
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ComposeMessageViewSendMessageAdapterWithDraft.self))
    private var observationTokens = [NSObjectProtocol]()
    private weak var composeMessageView: ComposeMessageView?

    // Initializer
    
    init(draft: PersistedDraft) {
        self.draft = draft
        observeDraftWasSentNotifications()
    }

    
    func userWantsToSendMessageInComposeMessageView(_ composeMessageView: ComposeMessageView) {
                
        assert(self.draft.managedObjectContext == ObvStack.shared.viewContext)
        
        let log = self.log
        
        // We keep a weak reference to the compose message view so as to clear it when we receive a notification that the message has been sent.
        self.composeMessageView = composeMessageView
        
        composeMessageView.freeze()
        let textToSend = composeMessageView.textView.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let draftObjectID = self.draft.typedObjectID

        ObvStack.shared.performBackgroundTask { (context) in

            let writableDraft: PersistedDraft
            do {
                guard let _writableDraft = try PersistedDraft.get(objectID: draftObjectID, within: context) else { return }
                writableDraft = _writableDraft
            } catch {
                DispatchQueue.main.async {
                    composeMessageView.unfreeze()
                }
                return
            }
            
            guard !textToSend.isEmpty || !writableDraft.draftFyleJoins.isEmpty else {
                DispatchQueue.main.async {
                    composeMessageView.unfreeze()
                }
                return
            }
            writableDraft.setContent(with: textToSend)
            writableDraft.send()
            do {
                try context.save(logOnFailure: log)
            } catch {
                // We wait for the reception of the DraftWasSent notification to unfreeze the compose message view
                return
            }
            
        }
        
    }
    
    
    private func observeDraftWasSentNotifications() {
        let token = ObvMessengerInternalNotification.observeDraftWasSent(queue: OperationQueue.main) { (draftObjectID) in
            guard self.draft.typedObjectID == draftObjectID else { return }
            ObvStack.shared.viewContext.refresh(self.draft, mergeChanges: false)
            self.composeMessageView?.loadDataSource()
            self.composeMessageView?.unfreeze()
        }
        observationTokens.append(token)
    }
    
}
