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
import ObvUICoreData
import ObvUIObvCircledInitials


@MainActor
protocol HorizontalUsersViewModelProtocol: ObservableObject {
    associatedtype UserModel: SingleUserViewForHorizontalUsersLayoutModelProtocol
    @MainActor var selectedUsersOrdered: [UserModel] { get }
}


protocol HorizontalUsersViewConfigurationProtocol {
    var canEditUsers: Bool { get }
    var textOnEmptySetOfUsers: String { get }
}


/// Displays an horizontal list of selected users during a group creation.
struct HorizontalUsersView<Model: HorizontalUsersViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let configuration: HorizontalUsersViewConfigurationProtocol
    
    let actions: SingleUserViewForHorizontalUsersLayoutActionsProtocol?
    
    @Environment(\.sizeCategory) var sizeCategory
    
    /// Magic numbers that shall be replaced by a custom SwiftUI Layout (only available for iOS 16.0+).
    /// See https://developer.apple.com/documentation/swiftui/layout and
    /// https://developer.apple.com/wwdc22/10056?time=609
    private var height: CGFloat {
        switch sizeCategory {
        case .extraSmall:
            return 109
        case .small:
            return 113
        case .medium:
            return 115
        case .large:
            return 118
        case .extraLarge:
            return 123
        case .extraExtraLarge:
            return 128
        case .extraExtraExtraLarge:
            return 133
        case .accessibilityMedium:
            return 144
        case .accessibilityLarge:
            return 157
        case .accessibilityExtraLarge:
            return 174
        case .accessibilityExtraExtraLarge:
            return 190
        case .accessibilityExtraExtraExtraLarge:
            return 209
        @unknown default:
            return 118
        }
    }
    
    var body: some View {
        
        ZStack {
            
            Text(configuration.textOnEmptySetOfUsers)
                .padding(16)
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(model.selectedUsersOrdered.isEmpty ? 1.0 : 0.0)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20.0) {
                    ForEach(model.selectedUsersOrdered, id: \.cryptoId) { user in
                        SingleUserViewForHorizontalContactsLayout(model: user, canEdit: configuration.canEditUsers, actions: actions)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .opacity(model.selectedUsersOrdered.isEmpty ? 0.0 : 1.0)
            
        }
        .frame(height: height)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12.0))
        .transition(.opacity)
        .animation(.easeInOut, value: UUID())
        
    }
}

struct HorizontalContactsView_Previews: PreviewProvider {
    
    private final class Users: HorizontalUsersViewModelProtocol {
        typealias ContactModel = User

        var selectedUsersOrdered: [User]
        
        func shouldDeleteContact(user: User) {}
        
        init(selectedUsersOrdered: [User]) {
            self.selectedUsersOrdered = selectedUsersOrdered
        }
    }
    
    private final class User: SingleUserViewForHorizontalUsersLayoutModelProtocol {
        
        var cryptoId: ObvCryptoId
        
        let firstName: String?
        let lastName: String?
        let circledInitialsConfiguration: CircledInitialsConfiguration
        
        init(cryptoId: ObvCryptoId, firstName: String?, lastName: String? = nil, circledInitialsConfiguration: CircledInitialsConfiguration) {
            self.cryptoId = cryptoId
            self.firstName = firstName
            self.lastName = lastName
            self.circledInitialsConfiguration = circledInitialsConfiguration
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(cryptoId)
        }
        
        static func == (lhs: HorizontalContactsView_Previews.User, rhs: HorizontalContactsView_Previews.User) -> Bool {
            lhs.cryptoId == rhs.cryptoId
        }

    }
    
    private final class Actions: SingleUserViewForHorizontalUsersLayoutActionsProtocol {
        func userWantsToDeleteUser(cryptoId: ObvTypes.ObvCryptoId) async {}
    }
    
