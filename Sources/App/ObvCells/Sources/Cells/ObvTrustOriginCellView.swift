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

import SwiftUI
import ObvTypes
import ObvDesignSystem
import ObvSystemIcon


public struct ObvTrustOriginCellView: View {
    
    let model: Model
    
    public struct Model: Sendable, Equatable, Hashable {
        let contactIdentifier: ObvContactIdentifier
        let date: Date
        let kind: TrustOriginKind
        
        public init(contactIdentifier: ObvContactIdentifier, date: Date, kind: TrustOriginKind) {
            self.contactIdentifier = contactIdentifier
            self.date = date
            self.kind = kind
        }

        public enum TrustOriginKind: Sendable, Equatable, Hashable {
            case direct
            case groupV1(groupOwner: ObvCryptoId, groupOwnerName: String?)
            case groupV2Server(groupIdentifier: ObvGroupV2.Identifier, groupName: String?)
            case keycloak
            case introduction(mediator: ObvCryptoId, mediatorName: String?)
        }
    }
        
    private var systemIcon: SystemIcon {
        switch model.kind {
        case .direct:
            return .earBadgeCheckmark
        case .introduction:
            return .figureStandLineDottedFigureStand
        case .groupV1:
            return .person3Fill
        case .keycloak:
            return .serverRack
        case .groupV2Server:
            return .person3Fill
        }
    }
    
    private var imageColor: Color {
        switch model.kind {
        case .direct: return .green
        case .introduction: return .blue
        case .groupV1: return .pink
        case .keycloak: return Color(#colorLiteral(red: 0.9411764741, green: 0.4980392158, blue: 0.3529411852, alpha: 1))
        case .groupV2Server: return .pink
        }
    }
    
    private var title: String {
        switch model.kind {
        case .direct:
            return String(localizedInThisBundle: "TRUST_ORIGIN_TITLE_DIRECT")
        case .groupV1(groupOwner: _, groupOwnerName: let groupOwnerName):
            if let groupOwnerName {
                return String(localizedInThisBundle: "TRUST_ORIGIN_TITLE_GROUP_WITH_OWNER_\(groupOwnerName)")
            } else {
                return String(localizedInThisBundle: "TRUST_ORIGIN_TITLE_GROUP_WITH_DELETED_OWNER")
            }
        case .groupV2Server(groupIdentifier: _, groupName: let groupName):
            if let groupName {
                return String(localizedInThisBundle: "TRUST_ORIGIN_TITLE_GROUP_WITH_NAME_\(groupName)")
            } else {
                return String(localizedInThisBundle: "TRUST_ORIGIN_TITLE_GROUP_NOW_DELETED")
            }
        case .keycloak:
            return String(localizedInThisBundle: "TRUST_ORIGIN_IDENTITY_SERVER")
        case .introduction(mediator: _, mediatorName: let mediatorName):
            if let mediatorName {
                return String(localizedInThisBundle: "TRUST_ORIGIN_TITLE_INTRODUCTION_\(mediatorName)")
            } else {
                return String(localizedInThisBundle: "TRUST_ORIGIN_TITLE_INTRODUCTION_BY_DELETED_MEDIATOR")
            }
        }
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemIcon: systemIcon)
                .foregroundColor(imageColor)
                .font(.system(size: 22))
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                HStack {
                    Text(model.date, style: .date)
                    Text(model.date, style: .time)
                }
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .font(.subheadline)
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
            }
            Spacer()
        }
    }

}
