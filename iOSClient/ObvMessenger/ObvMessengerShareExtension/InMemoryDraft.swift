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
import CoreData

final class InMemoryDraft: Draft {
    
    var body: String?
    let replyTo: PersistedMessage?
    private(set) var readOnce: Bool
    private(set) var visibilityDuration: TimeInterval?
    private(set) var existenceDuration: TimeInterval?
    private var inMemoryDraftFyleJoins: [InMemoryDraftFyleJoin]
    private var persistedDiscussion: PersistedDiscussion?
    private let localQueue = DispatchQueue(label: "InMemoryDraft Queue")
    private var persistedDiscussionObjectID: NSManagedObjectID?
    
    init() {
        self.body = nil
        self.replyTo = nil
        // The expiration settings are set when the discussion is chosen
        self.readOnce = false
        self.visibilityDuration = nil
        self.existenceDuration = nil
        self.inMemoryDraftFyleJoins = [InMemoryDraftFyleJoin]()
    }

    func reset() {
        inMemoryDraftFyleJoins.removeAll()
    }

    var draftFyleJoins: [DraftFyleJoin] {
        return self.inMemoryDraftFyleJoins
    }
    
    func removeDraftFyleJoin(atIndex index: Int) {
        guard index < inMemoryDraftFyleJoins.count else { return }
        inMemoryDraftFyleJoins.remove(at: index)
    }
    
    func appendURL(_ url: URL) {
        self.appendText(url.absoluteString)
    }
    
    func appendText(_ text: String) {
        localQueue.async { [weak self] in
            guard let _self = self else { return }
            if _self.body == nil {
                _self.body = text
                
            } else {
                _self.body?.append(" \(text)")
            }
        }
    }
    
    func appendFyle(_ fyleObjectID: NSManagedObjectID, fileName: String, uti: String) {
        ObvStack.shared.viewContext.performAndWait {
            guard let fyle = try? Fyle.get(objectID: fyleObjectID, within: ObvStack.shared.viewContext) else { return }
            let inMemoryDraftFyleJoin = InMemoryDraftFyleJoin(fyle: fyle, fileName: fileName, uti: uti, index: inMemoryDraftFyleJoins.count)
            localQueue.sync { [weak self] in
                self?.inMemoryDraftFyleJoins.append(inMemoryDraftFyleJoin)
            }
        }
    }

    func setDiscussion(to discussion: PersistedDiscussion) {
        localQueue.async { [weak self] in
            self?.persistedDiscussion = discussion
            self?.persistedDiscussionObjectID = discussion.objectID
            self?.readOnce = discussion.sharedConfiguration.readOnce
            self?.visibilityDuration = discussion.sharedConfiguration.visibilityDuration
            self?.existenceDuration = discussion.sharedConfiguration.existenceDuration
        }
    }
    
    var discussion: PersistedDiscussion {
        var _discussion: PersistedDiscussion!
        localQueue.sync {
            _discussion = self.persistedDiscussion
        }
        return _discussion
    }
    
    var isReady: Bool {
        var res = false
        localQueue.sync { [weak self] in
            res = self?.persistedDiscussionObjectID != nil
        }
        return res
    }
    
    /// Expected to be executed on the context thread passed as a parameter
    func changeContext(to context: NSManagedObjectContext) {
        guard let persistedDiscussionObjectID = self.persistedDiscussionObjectID else { assertionFailure(); return }
        guard let _discussion = try? PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: context) else { assertionFailure(); return }
        self.persistedDiscussion = _discussion
        _ = self.inMemoryDraftFyleJoins.map { $0.changeContext(to: context) }
    }
}
