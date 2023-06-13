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
import ObvEngine
import CoreData
import Combine
import ObvUI
import ObvUICoreData
import UI_CircledInitialsView_CircledInitialsConfiguration

protocol OwnedIdentityChooserViewControllerDelegate: AnyObject {
    func userUsedTheOwnedIdentityChooserViewControllerToChoose(ownedCryptoId: ObvCryptoId) async
    func userWantsToEditCurrentOwnedIdentity(ownedCryptoId: ObvCryptoId) async
    var ownedIdentityChooserViewControllerShouldAllowOwnedIdentityDeletion: Bool { get }
    var ownedIdentityChooserViewControllerShouldAllowOwnedIdentityEdition: Bool { get }
    var ownedIdentityChooserViewControllerShouldAllowOwnedIdentityCreation: Bool { get }
    var ownedIdentityChooserViewControllerExplanationString: String? { get }
}


final class OwnedIdentityChooserViewController: UIHostingController<OwnedIdentityChooserView> {
    
    private let ownedIdentities: [PersistedObvOwnedIdentity]
    var callbackOnViewDidDisappear: (() -> Void)?
    
    init(currentOwnedCryptoId: ObvCryptoId, ownedIdentities: [PersistedObvOwnedIdentity], delegate: OwnedIdentityChooserViewControllerDelegate) {
        self.ownedIdentities = ownedIdentities
        let view = OwnedIdentityChooserView(currentOwnedCryptoId: currentOwnedCryptoId,
                                            ownedIdentities: ownedIdentities,
                                            delegate: delegate)
        super.init(rootView: view)
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        callbackOnViewDidDisappear?()
    }
        
}


struct OwnedIdentityChooserView: View {
    
    let currentOwnedCryptoId: ObvCryptoId
    let ownedIdentities: [PersistedObvOwnedIdentity]
    weak var delegate: OwnedIdentityChooserViewControllerDelegate?
    
    /// Set when switching owned identity. We use the state to perform nice animations for the checkmark and for hiding the items corresponding to a hidden profile.
    /// This is thus only set when the user taps on an owned identity that is different from the current one.
    @State private var ownedCryptoIdSwitchedTo: ObvCryptoId?

    private var models: [OwnedIdentityItemView.Model] {
        ownedIdentities.map {
            OwnedIdentityItemView.Model(
                ownedIdentity: $0,
                currentOwnedCryptoId: currentOwnedCryptoId,
                ownedCryptoIdSwitchedTo: $ownedCryptoIdSwitchedTo)
        }
    }
    
    private var modelsToShow: [OwnedIdentityItemView.Model] {
        if ownedCryptoIdSwitchedTo != nil {
            return models.filter({ !$0.showHiddenProfileIcon })
        } else {
            return models
        }
    }

    
    var body: some View {
        OwnedIdentityChooserInnerView(currentOwnedCryptoId: currentOwnedCryptoId,
                                      models: modelsToShow,
                                      delegate: delegate)
    }
    
}


/// View allowing SwiftUI previews for the `OwnedIdentityChooserView`.
fileprivate struct OwnedIdentityChooserInnerView: View {
    
    let currentOwnedCryptoId: ObvCryptoId
    let models: [OwnedIdentityItemView.Model]
    weak var delegate: OwnedIdentityChooserViewControllerDelegate?
    
    private var allowDeletion: Bool {
        delegate?.ownedIdentityChooserViewControllerShouldAllowOwnedIdentityDeletion ?? false
    }
    
    private var allowEdition: Bool {
        delegate?.ownedIdentityChooserViewControllerShouldAllowOwnedIdentityEdition ?? false
    }
    
    private var allowCreation: Bool {
        delegate?.ownedIdentityChooserViewControllerShouldAllowOwnedIdentityCreation ?? false
    }
    
    private var explanationString: String? {
        delegate?.ownedIdentityChooserViewControllerExplanationString
    }


    var body: some View {
        NavigationView {
            VStack {
                if let explanationString {
                    HStack {
                        Text(explanationString)
                            .font(.body)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal)
                }
                List {
                    ForEach(models) { model in
                        if #available(iOS 15.0, *) {
                            OwnedIdentityItemView(
                                model: model,
                                delegate: delegate)
                                .listRowSeparator(.hidden)
                        } else {
                            OwnedIdentityItemView(
                                model: model,
                                delegate: delegate)
                        }
                    }
                    .if(allowDeletion, transform: { view in
                        view.onDelete { indexSet in
                            guard let index = indexSet.first else { return }
                            guard let ownedCryptoId = models[safe: index]?.ownedCryptoId else { return }
                            ObvMessengerInternalNotification.userWantsToDeleteOwnedIdentityButHasNotConfirmedYet(ownedCryptoId: ownedCryptoId)
                                .postOnDispatchQueue()
                        }
                    })
                }
                .listStyle(.plain)
                .if(allowDeletion, transform: { view in
                    view.navigationBarItems(leading: EditButton())
                })
                if allowEdition {
                    OlvidButton(style: .standardWithBlueText,
                                title: Text("EDIT_CURRENT_IDENTITY"),
                                systemIcon: .pencil(.circle)) {
                        Task { await delegate?.userWantsToEditCurrentOwnedIdentity(ownedCryptoId: currentOwnedCryptoId) }
                    }.padding(.horizontal)
                }
                if allowCreation {
                    OlvidButton(style: .blue,
                                title: Text("CREATE_NEW_OWNED_IDENTITY"),
                                systemIcon: .personCropCircleBadgePlus) {
                        ObvMessengerInternalNotification.userWantsToCreateNewOwnedIdentity
                            .postOnDispatchQueue()
                    }.padding(.horizontal).padding(.bottom)
                }
            }
            .navigationBarTitle("MY_OWN_IDS", displayMode: .inline)
        }
    }
}


