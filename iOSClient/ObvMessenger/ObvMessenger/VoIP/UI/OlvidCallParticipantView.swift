/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import SwiftUI
import ObvTypes
import UI_ObvCircledInitials


protocol OlvidCallParticipantViewModelProtocol: ObservableObject, Identifiable, InitialCircleViewNewModelProtocol {
    var displayName: String { get }
    var stateLocalizedDescription: String { get }
    var contactIsMuted: Bool { get }
    var cryptoId: ObvCryptoId { get }
}


protocol OlvidCallParticipantViewActionsProtocol {
    func userWantsToRemoveParticipant(cryptoId: ObvCryptoId) async throws
}

/// Encapsulates view parameters that cannot be easily implemented at the model level (i.e., by an `OlvidCallParticipant`, that will implement `OlvidCallParticipantViewModelProtocol`)
/// but that can easily be computed par the `OlvidCallView`.
struct OlvidCallParticipantViewState {
    let showRemoveParticipantButton: Bool
}


// MARK: - OlvidCallParticipantView

struct OlvidCallParticipantView<Model: OlvidCallParticipantViewModelProtocol>: View {
        
    @ObservedObject var model: Model
    let state: OlvidCallParticipantViewState
    let actions: OlvidCallParticipantViewActionsProtocol
    
    
    private func userWantsToRemoveParticipant() {
        Task {
            do {
                try await actions.userWantsToRemoveParticipant(cryptoId: model.cryptoId)
            } catch {
                assertionFailure()
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            InitialCircleViewNew(model: model, state: .init(circleDiameter: 70))
                .overlay(alignment: .topTrailing) {
                    MuteView()
                        .opacity(model.contactIsMuted ? 1.0 : 0.0)
                }
            VStack(alignment: .leading) {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(verbatim: model.displayName)
                        .font(.title)
                        .fontWeight(.heavy)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                Text(verbatim: model.stateLocalizedDescription)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            if state.showRemoveParticipantButton {
                Button(action: userWantsToRemoveParticipant) {
                    Image(systemIcon: .minusCircleFill)
                        .foregroundStyle(Color(UIColor.systemRed))
                        .background(Color(.white).clipShape(Circle()).padding(4))
                        .font(.system(size: 24))
                }.padding(.leading, 4)
            }
        }
    }
    
    
}


// MARK: - Small mute icon shown when the participant is muted

private struct MuteView: View {
    var body: some View {
        Image(systemIcon: .micSlashFill)
            .foregroundStyle(Color(UIColor.white))
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 24, height: 24)
            .background(Color(UIColor.systemRed))
            .clipShape(Circle())
    }
}



// MARK: - Previews

struct OlvidCallParticipantView_Previews: PreviewProvider {
    
    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
    private static let contactCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!)

    private final class ModelForPreviews: OlvidCallParticipantViewModelProtocol {
        
        var cryptoId: ObvTypes.ObvCryptoId { contactCryptoId }
        
        var circledInitialsConfiguration: CircledInitialsConfiguration {
            .contact(initial: "S",
                     photo: nil,
                     showGreenShield: false,
                     showRedShield: false,
                     cryptoId: contactCryptoId,
                     tintAdjustementMode: .normal)
        }
        
        var displayName: String {
            "Steve Jobs"
        }
        
        var stateLocalizedDescription: String {
            "Some description"
        }
                
        @Published var contactIsMuted: Bool = false
        
        var uuidForCallKit: UUID { UUID() }
        
    }
    
    
    private final class ActionsForPreviews: OlvidCallParticipantViewActionsProtocol {
        func userWantsToRemoveParticipant(cryptoId: ObvCryptoId) async throws {}
    }
    
    private static let model = ModelForPreviews()
    private static let actions = ActionsForPreviews()
    private static let state = OlvidCallParticipantViewState(
        showRemoveParticipantButton: true)

    static var previews: some View {
        OlvidCallParticipantView(model: model, state: state, actions: actions)
    }
    
}
