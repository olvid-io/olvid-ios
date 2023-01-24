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
import ObvTypes
import CoreData


struct MessageMetadatasSectionView: View {
    
    var fetchRequest: FetchRequest<PersistedMessageTimestampedMetadata>
    let ownedCryptoId: ObvCryptoId
    let stringFromDate: (Date?) -> String?
    
    init(messageObjectID: NSManagedObjectID, ownedCryptoId: ObvCryptoId, stringFromDate: @escaping (Date?) -> String?) {
        let nsFetchRequest = PersistedMessageTimestampedMetadata.getFetchRequest(messageObjectID: messageObjectID, excludeKindRead: true)
        self.fetchRequest = FetchRequest(fetchRequest: nsFetchRequest, animation: .easeInOut)
        self.ownedCryptoId = ownedCryptoId
        self.stringFromDate = stringFromDate
    }
    
    var body: some View {
        if !fetchRequest.wrappedValue.isEmpty {
            Section {
                ForEach(fetchRequest.wrappedValue, id: \.self) { metadata in
                    if let kind = metadata.kind {
                        MetadataView(ownedCryptoId: ownedCryptoId,
                                     forKind: kind,
                                     dateAsString: stringFromDate(metadata.date))
                    }
                }
            }
        }
    }
    
}


fileprivate struct MetadataView: View {
    
    let ownedCryptoId: ObvCryptoId
    let forKind: PersistedMessage.MetadataKind
    var dateAsString: String?
    
    private var icon: ObvSystemIcon {
        switch forKind {
        case .read:
            return .eyeFill
        case .wiped:
            return .flameFill
        case .remoteWiped:
            return .trash
        case .edited:
            return .pencil(.circleFill)
        }
    }
    
    private var title: String {
        switch forKind {
        case .read: return NSLocalizedString("Read", comment: "")
        case .wiped: return NSLocalizedString("Wiped", comment: "")
        case .remoteWiped(remoteCryptoId: let cryptoId):
            if let contact = try? PersistedObvContactIdentity.get(contactCryptoId: cryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) {
                return String.localizedStringWithFormat(NSLocalizedString("Remotely wiped by %@", comment: ""), contact.customDisplayName ?? contact.fullDisplayName)
            } else {
                return NSLocalizedString("Remotely wiped", comment: "")
            }
        case .edited: return CommonString.Word.Edited            
        }
    }
    
    private var dateString: String {
        dateAsString ?? "-"
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            ObvLabelAlt(title: self.title, systemIcon: icon)
            Spacer()
            Text(dateString)
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
        }
        .font(.body)
    }
    
}



struct MessageMetadataView_Previews: PreviewProvider {
    
    static var previews: some View {
        Group {
            ReceivedMessageStatusView(forStatus: .read, dateAsString: nil)
        }
        .padding()
        .previewLayout(.fixed(width: 400, height: 70))
    }
}
