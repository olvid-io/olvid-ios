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

import Foundation
import ObvTypes
import ObvCrypto
import ObvDesignSystem
import ObvAppTypes
import ObvSystemIcon
import SwiftUI
import ObvProfilePictureBarButtonItem
import ObvOwnedIdentityChooser
import ObvCells

#if DEBUG


extension Color {
    
    static let count: Int = 200
    
    static let sampleDatasForForeground: [Self] = {
        var colors: [Color] = []
        for _ in 0..<Self.count {
            let red = CGFloat.random(in: 0...1)
            let green = CGFloat.random(in: 0...1)
            let blue = CGFloat.random(in: 0...1)
            let color = Color(red: red, green: green, blue: blue)
            colors.append(color)
        }
        return colors
    }()

    static let sampleDatasForBackground: [Self] = {
        var colors: [Color] = []
        for _ in 0..<Self.count {
            let red = CGFloat.random(in: 0...1)
            let green = CGFloat.random(in: 0...1)
            let blue = CGFloat.random(in: 0...1)
            let color = Color(red: red, green: green, blue: blue)
            colors.append(color)
        }
        return colors
    }()

}


extension ObvAvatarViewModel.Colors {

    static let sampleDatas: [Self] = (0..<Color.count).map { index in
        ObvAvatarViewModel.Colors(foreground: UIColor(Color.sampleDatasForForeground[index]), background: UIColor(Color.sampleDatasForBackground[index]))
    }

}


extension ObvAvatarViewModel {
    
    @MainActor
    static var sampleData: Self {
        return .init(characterOrIcon: .icon(.person3), colors: ObvAvatarViewModel.Colors.sampleDatas.randomElement()!, photoURL: nil)
    }
    
    @MainActor
    static let sampleDatas: [Self] = ObvAvatarViewModel.Colors.sampleDatas.map {
        .init(characterOrIcon: .icon(.person3),
              colors: $0,
              photoURL: nil)
    }
    
    @MainActor
    static let sampleDataForOwnedCryptoId: Self = .init(
        characterOrIcon: .character("A"),
        colors: ObvAvatarViewModel.Colors.sampleDatas[0],
        photoURL: nil)
    
}


extension String {
    
    static let sampleGroupTitles: [Self] = (0..<100).map { index in
        "Group title \(index)"
    }
    
    static let sampleListOfGroupMemberNames: [Self] = (0..<100).map { index in
        "Group members \(index)"
    }
    
}


extension Bool {
    
    static let showGreenShieldSamples: [Self] = (0..<100).map { _ in
        Bool.random() ? true : false
    }
    
}


extension ObvGroupCellViewModel.HasUpdatedDetails {
    
    static let samples: [Self] = (0..<100).map { _ in
        let rand = Double.random(in: 0..<1)
        if rand < 0.5 {
            return .noNewPublishedDetails
        } else if rand < 0.8 {
            return .seenPublishedDetails
        } else {
            return .unseenPublishedDetails
        }
    }
    
}


extension ObvGroupCellViewModel {
    
    @MainActor
    static let sampleData: Self = .init(
        groupIdentifier: .groupV2(.sampleData),
        avatarModel: ObvAvatarViewModel.sampleData,
        title: "Group title",
        listOfGroupMemberNames: "Alice, Bob, Carol, David, Eve, Frank, Grace, Henry, Irene, Jack, Kate, Lee, Mark, Nancy, Oliver, Penelope, Quentin, Rachel, Simon, Tina, Ursula, Victor, Wendy, Xenia, Yvonne",
        showGreenShield: false,
        hasUpdatedDetails: .noNewPublishedDetails,
        updateInProgress: false)

    @MainActor
    static func sampleData(groupIdentifier: ObvGroupCellViewModel.GroupIdentifier) -> Self {
        guard let index = ObvGroupCellViewModel.GroupIdentifier.sampleDatas.firstIndex(of: groupIdentifier) else {
            assertionFailure()
            return Self.sampleData
        }
        return .init(groupIdentifier: .groupV2(.sampleData),
                     avatarModel: ObvAvatarViewModel.sampleDatas[index],
                     title: String.sampleGroupTitles[index],
                     listOfGroupMemberNames: String.sampleListOfGroupMemberNames[index],
                     showGreenShield: Bool.showGreenShieldSamples[index],
                     hasUpdatedDetails: HasUpdatedDetails.samples[index],
                     updateInProgress: false)
    }
    
}


extension ObvCryptoId {
    
    @MainActor
    static let sampleData: Self =
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
        
}

extension UID {
    
    @MainActor
    static let sampleDatas: [UID] = (0..<100).map { index in
        var n = index
        let uid = Data(bytes: &n, count: 32)
        return UID(uid: uid)!
    }
    
}

extension ObvGroupV2.Identifier {
    
    @MainActor
    static let sampleData: Self = .init(groupUID: UID.zero,
                                        serverURL: URL(string: "https//olvid.io")!,
                                        category: .server)
    
    
    @MainActor
    static let sampleDatas: [Self] = UID.sampleDatas.map {
        .init(groupUID: $0,
              serverURL: URL(string: "https//olvid.io")!,
              category: Bool.random() ? .server : .keycloak)
    }
    

}

extension ObvGroupV2Identifier {
    
    @MainActor
    static let sampleData: Self = .init(ownedCryptoId: .sampleData,
                                        identifier: .sampleData)
    
    @MainActor
    static let sampleDatas: [Self] = ObvGroupV2.Identifier.sampleDatas.map {
        .init(ownedCryptoId: ObvCryptoId.sampleData,
              identifier: $0)
    }
    
}


extension ObvGroupIdentifier {

    @MainActor
    static let sampleData: Self = .groupV2(.sampleData)
    
    @MainActor
    static let sampleDatas: [Self] = ObvGroupV2Identifier.sampleDatas.map {
        .groupV2($0)
    }
    
}



extension ObvGroupCellViewModel.GroupIdentifier {

    @MainActor
    static let sampleDatas: [Self] = ObvGroupIdentifier.sampleDatas.map {
        .obvGroupIdentifier($0)
    }
    
}


extension ObvProfilePictureBarButtonItemViewModel {
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        let avatarModel = ObvAvatarViewModel.sampleDataForOwnedCryptoId
        return .init(ownedCryptoId: ownedCryptoId,
                     avatarModel: avatarModel,
                     showGreenShield: false,
                     showRedDot: false)
    }
    
}


extension OwnedIdentityChooserViewModel {
    
    @MainActor
    static let sampleData: Self = .init(ownedIdentities: [
        .init(ownedCryptoId: ObvCryptoId.sampleData,
              avatarViewModel: ObvAvatarViewModel.sampleDataForOwnedCryptoId,
              title: "Alice",
              subtitle: "Subtitle",
              totalBadgeCount: 3,
              showGreenShield: false,
              showRedShield: false,
              showHiddenProfileIcon: false)
    ])
    
}


#endif
