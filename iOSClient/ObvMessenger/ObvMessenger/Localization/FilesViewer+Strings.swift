/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

extension FilesViewer {
    
    struct Strings {
        static let exportPdfTitle = NSLocalizedString("Export PDF file", comment: "Title of alert")
        static let exportPdfMessage = NSLocalizedString("What do you want to do with this PDF?", comment: "Message of alert")
        static let exportPdfActionExport = NSLocalizedString("Export to the system's Files App", comment: "Action of alert")
        static let fileExistsTitle = NSLocalizedString("Could not export file to the system's Files App", comment: "")
        static let fileExistsMessage = { (fileName: String) in
            String.localizedStringWithFormat(NSLocalizedString("A file named %@ already exists within the following location:\nOn My iPhone > Olvid", comment: ""), fileName)
        }
        static let fileExportedTitle = NSLocalizedString("File exported to the File App", comment: "")
        static let fileExportedMessage = { (fileName: String) in
            String.localizedStringWithFormat(NSLocalizedString("The file %@ can now be found in the File App, within the following location:\nOn My iPhone > Olvid", comment: ""), fileName)
        }
    }
    
}
