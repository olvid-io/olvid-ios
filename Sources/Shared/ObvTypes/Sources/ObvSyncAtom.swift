/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvEncoder
import ObvCrypto


public enum ObvSyncAtom: ObvCodable, Equatable, CustomDebugStringConvertible {

    case contactNickname(contactCryptoId: ObvCryptoId, contactNickname: String?)
    case groupV1Nickname(groupOwner: ObvCryptoId, groupUid: UID, groupNickname: String?)
    case groupV2Nickname(groupIdentifier: Data, groupNickname: String?)
    case contactPersonalNote(contactCryptoId: ObvCryptoId, note: String?)
    case groupV1PersonalNote(groupOwner: ObvCryptoId, groupUid: UID, note: String?)
    case groupV2PersonalNote(groupIdentifier: Data, note: String?)
    case ownProfileNickname(nickname: String?)
    case contactCustomHue(contactCryptoId: ObvCryptoId, customHue: Int?) // Not implemented under iOS
    case contactSendReadReceipt(contactCryptoId: ObvCryptoId, doSendReadReceipt: Bool?)
    case groupV1ReadReceipt(groupOwner: ObvCryptoId, groupUid: UID, doSendReadReceipt: Bool?)
    case groupV2ReadReceipt(groupIdentifier: Data, doSendReadReceipt: Bool?)
    case pinnedDiscussions(discussionIdentifiers: [DiscussionIdentifier], ordered: Bool)
    case trustContactDetails(contactCryptoId: ObvCryptoId, serializedIdentityDetailsElements: Data)
    case trustGroupV1Details(groupOwner: ObvCryptoId, groupUid: UID, serializedGroupDetailsElements: Data)
    case trustGroupV2Details(groupIdentifier: Data, version: Int)
    case settingDefaultSendReadReceipts(sendReadReceipt: Bool)
    case settingAutoJoinGroups(category: AutoJoinGroupsCategory)

    public enum AutoJoinGroupsCategory: String, ObvCodable {
        case everyone = "everyone"
        case contacts = "contacts"
        case nobody = "nobody"
        public func obvEncode() -> ObvEncoded {
            return self.rawValue.obvEncode()
        }
        public init?(_ obvEncoded: ObvEncoded) {
            guard let rawValue: String = try? obvEncoded.obvDecode(),
                  let value = AutoJoinGroupsCategory(rawValue: rawValue) else { assertionFailure(); return nil }
            self = value
        }
    }
    
    /// This enum is used in certain `ObvSyncAtom` (well, for now, only in the pinnedDiscussions atom)
    public enum DiscussionIdentifier: Equatable, Hashable, ObvCodable, Sendable {

        case oneToOne(contactCryptoId: ObvCryptoId)
        case groupV1(groupIdentifier: GroupV1Identifier)
        case groupV2(groupIdentifier: GroupV2Identifier)
        
        private enum DiscussionIdentifierRawValue: Int, CaseIterable, ObvCodable {
            
            case oneToOne = 0
            case groupV1 = 1
            case groupV2 = 2
            
            init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
                guard let rawValue: Int = try? obvEncoded.obvDecode() else { assertionFailure(); return nil }
                guard let value = DiscussionIdentifierRawValue(rawValue: rawValue) else { assertionFailure(); return nil }
                self = value
            }
            
            func obvEncode() -> ObvEncoder.ObvEncoded {
                self.rawValue.obvEncode()
            }

        }
        
