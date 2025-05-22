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
import ObvCrypto
import ObvDesignSystem


@MainActor
public protocol BackupedProfileFromServerViewModelProtocol: AnyObject, ObservableObject, Identifiable {
    associatedtype AvatarModel: ObvAvatarLegacyViewModel
    var firstNameThenLastName: String { get }
    var customDisplayName: String? { get }
    var positionAtCompany: String { get }
    var avatar: AvatarModel { get }
    var isOnThisDevice: Bool { get }
    var profileBackupSeed: BackupSeed { get }
    var ownedCryptoId: ObvCryptoId { get }
    var encodedPhotoServerKeyAndLabel: Data? { get }
}


protocol BackupedProfileFromServerViewActionsProtocol {
    @MainActor func fetchAvatarImage(profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage?
}


struct BackupedProfileFromServerView<Model: BackupedProfileFromServerViewModelProtocol>: View, ObvAvatarLegacyViewActions {
    
    @ObservedObject var model: Model
    let actions: BackupedProfileFromServerViewActionsProtocol
    let showChevron: Bool
    
    private let opacityIfOnThisDevice: Double = 0.4
    
    func fetchAvatarImageOfSize(_ size: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        let profileCryptoId = model.ownedCryptoId
        let encodedPhotoServerKeyAndLabel = model.encodedPhotoServerKeyAndLabel
        return await actions.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: size)
    }

    private var sanitizedCustomDisplayName: String? {
        guard let customDisplayName = model.customDisplayName else { return nil }
        let sanitized = customDisplayName.trimmingWhitespacesAndNewlines()
        return sanitized.isEmpty ? nil : sanitized
    }
    
    private var sanitizedPositionAtCompany: String? {
        let sanitized = model.positionAtCompany.trimmingWhitespacesAndNewlines()
        return sanitized.isEmpty ? nil : sanitized
    }

    private struct Titles {
        let title1: String
        let title2: String?
        let title3: String?
        let numberOfTitles: Int
    }

    private var titles: Titles {
        switch (sanitizedCustomDisplayName, sanitizedPositionAtCompany) {
        case (.none, .none):
            return Titles(title1: model.firstNameThenLastName, title2: nil, title3: nil, numberOfTitles: 1)
        case (.none, .some(let sanitizedPositionAtCompany)):
            return Titles(title1: model.firstNameThenLastName, title2: sanitizedPositionAtCompany, title3: nil, numberOfTitles: 2)
        case (.some(let sanitizedCustomDisplayName), .none):
            return Titles(title1: sanitizedCustomDisplayName, title2: model.firstNameThenLastName, title3: nil, numberOfTitles: 2)
        case (.some(let sanitizedCustomDisplayName), .some(let sanitizedPositionAtCompany)):
            return Titles(title1: sanitizedCustomDisplayName, title2: model.firstNameThenLastName, title3: sanitizedPositionAtCompany, numberOfTitles: 3)
        }
    }
        
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            
            ObvAvatarLegacyView(model: model.avatar, actions: self)
                .opacity(model.isOnThisDevice ? opacityIfOnThisDevice : 1.0)
                .padding(.trailing, 16)
            
            VStack(alignment: .leading) {
                Text(titles.title1)
                    .lineLimit(titles.numberOfTitles == 3 ? 1 : 2)
                if let title2 = titles.title2 {
                    Text(title2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let title3 = titles.title3 {
                        Text(title3)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .font(.body)
            .opacity(model.isOnThisDevice ? opacityIfOnThisDevice : 1.0)
            .padding(.trailing, 16)

            Spacer(minLength: 0)

            if model.isOnThisDevice {
                Text("IS_ON_THIS_DEVICE")
                    .foregroundStyle(.white)
                    .font(.caption)
                    .padding(6)
                    .background(Capsule().fill(Color(UIColor.systemGreen)))
                    .padding(.trailing, 8)
            }

            if showChevron {
                Image(systemIcon: .chevronRight)
            }
            
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(UIColor.systemFill)))
    }
}


// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: BackupedProfileFromServerViewActionsProtocol {
    
    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        let actions = AvatarActionsForPreviews()
        return await actions.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }

}

#Preview("Not on this device") {
    BackupedProfileFromServerView(
        model: BackupedProfileFromServerViewModelForPreviews(
            index: 3,
            isOnThisDevice: false,
            canNavigateToListOfThisProfileBackups: true,
            profileBackupSeed: BackupSeed(String(repeating: "0", count: 32))!),
        actions: AvatarActionsForPreviews(),
        showChevron: true)
}

#Preview("On this device") {
    BackupedProfileFromServerView(
        model: BackupedProfileFromServerViewModelForPreviews(
            index: 0,
            isOnThisDevice: true,
            canNavigateToListOfThisProfileBackups: true,
            profileBackupSeed: BackupSeed(String(repeating: "1", count: 32))!),
        actions: AvatarActionsForPreviews(),
        showChevron: true)
}

#endif
