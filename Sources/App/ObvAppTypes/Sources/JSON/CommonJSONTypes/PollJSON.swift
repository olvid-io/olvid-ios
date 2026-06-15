/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


public struct PollJSON: Codable, Equatable, Hashable, Sendable {

    public enum PollAnswerType: String, Sendable {
        case string = "string"
    }
    
    public let type: PollJSON.PollAnswerType
    public let question: String
    public let multipleChoice: Bool
    public let expiration: TimeInterval?
    public let candidates: [PollCandidateJSON]
    
    var expirationDate: Date? {
        guard let expiration else { return nil }
        
        return Date(timeIntervalSince1970: expiration)
    }
    
    enum CodingKeys: String, CodingKey {
        case type = "t"
        case question = "q"
        case candidates = "c"
        case multipleChoice = "m"
        case expiration = "e"
    }
    
    public init(type: PollJSON.PollAnswerType,
                question: String,
                candidates: [PollCandidateJSON],
                multipleChoice: Bool,
                expiration: TimeInterval?) {
        self.type = type
        self.question = question
        self.candidates = candidates
        self.multipleChoice = multipleChoice
        self.expiration = expiration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let typeRawValue = try container.decode(String.self, forKey: .type)
        self.type = PollJSON.PollAnswerType(rawValue: typeRawValue) ?? .string
                
        self.question = try container.decode(String.self, forKey: .question)
        self.multipleChoice = try container.decode(Bool.self, forKey: .multipleChoice)
        self.candidates = try container.decode( [PollCandidateJSON].self, forKey: .candidates)
        if let expiration = try container.decodeIfPresent(Int.self, forKey: .expiration) {
            self.expiration = TimeInterval(milliseconds: expiration)
        } else {
            self.expiration = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.type.rawValue, forKey: .type)
        
        try container.encode(self.question, forKey: .question)
        try container.encode(self.multipleChoice, forKey: .multipleChoice)
        try container.encode(self.question, forKey: .question)
        try container.encode(self.candidates, forKey: .candidates)
        
        if let expiration = expiration?.toMilliseconds {
            try container.encodeIfPresent(expiration, forKey: .expiration)
        }
    }

    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return data
    }

    static func jsonDecode(_ data: Data) throws -> PollJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(PollJSON.self, from: data)
    }
    
    public func toObvPoll() -> ObvPoll {
        
        let type = ObvPollType(rawValue: self.type.rawValue) ?? .string
        
        return ObvPoll(question: self.question,
                       type: type,
                       expiration: self.expirationDate,
                       multipleChoice: self.multipleChoice,
                       candidates: candidates.compactMap { ObvPollCandidate(text: $0.text, uuid: $0.uuid) })
    }
}
