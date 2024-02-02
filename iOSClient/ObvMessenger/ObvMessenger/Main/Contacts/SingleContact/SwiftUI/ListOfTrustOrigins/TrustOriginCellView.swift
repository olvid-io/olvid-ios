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


import ObvEngine
import ObvUI
import SwiftUI
import ObvDesignSystem


struct TrustOriginCellView: View {

    let trustOrigin: ObvTrustOrigin
    
    private var image: Image? {
        switch trustOrigin {
        case .direct:
            return Image(systemIcon: .earBadgeCheckmark)
        case .introduction:
            return Image(systemIcon: .figureStandLineDottedFigureStand)
        case .group:
            return Image(systemIcon: .person3Fill)
        case .keycloak:
            return Image(systemIcon: .serverRack)
        case .serverGroupV2:
            return Image(systemIcon: .person3Fill)
        }
    }
    
    private var title: Text {
        switch trustOrigin {
        case .direct:
            return Text("TRUST_ORIGIN_TITLE_DIRECT")
        case .introduction(timestamp: _, mediator: let mediator):
            if let mediator = mediator {
                return Text("TRUST_ORIGIN_TITLE_INTRODUCTION_\(mediator.trustedIdentityDetails.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName))")
            } else {
                return Text("INTRODUCED_BY_FORMER_CONTACT")
            }
        case .group:
            return Text("TRUST_ORIGIN_TITLE_GROUP")
        case .keycloak:
            return Text("IDENTITY_SERVER")
        case .serverGroupV2:
            return Text("TRUST_ORIGIN_TITLE_GROUP")
        }
    }
    
    private var imageColor: Color {
        switch trustOrigin {
        case .direct: return .green
        case .introduction: return .blue
        case .group: return .pink
        case .keycloak: return Color(#colorLiteral(red: 0.9411764741, green: 0.4980392158, blue: 0.3529411852, alpha: 1))
        case .serverGroupV2: return .pink
        }
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            image
                .foregroundColor(imageColor)
                .font(.system(size: 22))
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 4) {
                title
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                HStack {
                    Text(trustOrigin.date, style: .date)
                    Text(trustOrigin.date, style: .time)
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



// MARK: - Previews

struct TrustOriginsView_Previews: PreviewProvider {
    
    static let someDate = Date(timeIntervalSince1970: 1_600_000_000)
    
    static var previews: some View {
        Group {
            TrustOriginCellView(trustOrigin: ObvTrustOrigin.direct(timestamp: someDate))
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
            TrustOriginCellView(trustOrigin: ObvTrustOrigin.introduction(timestamp: someDate, mediator: nil))
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
            TrustOriginCellView(trustOrigin: ObvTrustOrigin.group(timestamp: someDate, groupOwner: nil))
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
            TrustOriginCellView(trustOrigin: ObvTrustOrigin.direct(timestamp: someDate))
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
            TrustOriginCellView(trustOrigin: ObvTrustOrigin.introduction(timestamp: someDate, mediator: nil))
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
            TrustOriginCellView(trustOrigin: ObvTrustOrigin.group(timestamp: someDate, groupOwner: nil))
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
        }
    }
}
