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
import ObvDesignSystem
import ConfettiSwiftUI

@MainActor
protocol AutomaticBackupSuccessfullyActivatedConfirmationViewActionsProtocol: AnyObject {
    func userWantsToDismissAutomaticBackupSuccessfullyActivatedConfirmationView()
}


struct AutomaticBackupSuccessfullyActivatedConfirmationView: View {
    
    let actions: AutomaticBackupSuccessfullyActivatedConfirmationViewActionsProtocol
    
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            VStack {
                CheckMarkImageAnimated()
                    .padding(.bottom)
                Text("AUTOMATIC_BACKUP_SUCCESSFULLY_ACTIVATED")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding()
            Spacer(minLength: 0)
            Button(action: actions.userWantsToDismissAutomaticBackupSuccessfullyActivatedConfirmationView) {
                HStack {
                    Spacer(minLength: 0)
                    Text("OK")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }
}


private struct CheckMarkImageAnimated: View {
    
    @State private var isBadgeVisible: Bool = false
    @State private var triggerConfettiCanon: Int = 0
    
    private let springDuration: CGFloat = 0.4
    
    private func onAppear() {
        Task {
            try? await Task.sleep(seconds: 0.3)
            if #available(iOS 17, *) {
                withAnimation(.spring(duration: springDuration, bounce: 0.4, blendDuration: 0.5)) {
                    isBadgeVisible = true
                } completion: {
                    triggerConfettiCanon += 1
                }
            } else {
                withAnimation(.spring(duration: springDuration, bounce: 0.4, blendDuration: 0.5)) {
                    isBadgeVisible = true
                    triggerConfettiCanon += 1
                }
            }
        }
    }
    
    var body: some View {
        
        Group {
            if isBadgeVisible {
                CheckMarkImage()
                    .transition(.scale.combined(with: .opacity))
            } else {
                CheckMarkImage()
                    .opacity(0)
                    .onAppear(perform: onAppear)
            }
        }
        .confettiCannon(trigger: $triggerConfettiCanon,
                        num: 100,
                        openingAngle: Angle(degrees: 0),
                        closingAngle: Angle(degrees: 360),
                        radius: 200)

    }
    
}


private struct CheckMarkImage: View {
    var body: some View {
        Image(systemIcon: .checkmarkCircleFill)
            .font(.system(size: 96))
            .foregroundStyle(Color(UIColor.systemGreen))
            .background(
                Circle().foregroundStyle(Color(.white))
                    .frame(width: 60, height: 60)
            )
    }
}




// MARK: - Previews

#if DEBUG

private final class ActionsForPreviews: AutomaticBackupSuccessfullyActivatedConfirmationViewActionsProtocol {
    
    func userWantsToDismissAutomaticBackupSuccessfullyActivatedConfirmationView() {
        // Nothing to simulate
    }
    
}

@MainActor
private let actionsForPreviews = ActionsForPreviews()

#Preview {
    AutomaticBackupSuccessfullyActivatedConfirmationView(actions: actionsForPreviews)
}


#endif
