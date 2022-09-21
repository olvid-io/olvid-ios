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

extension AttachementInfo {
    var icon: ObvSystemIcon {
        switch self.status {
        case .none: return .circleDashed
        case .delivered: return .checkmarkCircleFill
        case .read: return .eyeFill
        }
    }

    var title: String {
        switch self.status {
        case .none: return NSLocalizedString("Sent", comment: "")
        case .delivered: return NSLocalizedString("Delivered", comment: "")
        case .read: return NSLocalizedString("Read", comment: "")
        }
    }
}


struct AttachementInfosView: View {
    let attachmentInfos: [AttachementInfo]

    var body: some View {
        if !attachmentInfos.isEmpty {
            Section(header: Text("ATTACHMENTS_INFO")) {
                ForEach(attachmentInfos) { attachmentInfo in
                    if attachmentInfo.attachmentRecipientsInfos.count == 1 {
                        HStack {
                            Image(systemIcon: attachmentInfo.icon)
                                .foregroundColor(Color(.secondaryLabel))
                            Text(attachmentInfo.filename)
                                .font(.callout)
                                .foregroundColor(Color(.secondaryLabel))
                        }
                    } else {
                        NavigationLink {
                            AttachementInfosDetailsView(filename: attachmentInfo.filename, attachmentRecipientsInfos: attachmentInfo.attachmentRecipientsInfos)
                        } label: {
                            HStack {
                                if let icon = attachmentInfo.icon {
                                    Image(systemIcon: icon)
                                }
                                Text(attachmentInfo.filename)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct AttachementInfosDetailsView: View {

    let filename: String
    let attachmentRecipientsInfos: [(String, PersistedAttachmentSentRecipientInfos.ReceptionStatus?)]

    var body: some View {
        List {
            Section(header: Text(filename)) {
                ForEach(attachmentRecipientsInfos, id: \.0) { (recipientName, status) in
                    HStack {
                        Image(systemIcon: icon(for: status))
                        Text(recipientName)
                    }
                }
            }
        }
    }

    func icon(for status: PersistedAttachmentSentRecipientInfos.ReceptionStatus?) -> ObvSystemIcon {
        guard let status = status else {
            return .checkmarkCircle
        }
        switch status {
        case .delivered: return .checkmarkCircleFill
        case .read: return .eyeFill
        }
    }
}
