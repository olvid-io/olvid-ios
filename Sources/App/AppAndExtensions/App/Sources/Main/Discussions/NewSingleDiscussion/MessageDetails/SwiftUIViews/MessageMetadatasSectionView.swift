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

import CoreData
import ObvUI
import ObvUICoreData
import ObvTypes
import SwiftUI
import ObvSystemIcon
import ObvDesignSystem


/// Expected to be implemented by `PersistedMessageSent`
protocol SentMessageMetadatasSectionViewModelProtocol: ObservableObject {
    
    var status: PersistedMessageSent.MessageStatus { get }
    var hasMoreThanOneRecipient: Bool { get }

}


struct SentMessageMetadatasSectionView<Model: SentMessageMetadatasSectionViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let messageObjectID: NSManagedObjectID
    let ownedCryptoId: ObvCryptoId
    let stringFromDate: (Date?) -> String?
    
    init(model: Model, messageObjectID: NSManagedObjectID, ownedCryptoId: ObvCryptoId, stringFromDate: @escaping (Date?) -> String?) {
        self.model = model
        self.messageObjectID = messageObjectID
        self.ownedCryptoId = ownedCryptoId
        self.stringFromDate = stringFromDate
    }
    
    private var messageStatusTitle: LocalizedStringKey {
        return model.status.getLocalizedStringKey(messageHasMoreThanOneRecipient: model.hasMoreThanOneRecipient)
    }
    
    private var messageStatusIcon: any SymbolIcon {
        return model.status.getSymbolIcon(messageHasMoreThanOneRecipient: model.hasMoreThanOneRecipient)
    }

    var body: some View {
        Section("MESSAGE_STATUS") {
            
            Label(
                title: {
                    Text(messageStatusTitle)
                        .foregroundStyle(.primary)
                },
                icon: {
                    Image(symbolIcon: messageStatusIcon)
                        //.renderingMode(.original)
                        .foregroundColor(.secondary)
                        //.foregroundStyle(.secondary)
                }
            )
            .font(.body)
            
            MessageMetadatasSectionView(messageObjectID: messageObjectID,
                                        ownedCryptoId: ownedCryptoId,
                                        stringFromDate: stringFromDate)
            
        }
    }
    
}


struct MessageMetadatasSectionView: View {
    
    var fetchRequest: FetchRequest<PersistedMessageTimestampedMetadata>
    let ownedCryptoId: ObvCryptoId
    let stringFromDate: (Date?) -> String?
    
    init(messageObjectID: NSManagedObjectID, ownedCryptoId: ObvCryptoId, stringFromDate: @escaping (Date?) -> String?) {
        let nsFetchRequest = PersistedMessageTimestampedMetadata.getFetchRequest(messageObjectID: messageObjectID)
        self.fetchRequest = FetchRequest(fetchRequest: nsFetchRequest, animation: .easeInOut)
        self.ownedCryptoId = ownedCryptoId
        self.stringFromDate = stringFromDate
    }
    
    var body: some View {
        if !fetchRequest.wrappedValue.isEmpty {
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


fileprivate struct MetadataView: View {
    
    let ownedCryptoId: ObvCryptoId
    let forKind: PersistedMessage.MetadataKind
    var dateAsString: String?
    
    private var icon: any SymbolIcon {
        switch forKind {
        case .wiped:
            return SystemIcon.flameFill
        case .remoteWiped:
            return SystemIcon.trash
        case .edited:
            return SystemIcon.pencil(.circleFill)
        }
    }
    
    private var title: String {
        switch forKind {
        case .wiped: return NSLocalizedString("Wiped", comment: "")
        case .remoteWiped(remoteCryptoId: let cryptoId):
            if cryptoId == ownedCryptoId {
                return String.localizedStringWithFormat(NSLocalizedString("REMOTELY_WIPED_BY_YOU", comment: ""))
            } else if let contact = try? PersistedObvContactIdentity.get(contactCryptoId: cryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) {
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
            
            Label(
                title: {
                    Text(self.title)
                        .foregroundStyle(.primary)
                },
                icon: {
                    Image(symbolIcon: icon)
                        .foregroundColor(.secondary)
                }
            )
            .font(.body)
            
            Spacer()
            
            Text(dateString)
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
            
        }
        .font(.body)
    }
    
}
