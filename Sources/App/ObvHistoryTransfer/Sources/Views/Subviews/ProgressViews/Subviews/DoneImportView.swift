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

import SwiftUI


/// View used both in `LocalNetworkImportView` and in `ZipImportView`.
struct DoneImportView: View {
    
    let receivingDoneStatus: ReceivingDoneStatus

    private var title: String {
        switch receivingDoneStatus {
        case .exportWasSuccessful:
            return String(localizedInThisBundle: "DONE_IMPORT_VIEW_TITLE_EXPORT_WAS_SUCCESSFUL")
        case .exportWasCancelledByUser:
            return String(localizedInThisBundle: "DONE_IMPORT_VIEW_TITLE_EXPORT_CANCELLED_BY_USER")
        case .exportFailed:
            return String(localizedInThisBundle: "DONE_IMPORT_VIEW_TITLE_EXPORT_FAILED")
        case .exportFailedAsIdentitiesDidNotMatch:
            return String(localizedInThisBundle: "DONE_IMPORT_VIEW_TITLE_EXPORT_IDENTITY_MISMATCH")
        }
    }

    private var subtitle: String {
        switch receivingDoneStatus {
        case .exportWasSuccessful:
            return String(localizedInThisBundle: "DONE_IMPORT_VIEW_SUBTITLE_EXPORT_WAS_SUCCESSFUL")
        case .exportWasCancelledByUser:
            return String(localizedInThisBundle: "DONE_IMPORT_VIEW_SUBTITLE_EXPORT_CANCELLED_BY_USER")
        case .exportFailed:
            return String(localizedInThisBundle: "DONE_IMPORT_VIEW_SUBTITLE_EXPORT_FAILED")
        case .exportFailedAsIdentitiesDidNotMatch:
            return String(localizedInThisBundle: "DONE_IMPORT_VIEW_SUBTITLE_EXPORT_IDENTITY_MISMATCH")
        }
    }
    
    private var subtitleFailedAttachments: String? {
        switch receivingDoneStatus {
        case .exportWasSuccessful(failedFylesCount: let failedFylesCount):
            if failedFylesCount > 0 {
                return String(localizedInThisBundle: "DONE_IMPORT_VIEW_SUBTITLE_EXPORT_\(failedFylesCount)_ATTACHMENTS_COULD_NOT_BE_SENT")
            } else {
                return nil
            }
        case .exportWasCancelledByUser, .exportFailed, .exportFailedAsIdentitiesDidNotMatch:
            return nil
        }
    }

    private var state: ProgressItemState {
        switch receivingDoneStatus {
        case .exportWasSuccessful:
            return .success
        case .exportWasCancelledByUser:
            return .warning
        case .exportFailed, .exportFailedAsIdentitiesDidNotMatch:
            return .error
        }
    }

    var body: some View {
        ProgressItemRowView(state: state, showLine: false, title: title) {
            Text(subtitle)
            if let subtitleFailedAttachments {
                Text(subtitleFailedAttachments)
            }
        }
    }

}