/// View showing details about one owned identity.
///
/// We use a internal model to make it possible to have SwiftUI previews
private struct OwnedIdentityItemView: View {
    
    /// View's model that makes it possible to have SwiftUI previews
    final class Model: ObservableObject, Identifiable {
        
        let ownedCryptoId: ObvCryptoId
        let currentOwnedCryptoId: ObvCryptoId
        @Published var title: String
        @Published var subtitle: String
        @Published var badgeCountForDiscussionsTab: Int
        @Published var showGreenShield: Bool
        @Published var showRedShield: Bool
        @Published var showHiddenProfileIcon: Bool
        @Published var circledInitialsConfiguration: CircledInitialsConfiguration
        @Binding var ownedCryptoIdSwitchedTo: ObvCryptoId?
        var id: Data { ownedCryptoId.getIdentity() }
        
        private var cancellable: AnyCancellable?
        
        init(ownedCryptoId: ObvCryptoId, currentOwnedCryptoId: ObvCryptoId, title: String, subtitle: String, badgeCountForDiscussionsTab: Int, showGreenShield: Bool, showRedShield: Bool, showHiddenProfileIcon: Bool, circledInitialsConfiguration: CircledInitialsConfiguration) {
            self.ownedCryptoId = ownedCryptoId
            self.currentOwnedCryptoId = currentOwnedCryptoId
            self.title = title
            self.subtitle = subtitle
            self.badgeCountForDiscussionsTab = badgeCountForDiscussionsTab
            self.showGreenShield = showGreenShield
            self.showRedShield = showRedShield
            self.showHiddenProfileIcon = showHiddenProfileIcon
            self.circledInitialsConfiguration = circledInitialsConfiguration
            self._ownedCryptoIdSwitchedTo = .constant(nil)
        }
        
        convenience init(ownedIdentity: PersistedObvOwnedIdentity, currentOwnedCryptoId: ObvCryptoId, ownedCryptoIdSwitchedTo: Binding<ObvCryptoId?>) {
            self.init(ownedCryptoId: ownedIdentity.cryptoId,
                      currentOwnedCryptoId: currentOwnedCryptoId,
                      title: "",
                      subtitle: "",
                      badgeCountForDiscussionsTab: 0,
                      showGreenShield: false,
                      showRedShield: false,
                      showHiddenProfileIcon: false,
                      circledInitialsConfiguration: ownedIdentity.circledInitialsConfiguration)
            self._ownedCryptoIdSwitchedTo = ownedCryptoIdSwitchedTo
            updateWithOwnedIdentity(ownedIdentity)
            cancellable = ownedIdentity.objectWillChange.sink { [weak self] in
                self?.updateWithOwnedIdentity(ownedIdentity)
            }
        }
        
        private func updateWithOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) {
            if let customDisplayName = ownedIdentity.customDisplayName {
                self.title = customDisplayName
                let name = ownedIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
                let positionAtCompany = ownedIdentity.identityCoreDetails.getDisplayNameWithStyle(.positionAtCompany)
                if positionAtCompany.isEmpty {
                    self.subtitle = name
                } else {
                    self.subtitle = "\(name) (\(positionAtCompany))"
                }
            } else {
                self.title = ownedIdentity.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
                self.subtitle = ownedIdentity.identityCoreDetails.getDisplayNameWithStyle(.positionAtCompany)
            }
            self.badgeCountForDiscussionsTab = ownedIdentity.badgeCountForDiscussionsTab
            self.showGreenShield = ownedIdentity.circledInitialsConfiguration.showGreenShield
            self.showRedShield = ownedIdentity.circledInitialsConfiguration.showRedShield
            self.showHiddenProfileIcon = ownedIdentity.isHidden
            self.circledInitialsConfiguration = ownedIdentity.circledInitialsConfiguration
        }
        