        public func obvEncode() -> ObvEncoded {
            switch self {
            case .oneToOne(contactCryptoId: let contactCryptoId):
                return [DiscussionIdentifierRawValue.oneToOne, contactCryptoId].obvEncode()
            case .groupV1(groupIdentifier: let groupIdentifier):
                return [DiscussionIdentifierRawValue.groupV1, groupIdentifier.groupOwner, groupIdentifier.groupUid].obvEncode()
            case .groupV2(groupIdentifier: let groupIdentifier):
                return [DiscussionIdentifierRawValue.groupV2, groupIdentifier].obvEncode()
            }
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let listOfEncoded = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
            guard let encodedRawValue = listOfEncoded.first else { assertionFailure(); return nil }
            let remainingEncodedElements = [ObvEncoded](listOfEncoded.dropFirst())
            guard let discussionIdentifierRawValue = DiscussionIdentifierRawValue(encodedRawValue) else { assertionFailure(); return nil }
            do {
                switch discussionIdentifierRawValue {
                case .oneToOne:
                    guard remainingEncodedElements.count == 1 else { assertionFailure(); return nil }
                    let contactCryptoId: ObvCryptoId = try remainingEncodedElements.obvDecode()
                    self = .oneToOne(contactCryptoId: contactCryptoId)
                case .groupV1:
                    guard remainingEncodedElements.count == 2 else { assertionFailure(); return nil }
                    let (groupOwner, groupUid): (ObvCryptoId, UID) = try remainingEncodedElements.obvDecode()
                    self = .groupV1(groupIdentifier: GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner))
                case .groupV2:
                    guard remainingEncodedElements.count == 1 else { assertionFailure(); return nil }
                    let groupIdentifier: Data = try remainingEncodedElements.obvDecode()
                    self = .groupV2(groupIdentifier: groupIdentifier)
                }
            } catch {
                assertionFailure()
                return nil
            }
        }
        
    }
    
    public func obvEncode() -> ObvEncoded {
        switch self {
        case .contactNickname(let contactCryptoId, let contactNickname):
            if let contactNickname {
                return [ObvSyncAtomRawValue.contactNickname, contactCryptoId, contactNickname].obvEncode()
            } else {
                return [ObvSyncAtomRawValue.contactNickname, contactCryptoId].obvEncode()
            }
        case .groupV1Nickname(let groupOwner, let groupUid, let groupNickname):
            if let groupNickname {
                return [ObvSyncAtomRawValue.groupV1Nickname, groupOwner, groupUid, groupNickname].obvEncode()
            } else {
                return [ObvSyncAtomRawValue.groupV1Nickname, groupOwner, groupUid].obvEncode()
            }
        case .groupV2Nickname(let groupIdentifier, let groupNickname):
            if let groupNickname {
                return [ObvSyncAtomRawValue.groupV2Nickname, groupIdentifier, groupNickname].obvEncode()
            } else {
                return [ObvSyncAtomRawValue.groupV2Nickname, groupIdentifier].obvEncode()
            }
        case .contactPersonalNote(let contactCryptoId, let note):
            if let note {
                return [ObvSyncAtomRawValue.contactPersonalNote, contactCryptoId, note].obvEncode()
            } else {
                return [ObvSyncAtomRawValue.contactPersonalNote, contactCryptoId].obvEncode()
            }
        case .groupV1PersonalNote(let groupOwner, let groupUid, let note):
            if let note {
                return [ObvSyncAtomRawValue.groupV1PersonalNote, groupOwner, groupUid, note].obvEncode()
            } else {
                return [ObvSyncAtomRawValue.groupV1PersonalNote, groupOwner, groupUid].obvEncode()
            }
        case .groupV2PersonalNote(let groupIdentifier, let note):
            if let note {
                return [ObvSyncAtomRawValue.groupV2PersonalNote, groupIdentifier, note].obvEncode()
            } else {
                return [ObvSyncAtomRawValue.groupV2PersonalNote, groupIdentifier].obvEncode()
            }
        case .ownProfileNickname(let nickname):
            if let nickname, !nickname.isEmpty {
                return [ObvSyncAtomRawValue.ownProfileNickname, nickname].obvEncode()
            } else {
                return [ObvSyncAtomRawValue.ownProfileNickname].obvEncode()
            }
        case .contactCustomHue(let contactCryptoId, let customHue):
            if let customHue {
                return [ObvSyncAtomRawValue.contactCustomHue, contactCryptoId, customHue].obvEncode()
            } else {
                return [ObvSyncAtomRawValue.contactCustomHue, contactCryptoId].obvEncode()
            }
        case .contactSendReadReceipt(let contactCryptoId, let doSendReadReceipt):
            if let doSendReadReceipt {
                return [ObvSyncAtomRawValue.contactSendReadReceipt, contactCryptoId, doSendReadReceipt].obvEncode()
            } else {
                return [ObvSyncAtomRawValue.contactSendReadReceipt, contactCryptoId].obvEncode()
            }
        case .groupV1ReadReceipt(let groupOwner, let groupUid, let doSendReadReceipt):
            if let doSendReadReceipt {
                return [ObvSyncAtomRawValue.groupV1ReadReceipt, groupOwner, groupUid, doSendReadReceipt].obvEncode()
            } else {
                return [ObvSyncAtomRawValue.groupV1ReadReceipt, groupOwner, groupUid].obvEncode()
            }
        case .groupV2ReadReceipt(let groupIdentifier, let doSendReadReceipt):
            if let doSendReadReceipt {
                return [ObvSyncAtomRawValue.groupV2ReadReceipt, groupIdentifier, doSendReadReceipt].obvEncode()
            } else {
                return [ObvSyncAtomRawValue.groupV2ReadReceipt, groupIdentifier].obvEncode()
            }
        case .pinnedDiscussions(let discussionIdentifiers, let ordered):
            let encodedDiscussionIdentifiers: [ObvEncoded] = discussionIdentifiers.map { $0.obvEncode() }
            return [ObvSyncAtomRawValue.pinnedDiscussions.obvEncode(), encodedDiscussionIdentifiers.obvEncode(), ordered.obvEncode()].obvEncode()
        case .trustContactDetails(contactCryptoId: let contactCryptoId, serializedIdentityDetailsElements: let serializedIdentityDetailsElements):
            return [ObvSyncAtomRawValue.trustContactDetails, contactCryptoId, serializedIdentityDetailsElements].obvEncode()
        case .trustGroupV1Details(let groupOwner, let groupUid, let serializedGroupDetailsElements):
            return [ObvSyncAtomRawValue.trustGroupV1Details, groupOwner, groupUid, serializedGroupDetailsElements].obvEncode()
        case .trustGroupV2Details(let groupIdentifier, let version):
            return [ObvSyncAtomRawValue.trustGroupV2Details, groupIdentifier, version].obvEncode()
        case .settingDefaultSendReadReceipts(let sendReadReceipt):
            return [ObvSyncAtomRawValue.settingDefaultSendReadReceipts, sendReadReceipt].obvEncode()
        case .settingAutoJoinGroups(let category):
            return [ObvSyncAtomRawValue.settingAutoJoinGroups, category].obvEncode()
        }
    }
    
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
        guard let encodedRawValue = listOfEncoded.first else { assertionFailure(); return nil }
        let remainingEncodedElements = [ObvEncoded](listOfEncoded.dropFirst())
        guard let syncAtomRawValue = ObvSyncAtomRawValue(encodedRawValue) else { assertionFailure(); return nil}
        do {
            switch syncAtomRawValue {
            case .contactNickname:
                switch remainingEncodedElements.count {
                case 1:
                    let contactCryptoId: ObvCryptoId = try remainingEncodedElements.obvDecode()
                    self = .contactNickname(contactCryptoId: contactCryptoId, contactNickname: nil)
                case 2:
                    let (contactCryptoId, contactNickname): (ObvCryptoId, String) = try remainingEncodedElements.obvDecode()
                    self = .contactNickname(contactCryptoId: contactCryptoId, contactNickname: contactNickname)
                default:
                    assertionFailure()
                    return nil
                }
            case .groupV1Nickname:
                switch remainingEncodedElements.count {
                case 2:
                    let (groupOwner, groupUid): (ObvCryptoId, UID) = try remainingEncodedElements.obvDecode()
                    self = .groupV1Nickname(groupOwner: groupOwner, groupUid: groupUid, groupNickname: nil)
                case 3:
                    let (groupOwner, groupUid, groupNickname): (ObvCryptoId, UID, String) = try remainingEncodedElements.obvDecode()
                    self = .groupV1Nickname(groupOwner: groupOwner, groupUid: groupUid, groupNickname: groupNickname)
                default:
                    assertionFailure()
                    return nil
                }
            case .groupV2Nickname:
                switch remainingEncodedElements.count {
                case 1:
                    let groupIdentifier: Data = try remainingEncodedElements.obvDecode()
                    self = .groupV2Nickname(groupIdentifier: groupIdentifier, groupNickname: nil)
                case 2:
                    let (groupIdentifier, groupNickname): (Data, String) = try remainingEncodedElements.obvDecode()
                    self = .groupV2Nickname(groupIdentifier: groupIdentifier, groupNickname: groupNickname)
                default:
                    assertionFailure()
                    return nil
                }
            case .contactPersonalNote:
                switch remainingEncodedElements.count {
                case 1:
                    let contactCryptoId: ObvCryptoId = try remainingEncodedElements.obvDecode()
                    self = .contactPersonalNote(contactCryptoId: contactCryptoId, note: nil)
                case 2:
                    let (contactCryptoId, note): (ObvCryptoId, String?) = try remainingEncodedElements.obvDecode()
                    self = .contactPersonalNote(contactCryptoId: contactCryptoId, note: note)
                default:
                    assertionFailure()
                    return nil
                }
            case .groupV1PersonalNote:
                switch remainingEncodedElements.count {
                case 2:
                    let (groupOwner, groupUid): (ObvCryptoId, UID) = try remainingEncodedElements.obvDecode()
                    self = .groupV1PersonalNote(groupOwner: groupOwner, groupUid: groupUid, note: nil)
                case 3:
                    let (groupOwner, groupUid, note): (ObvCryptoId, UID, String) = try remainingEncodedElements.obvDecode()
                    self = .groupV1PersonalNote(groupOwner: groupOwner, groupUid: groupUid, note: note)
                default:
                    assertionFailure()
                    return nil
                }
            case .groupV2PersonalNote:
                switch remainingEncodedElements.count {
                case 1:
                    let groupIdentifier: Data = try remainingEncodedElements.obvDecode()
                    self = .groupV2PersonalNote(groupIdentifier: groupIdentifier, note: nil)
                case 2:
                    let (groupIdentifier, note): (Data, String) = try remainingEncodedElements.obvDecode()
                    self = .groupV2PersonalNote(groupIdentifier: groupIdentifier, note: note)
                default:
                    assertionFailure()
                    return nil
                }
            case .ownProfileNickname:
                switch remainingEncodedElements.count {
                case 0:
                    self = .ownProfileNickname(nickname: nil)
                case 1:
                    let nickname: String = try remainingEncodedElements.obvDecode()
                    self = .ownProfileNickname(nickname: nickname)
                default:
                    assertionFailure()
                    return nil
                }
            case .contactCustomHue:
                switch remainingEncodedElements.count {
                case 1:
                    let contactCryptoId: ObvCryptoId = try remainingEncodedElements.obvDecode()
                    self = .contactCustomHue(contactCryptoId: contactCryptoId, customHue: nil)
                case 2:
                    let (contactCryptoId, customHue): (ObvCryptoId, Int) = try remainingEncodedElements.obvDecode()
                    self = .contactCustomHue(contactCryptoId: contactCryptoId, customHue: customHue)
                default:
                    assertionFailure()
                    return nil
                }
            case .contactSendReadReceipt:
                switch remainingEncodedElements.count {
                case 1:
                    let contactCryptoId: ObvCryptoId = try remainingEncodedElements.obvDecode()
                    self = .contactSendReadReceipt(contactCryptoId: contactCryptoId, doSendReadReceipt: nil)
                case 2:
                    let (contactCryptoId, doSendReadReceipt): (ObvCryptoId, Bool) = try remainingEncodedElements.obvDecode()
                    self = .contactSendReadReceipt(contactCryptoId: contactCryptoId, doSendReadReceipt: doSendReadReceipt)
                default:
                    assertionFailure()
                    return nil
                }
            case .groupV1ReadReceipt:
                switch remainingEncodedElements.count {
                case 2:
                    let (groupOwner, groupUid): (ObvCryptoId, UID) = try remainingEncodedElements.obvDecode()
                    self = .groupV1ReadReceipt(groupOwner: groupOwner, groupUid: groupUid, doSendReadReceipt: nil)
                case 3:
                    let (groupOwner, groupUid, doSendReadReceipt): (ObvCryptoId, UID, Bool) = try remainingEncodedElements.obvDecode()
                    self = .groupV1ReadReceipt(groupOwner: groupOwner, groupUid: groupUid, doSendReadReceipt: doSendReadReceipt)
                default:
                    assertionFailure()
                    return nil
                }
            case .groupV2ReadReceipt:
                switch remainingEncodedElements.count {
                case 1:
                    let groupIdentifier: Data = try remainingEncodedElements.obvDecode()
                    self = .groupV2ReadReceipt(groupIdentifier: groupIdentifier, doSendReadReceipt: nil)
                case 2:
                    let (groupIdentifier, doSendReadReceipt): (Data, Bool) = try remainingEncodedElements.obvDecode()
                    self = .groupV2ReadReceipt(groupIdentifier: groupIdentifier, doSendReadReceipt: doSendReadReceipt)
                default:
                    assertionFailure()
                    return nil
                }
            case .pinnedDiscussions:
                switch remainingEncodedElements.count {
                case 2:
                    guard let encodedDiscussionIdentifiers = [ObvEncoded](remainingEncodedElements[0]) else { assertionFailure(); return nil }
                    let discussionIdentifiers = encodedDiscussionIdentifiers.compactMap { DiscussionIdentifier($0) }
                    guard let ordered = Bool(remainingEncodedElements[1]) else { assertionFailure(); return nil }
                    self = .pinnedDiscussions(discussionIdentifiers: discussionIdentifiers, ordered: ordered)
                default:
                    assertionFailure()
                    return nil
                }
            case .trustContactDetails:
                switch remainingEncodedElements.count {
                case 2:
                    let (contactCryptoId, serializedIdentityDetailsElements): (ObvCryptoId, Data) = try remainingEncodedElements.obvDecode()
                    self = .trustContactDetails(contactCryptoId: contactCryptoId, serializedIdentityDetailsElements: serializedIdentityDetailsElements)
                default:
                    assertionFailure()
                    return nil
                }
            case .trustGroupV1Details:
                switch remainingEncodedElements.count {
                case 3:
                    let (groupOwner, groupUid, serializedGroupDetailsElements): (ObvCryptoId, UID, Data) = try remainingEncodedElements.obvDecode()
                    self = .trustGroupV1Details(groupOwner: groupOwner, groupUid: groupUid, serializedGroupDetailsElements: serializedGroupDetailsElements)
                default:
                    assertionFailure()
                    return nil
                }
            case .trustGroupV2Details:
                switch remainingEncodedElements.count {
                case 2:
                    let (groupIdentifier, version): (Data, Int) = try remainingEncodedElements.obvDecode()
                    self = .trustGroupV2Details(groupIdentifier: groupIdentifier, version: version)
                default:
                    assertionFailure()
                    return nil
                }
            case .settingDefaultSendReadReceipts:
                switch remainingEncodedElements.count {
                case 1:
                    let sendReadReceipt: Bool = try remainingEncodedElements.obvDecode()
                    self = .settingDefaultSendReadReceipts(sendReadReceipt: sendReadReceipt)
                default:
                    assertionFailure()
                    return nil
                }
            case .settingAutoJoinGroups:
                switch remainingEncodedElements.count {
                case 1:
                    let category: AutoJoinGroupsCategory = try remainingEncodedElements.obvDecode()
                    self = .settingAutoJoinGroups(category: category)
                default:
                    assertionFailure()
                    return nil
                }
            }
        } catch {
            assertionFailure()
            return nil
        }
    }
    
    
    public enum SyncAtomRecipient {
        case app
        case identityManager
        case notImplementedOniOS
    }
    
    public var recipient: SyncAtomRecipient {
        switch self {
        case .contactNickname,
                .groupV1Nickname,
                .groupV2Nickname,
                .contactPersonalNote,
                .groupV1PersonalNote,
                .groupV2PersonalNote,
                .ownProfileNickname,
                .contactSendReadReceipt,
                .groupV1ReadReceipt,
                .groupV2ReadReceipt,
                .settingDefaultSendReadReceipts,
                .settingAutoJoinGroups,
                .pinnedDiscussions:
            return .app
        case .trustContactDetails,
                .trustGroupV1Details,
                .trustGroupV2Details:
            return .identityManager
        case .contactCustomHue:
            return .notImplementedOniOS
        }
    }
    
    public var debugDescription: String {
        let prefix = "ObvSyncAtom"
        let suffix: String
        switch self {
        case .contactNickname:
            suffix = "contactNickname"
        case .groupV1Nickname:
            suffix = "groupV1Nickname"
        case .groupV2Nickname:
            suffix = "groupV2Nickname"
        case .contactPersonalNote:
            suffix = "contactPersonalNote"
        case .groupV1PersonalNote:
            suffix = "groupV1PersonalNote"
        case .groupV2PersonalNote:
            suffix = "groupV2PersonalNote"
        case .ownProfileNickname:
            suffix = "ownProfileNickname"
        case .contactCustomHue:
            suffix = "contactCustomHue"
        case .contactSendReadReceipt:
            suffix = "contactSendReadReceipt"
        case .groupV1ReadReceipt:
            suffix = "groupV1ReadReceipt"
        case .groupV2ReadReceipt:
            suffix = "groupV2ReadReceipt"
        case .trustContactDetails:
            suffix = "trustContactDetails"
        case .trustGroupV1Details:
            suffix = "trustGroupV1Details"
        case .trustGroupV2Details:
            suffix = "trustGroupV2Details"
        case .pinnedDiscussions:
            suffix = "pinnedDiscussions"
        case .settingDefaultSendReadReceipts:
            suffix = "settingDefaultSendReadReceipts"
        case .settingAutoJoinGroups:
            suffix = "settingAutoJoinGroups"
        }
        return [prefix, suffix].joined(separator: ".")
    }

}



private enum ObvSyncAtomRawValue: Int, CaseIterable, ObvCodable {
    
    case contactNickname = 0
    case groupV1Nickname = 1
    case groupV2Nickname = 2
    case contactPersonalNote = 3
    case groupV1PersonalNote = 4
    case groupV2PersonalNote = 5
    case ownProfileNickname = 6
    case contactCustomHue = 7 // Only available under Android
    case contactSendReadReceipt = 8
    case groupV1ReadReceipt = 9
    case groupV2ReadReceipt = 10
    case pinnedDiscussions = 11
    case trustContactDetails = 12
    case trustGroupV1Details = 13
    case trustGroupV2Details = 14
    case settingDefaultSendReadReceipts = 15
    case settingAutoJoinGroups = 16

    init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
        guard let rawValue: Int = try? obvEncoded.obvDecode() else { assertionFailure(); return nil }
        guard let value = ObvSyncAtomRawValue(rawValue: rawValue) else { assertionFailure(); return nil }
        self = value
    }
    
    func obvEncode() -> ObvEncoder.ObvEncoded {
        self.rawValue.obvEncode()
    }

}
