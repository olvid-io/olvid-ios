/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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


public enum ObvPollType: String, Sendable {
    case string = "string"
}

public struct ObvPollCandidate: Sendable {
    public let text: String
    public let uuid: UUID
    
    public init(text: String, uuid: UUID) {
        self.text = text
        self.uuid = uuid
    }
}

public struct ObvPoll: Sendable {
    
    public let question: String
    public let type: ObvPollType
    public let expiration: Date?
    public let multipleChoice: Bool
    public let candidates: [ObvPollCandidate]
    
    public init(question: String,
                type: ObvPollType,
                expiration: Date?,
                multipleChoice: Bool,
                candidates: [ObvPollCandidate]) {
        self.question = question
        self.type = type
        self.expiration = expiration
        self.multipleChoice = multipleChoice
        self.candidates = candidates
    }
}


extension UUID {
    
    /// A poll can be configured to allow users to vote "None", typically when they find no suitable candidate. The "None" candidate is always identitified by this `UUID`.
    public static let uuidOfPollCandidateNone = UUID.init(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
    
}
