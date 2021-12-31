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

import SwiftUI

@available(iOS 13, *)
struct IdentityCardContentViewWithPhoto: View {

    @ObservedObject var singleIdentity: SingleIdentity
    @State private var activeSheet: ActiveSheet? = nil
    @State private var pictureState: UIImage? = nil

    fileprivate enum ActiveSheet: Identifiable {
        case libraryPicker, cameraPicker, editor
        var id: Int { hashValue }
    }

    private var runningOnRealDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
    private func buildCameraButtonActions() -> [ProfilePictureAction] {
        var actions: [ProfilePictureAction] = []
        actions += [ProfilePictureAction(title: "Choose picture") {
            self.activeSheet = .libraryPicker
        }]
        if runningOnRealDevice {
            actions += [ProfilePictureAction(title: "Take picture") {
                self.activeSheet = .cameraPicker
            }]
        }
        actions += [ProfilePictureAction(title: "Remove picture") {
            self.singleIdentity.photo = nil
        }]
        return actions
    }

    private static var rfc3339Formatter: DateFormatter {
        let RFC3339DateFormatter = DateFormatter()
        RFC3339DateFormatter.locale = Locale(identifier: "en_US_POSIX")
        RFC3339DateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        RFC3339DateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return RFC3339DateFormatter
    }

    var body: some View {
        IdentityCardContentView(
            contact: singleIdentity,
            allowProfilPictureEdition: true,
            profilPictureEditionActions: buildCameraButtonActions())
            .sheet(item: $activeSheet) { item in
                switch item {
                case .cameraPicker:
                    ImagePicker(image: $pictureState, useCamera: true) {
                        activeSheet = .editor
                    }
                case .libraryPicker:
                    ImagePicker(image: $pictureState, useCamera: false) {
                        activeSheet = .editor
                    }
                case .editor:
                    ImageEditor(image: $pictureState) {
                        if let image = pictureState, let data = image.jpegData(compressionQuality: 0.75) {
                            let filename = ObvMessengerConstants.containerURL.identityPhotosCache.appendingPathComponent(
                                IdentityCardContentViewWithPhoto.rfc3339Formatter.string(from: Date()) + "_cropped.jpg")
                            do {
                                try data.write(to: filename)
                                singleIdentity.photo = filename
                            } catch {
                                return
                            }
                            print("A new image was been saved in \(filename)")
                        }
#warning("Ca marche pas sur ios 13 sur simulateur ..")
                        activeSheet = nil
                    }
                }
            }
    }
}