    private static let identitiesAsURLs: [URL] = [
        URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!,
        URL(string: "https://invitation.olvid.io/#AwAAAHAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVZx8aqikpCe4h3ayCwgKBf-2nDwz-a6vxUo3-ep5azkBUjimUf3J--GXI8WTc2NIysQbw5fxmsY9TpjnDsZMW-AAAAAACEJvYiBXb3Jr")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHYAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAD5GDHskL0wOdRjeL9jqjk9VujoQz40aoF6ZQbemkUN8Bej7FwmFAf-Kxss1psnCavjIa6kpOHoeqQKID2SiQXckAAAAADkJlbnZlbnV0byAgKEAp")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHQAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAApiJHxXH73fq_IwsjQzNaAVqz-cUFq1Jt4FrLTMXihKIBP-dXlPyBZAib67ynX3vJOS5OepS3c0H_vBdIisycS8kAAAAADENoYXJsaWUgIChAKQ==")!,
        URL(string:"https://invitation.olvid.io/#AwAAAH4AAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAF8M9oXsYUtToB6_DKjdSLb8xp149impOaE3Z_HoMJoMBTUZA4jgEiwg85Vd2kW8JxZe105_snQmZjMJyiGIDqH4AAAAAFkpvc2UgIChKYXZhIEFyY2hpdGVjdCk=")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHEAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAc0RK3cH4miFs9QmoJ8DL_bX9-aAdaAHIDiL0z5-ed68Be7xT2o_Vm7BABfh0pmFJKWctDNJt3Qm7JYg5OEY1rZUAAAAACUtleWNsb2FrIA==")!,
        URL(string:"https://invitation.olvid.io/#AwAAAG4AAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAvVlhMRjdv2H81RHLXaguiEP5V4Yq1bM-CcezlW3BVSABAoPA81frqdDxqcyj5MdcwQ2D8j6J-er2Qrxk6p6Z1mwAAAAABkFsaWNlIA==")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHwAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAmSZQjI4rk_EdLRaVtqcB_OJ40YjMgbOcixZOkXYnkFoBGXxJfYRWhPO1HPLB5HNvw_zyG3UAGmpSIvQRcRPyb-QAAAAAFExhdXJlIEEuIChCb3NzQEJvc3Mp")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHwAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVJxgzxknGtTGDTeaik64WMTryiRLk9dGAwb9eyppwK8BS4yBgHT8iUzA6wmtFIGLWeSoVmrLCQ2NvZzkrjszktYAAAAAFExpc2UgQS4gKEFwcHJlbnRpZUAp")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHQAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAD4QZ87zzkSfNHeNfGI5t94vQzJsh8L_6mcswldVzfmoBKGsqPUOOWiHC635LomWWEEYQKo1aOEgEERhjUw_mEVMAAAAADEFwcCBBdXRoIChAKQ==")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHYAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAg5taJPBxk44MEJEUxYoRymXkio99q8YDRU985G5SuHYBPGDWLcplGe2sMiz3MJTVNlLd8pnzVYzaqFrVM6Aqh9EAAAAADlNpbXUgQnJ1bm8gKEAp")!,
        URL(string:"https://invitation.olvid.io/#AwAAAH4AAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAlIeSyt7KPGojNK1qkz1g4pq7jbEHw4xZ0yHMa9NBDs8BWJQO3ZrcLxsWIf_p0vNXKaYvsKAHsBnLLBS-rsIhRaAAAAAAFmRlc2t0b3AgQnJ1bm8yIChPbHZpZCk=")!,
        URL(string:"https://invitation.olvid.io/#AwAAAIcAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAmH7QEAnr5a2PT7Rixr---xC5hBQ22sOvhKyIBcSVmwwBaqkgafIKwiGiBg2AuMaNnGkMutUkSYTvmfBPnvTX5DMAAAAAH1JvbGFuZCBDdXZpZXIgKEluc3BlY3RldXJAREdQTik=")!,
        URL(string:"https://invitation.olvid.io/#AwAAAIgAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAmSZQjI4rk_EdLRaVtqcB_OJ40YjMgbOcixZOkXYnkFoBGXxJfYRWhPO1HPLB5HNvw_zyG3UAGmpSIvQRcRPyb-QAAAAAIENsYXJhIERlc2NoYW1wcyAoQENlcmVhbHMgQ29ycC4p")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHMAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAlh2hKYVtXSvtHJwHzKTRCXRsfmvsgoeLiXI_mwSmnBQBPZxuElTlX1fIdSPy6Cq2YMcfsLA1q26b5OhZ_XMztyMAAAAAC2ppbSBkb2UgKEAp")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHwAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAV3kAsHzL-9RbC9jri-BDy1s_8HUsfG0W93cYZFkWUAcBdnX8Bun8RCTa1zK9-9ZVNnLwjTgN5r3Fky_cl4XFbTAAAAAAFEdpdWxpYSBGLiAoQWN0cmVzc0Ap")!,
        URL(string:"https://invitation.olvid.io/#AwAAAIsAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA4sBS3xUo7_BAhOHfGw84U5440wFxbfkeG1es33hB370BIR1LO6BlY7460nWBbBv0R9Oc6rCoNsgD6N5dFcDlCGMAAAAAI0xvbGEgRi4gKE1hcmtldGluZyBNYW5hZ2VyICFAT2x2aWQp")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHkAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAZfREVd3DjMWY-RKSLzcfezF-d9a3uqziE-pFgqnX7m4BP9W1FrUZvAoENiah3bh9pwKdpY2_OgczQYWe4nugwbAAAAAAEUJydW5vIEd1w6lkb24gKEAp")!,
        URL(string:"https://invitation.olvid.io/#AwAAAIoAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA69q1WlDUts8cA1Ak6tKv8rDxXWR2ZT8O-RLzRrTLh2QBckgDzF7N12icwJbM0yhcHM7iCa-Tkuts8NkgLrnbbCkAAAAAIkJvYiBMYXphciAoY29uc3BpcmF0aW9uaXN0QEFyZWE1MSk=")!,
        URL(string:"https://invitation.olvid.io/#AwAAAIoAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAeWoN2RxfCxlYrzRGXNgZv62IgiBJxnsiF1aii9Kw22gBMUhnVHYth98cKaEkQiaQk-jWkinhNKAyuSAU652U8o0AAAAAIlNvcGhpZSBULiAoSGFwcHluZXNzIG9mZmljZXJAQUNNRSk=")!,
        URL(string:"https://invitation.olvid.io/#AwAAAJUAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAO1wIxMqpqaEvWNVxCZYgiKNFU05M-EqsLuDyiGBslJABInQAjfHHx1R18WRHp6mbOuK7hMrrl6gnngSeFzBlQJgAAAAALUFuYcOvcyBULiBSaWNoZSAoU2NpZW50aWZjIGFkdmlzb3JATWljcm9zb2Z0KQ==")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHoAAAAAWmh0dHBzOi8vc2VydmVyLm9sdmlkLmlvAADcbw_8VsTvd29XHaZxmGt8K1NJGZU4EZYCD6UnZKfbrAF9fJS6N2Y4FiJf4zu7mnl4XP8elwxPsIX9kbaPpNv3TQAAAAAWcm9tYWluIHRlc3QgKFBPQE9sdmlkKQ==")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHgAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAiX5MQIcTHmrSaW_DcpmdGG-UobLFx5hy0Gh4ypV5ePYBdBn84zGq0VCjp6LtIZzZS-r6Yp_tveTlo65PK8ihgkYAAAAAEERhdmlkIFRob21hcyAoQCk=")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHUAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAN1Rs9T7Mnt8k2JotUTIfFH49-VlZg2Wy6Dk278y_XrgBEfWLkPOPrtySYjmsjLrsy1fjBOA51BkqGKDY6pkQyb8AAAAADUFsaWNlIFRvbSAoQCk=")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHMAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAUf5tJY47V8EFVCDcPOI48FE8QRUNddgbNRQJI01C4VIBQMVhVmMtwDcszY001UJDIQynHN5zdpLXehgf_ehPwGwAAAAAC0JvYiBUb20gKEAp")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHUAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAA91ekYFtCK3XZ5vfiXC-zfz48RQwLxnS8CT-WR1_3NcBGZJNkAFSbG4cGYR_Acu69qmyHjQGAqhqhjlnsen0Z8cAAAAADUxhdXJhIFRvbSAoQCk=")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHUAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAGK6TtqVZeQA42CgRJZWQSN0NiTLiL1w9AcQiFZKg8R0BJ6sZoKxe1GexBE4ywe_14c5uILiMa7AwaHTRdin9aKwAAAAADU1hcmlhIFRvbSAoQCk=")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHEAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAXLsUvYE-GcU1ZX-IsWnhfVeAHawD7ahI79mF0EetL8cBa745VngDX6reudYHsYot6b-k4ND3IkMhusRY_GXanVUAAAAACWRlc2sgdG9wMQ==")!,
        URL(string:"https://invitation.olvid.io/#AwAAAIEAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAApyOLPcR13NEGIMCdR0i_q0PPxhKwz5nIq1meEC9unXgBFQHPOS7zlC8NwxkUmDDqXOPAhruIujaX8uxTmf92IJEAAAAAGUVsc2EgVHVybmluIChDYW5hcmRAQUNNRSk=")!,
        URL(string:"https://invitation.olvid.io/#AwAAAHUAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAtmon5jdxKySQke3D8GqkwR3Odv3jmqUlYvalETWo4ZABf2WQWvgzKiNeVRz8g2tQXMO8t6Usi27cQI4AwX8YZo0AAAAADUFsaWNlIFR3byAoQCk=")!
    ]
    
    
    private static let ownedCryptoIds = identitiesAsURLs.map({ ObvURLIdentity(urlRepresentation: $0)!.cryptoId })
    
    private static let ownedCircledInitialsConfigurations = [
        CircledInitialsConfiguration.contact(initial: "A", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[0], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "B", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[1], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "C", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[2], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "D", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[3], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "E", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[4], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "F", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[5], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "G", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[6], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "H", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[7], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "I", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[8], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "J", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[9], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "K", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[10], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "L", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[11], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "M", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[12], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "N", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[13], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "O", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[14], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "P", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[15], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "Q", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[16], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "R", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[17], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "S", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[18], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "T", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[19], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "U", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[20], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "V", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[21], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "W", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[22], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "X", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[23], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "Y", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[24], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "Z", photo: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[25], tintAdjustementMode: .normal)
    ]
    
    struct Configuration: HorizontalUsersViewConfigurationProtocol {
        let textOnEmptySetOfUsers: String
        let canEditUsers: Bool
    }
    
    static var previews: some View {
        Group {
            HorizontalUsersView(model: Users(selectedUsersOrdered: [
                User(cryptoId: ownedCryptoIds[0],
                        firstName: "Amaury",
                        lastName: "Aulait",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[0]),
                User(cryptoId: ownedCryptoIds[1],
                        firstName: "Bertrand",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[1]),
                User(cryptoId: ownedCryptoIds[2],
                        firstName: "Christophe",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[2]),
                User(cryptoId: ownedCryptoIds[3],
                        firstName: "Danielle",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[3]),
                User(cryptoId: ownedCryptoIds[4],
                        firstName: "Éléonore",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[4]),
                User(cryptoId: ownedCryptoIds[5],
                        firstName: "Françis",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[5]),
                User(cryptoId: ownedCryptoIds[6],
                        firstName: "Gaëtan",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[6]),
                User(cryptoId: ownedCryptoIds[13],
                        firstName: "Nicolas",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[13]),
                User(cryptoId: ownedCryptoIds[9],
                        firstName: "Joris",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[9]),
                User(cryptoId: ownedCryptoIds[10],
                        firstName: "Kevin",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[10]),
                User(cryptoId: ownedCryptoIds[11],
                        firstName: "Louison",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[11]),
                User(cryptoId: ownedCryptoIds[12],
                        firstName: "Mathieu",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[12]),
                User(cryptoId: ownedCryptoIds[8],
                        firstName: "Irène",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[8]),
                User(cryptoId: ownedCryptoIds[14],
                        firstName: "Orianne",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[14]),
                User(cryptoId: ownedCryptoIds[15],
                        firstName: "Pierre",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[15]),
                User(cryptoId: ownedCryptoIds[16],
                        firstName: "Quentin",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[16]),
                User(cryptoId: ownedCryptoIds[17],
                        firstName: "Rayane",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[17]),
                User(cryptoId: ownedCryptoIds[18],
                        firstName: "Sébastien",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[18]),
                User(cryptoId: ownedCryptoIds[19],
                        firstName: "Thimothé",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[19]),
                User(cryptoId: ownedCryptoIds[20],
                        firstName: "Ugo",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[20]),
                User(cryptoId: ownedCryptoIds[21],
                        firstName: "Victoria",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[21]),
                User(cryptoId: ownedCryptoIds[22],
                        firstName: "Warren",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[22]),
                User(cryptoId: ownedCryptoIds[23],
                        firstName: "Xavier",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[23]),
                User(cryptoId: ownedCryptoIds[24],
                        firstName: "Yasmina",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[24]),
                User(cryptoId: ownedCryptoIds[25],
                        firstName: "Zoë",
                        circledInitialsConfiguration: ownedCircledInitialsConfigurations[25])
            ]), configuration: Configuration(textOnEmptySetOfUsers: "Test string", canEditUsers: true),
            actions: Actions())
//            HorizontalUsersView(model: Contacts(contacts: []), actions: Actions())
            .padding(EdgeInsets(top: 100.0, leading: 20.0, bottom: 100.0, trailing: 20.0))
            .background(Color(.systemGroupedBackground))
            .previewLayout(.sizeThatFits)
        }
    }
}
