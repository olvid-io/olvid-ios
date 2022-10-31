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

import SwiftUI
import ObvEngine


struct TrustOriginsView: View {
    
    let trustOrigins: [ObvTrustOrigin]
    let dateFormatter: DateFormatter
    
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(trustOrigins, id: \.self) { trustOrigin in
                TrustOriginCell(trustOrigin: trustOrigin, dateFormatter: dateFormatter)
                if trustOrigin != trustOrigins.last {
                    SeparatorView()
                }
            }
        }
    }
    
}



fileprivate struct TrustOriginCell: View {

    let trustOrigin: ObvTrustOrigin
    let dateFormatter: DateFormatter
    
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
                if #available(iOS 14, *) {
                    Text(dateFormatter.string(from: trustOrigin.date))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.subheadline)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                } else {
                    Text(dateFormatter.string(from: trustOrigin.date))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.footnote)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                }
            }
            Spacer()
        }
    }
    
}




struct TrustOriginsView_Previews: PreviewProvider {
    
    static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.dateStyle = .long
        df.timeStyle = .short
        return df
    }()
    
    static let someDate = Date(timeIntervalSince1970: 1_600_000_000)
    
    static var previews: some View {
        Group {
            TrustOriginCell(trustOrigin: ObvTrustOrigin.direct(timestamp: someDate),
                            dateFormatter: dateFormatter)
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
            TrustOriginCell(trustOrigin: ObvTrustOrigin.introduction(timestamp: someDate, mediator: nil),
                            dateFormatter: dateFormatter)
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
            TrustOriginCell(trustOrigin: ObvTrustOrigin.group(timestamp: someDate, groupOwner: nil),
                            dateFormatter: dateFormatter)
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
            TrustOriginCell(trustOrigin: ObvTrustOrigin.direct(timestamp: someDate),
                            dateFormatter: dateFormatter)
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
            TrustOriginCell(trustOrigin: ObvTrustOrigin.introduction(timestamp: someDate, mediator: nil),
                            dateFormatter: dateFormatter)
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
            TrustOriginCell(trustOrigin: ObvTrustOrigin.group(timestamp: someDate, groupOwner: nil),
                            dateFormatter: dateFormatter)
                .previewLayout(.sizeThatFits)
                .padding()
                .frame(width: 300, height: 110, alignment: .leading)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
            TrustOriginsView(trustOrigins: [.direct(timestamp: someDate),
                                            .introduction(timestamp: someDate, mediator: nil),
                                            .group(timestamp: someDate, groupOwner: nil)
            ],
            dateFormatter: dateFormatter)
        }
    }
}