        var showCheckMark: Bool {
            if let ownedCryptoIdSwitchedTo {
                return ownedCryptoIdSwitchedTo == ownedCryptoId
            } else {
                return currentOwnedCryptoId == ownedCryptoId
            }
        }

    }
    
    @ObservedObject var model: Model
    let delegate: OwnedIdentityChooserViewControllerDelegate?
    

    private static let kCircleToTextAreaPadding = CGFloat(8.0)
    private static let animationDurationWhenSwitchingIdentity: Double = 0.3 // In secconds
    
    var body: some View {
        HStack(alignment: .center, spacing: Self.kCircleToTextAreaPadding) {
            CircledInitialsView(configuration: model.circledInitialsConfiguration, size: .medium, style: ObvMessengerSettings.Interface.identityColorStyle)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.title)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                        .lineLimit(1)
                        .font(.system(.headline, design: .rounded))
                    if model.showGreenShield {
                        Image(systemIcon: .checkmarkShieldFill)
                            .foregroundColor(Color(.systemGreen))
                    }
                    if model.showRedShield {
                        Image(systemIcon: .exclamationmarkShieldFill)
                            .foregroundColor(Color(.systemRed))
                    }
                }
                if !model.subtitle.isEmpty {
                    Text(model.subtitle)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(1)
                        .font(.subheadline)
                }
            }
            Spacer()
            if model.showHiddenProfileIcon {
                Image(systemIcon: .eyeSlash)
                    .imageScale(.large)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.adaptiveOlvidBlue))
            }
            if model.showCheckMark {
                Image(systemIcon: .checkmarkCircleFill)
                    .imageScale(.large)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.adaptiveOlvidBlue))
            } else if model.badgeCountForDiscussionsTab > 0 {
                Text(String(model.badgeCountForDiscussionsTab))
                    .foregroundColor(.white)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8.0)
                    .padding(.vertical, 4.0)
                    .background(Capsule().foregroundColor(Color(AppTheme.appleBadgeRedColor)))
            }
        }
        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
        .onTapGesture {
            if model.ownedCryptoId == model.currentOwnedCryptoId {
                Task { await delegate?.userUsedTheOwnedIdentityChooserViewControllerToChoose(ownedCryptoId: model.ownedCryptoId) }
            } else {
                withAnimation(.linear(duration: Self.animationDurationWhenSwitchingIdentity)) {
                    model.ownedCryptoIdSwitchedTo = model.ownedCryptoId
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.animationDurationWhenSwitchingIdentity) {
                    Task { await delegate?.userUsedTheOwnedIdentityChooserViewControllerToChoose(ownedCryptoId: model.ownedCryptoId) }
                }
            }
        }
    }
    
}


// MARK: - Previews

struct OwnedIdentityChooserInnerView_Previews: PreviewProvider {

    private static let identitiesAsURLs: [URL] = [
        URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!,
        URL(string: "https://invitation.olvid.io/#AwAAAHAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVZx8aqikpCe4h3ayCwgKBf-2nDwz-a6vxUo3-ep5azkBUjimUf3J--GXI8WTc2NIysQbw5fxmsY9TpjnDsZMW-AAAAAACEJvYiBXb3Jr")!,
    ]

    private static let ownedCryptoIds = identitiesAsURLs.map({ ObvURLIdentity(urlRepresentation: $0)!.cryptoId })

    private static let ownedCircledInitialsConfigurations = [
        CircledInitialsConfiguration.contact(initial: "S", photoURL: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[0], tintAdjustementMode: .normal),
        CircledInitialsConfiguration.contact(initial: "T", photoURL: nil, showGreenShield: false, showRedShield: false, cryptoId: ownedCryptoIds[1], tintAdjustementMode: .normal),
    ]

    private static let models = [
        OwnedIdentityItemView.Model(
            ownedCryptoId: ownedCryptoIds[0],
            currentOwnedCryptoId: ownedCryptoIds[0],
            title: "Steve Jobs",
            subtitle: "CEO @ Apple",
            badgeCountForDiscussionsTab: 2,
            showGreenShield: false,
            showRedShield: false,
            showHiddenProfileIcon: false,
            circledInitialsConfiguration: ownedCircledInitialsConfigurations[0]),
        OwnedIdentityItemView.Model(
            ownedCryptoId: ownedCryptoIds[1],
            currentOwnedCryptoId: ownedCryptoIds[0],
            title: "Tim Cooks",
            subtitle: "",
            badgeCountForDiscussionsTab: 2,
            showGreenShield: false,
            showRedShield: false,
            showHiddenProfileIcon: false,
            circledInitialsConfiguration: ownedCircledInitialsConfigurations[1]),
    ]

    static var previews: some View {
        Group {
            OwnedIdentityChooserInnerView(currentOwnedCryptoId: ownedCryptoIds[0],
                                          models: models,
                                          delegate: nil)
        }
    }
}
