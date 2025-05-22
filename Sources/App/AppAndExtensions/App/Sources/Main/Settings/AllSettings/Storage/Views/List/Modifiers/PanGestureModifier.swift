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

struct PanGestureModifier: ViewModifier {
    
    @Binding var panGesture: UIPanGestureRecognizer?
    var panIsEnabled: Bool
    
    var onGestureChange: ((UIPanGestureRecognizer) -> Void)?
    var onGestureEnded: ((UIPanGestureRecognizer) -> Void)?
    
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.gesture(
                PanGesture { gesture in
                    if panGesture == nil {
                        panGesture = gesture
                        gesture.isEnabled = panIsEnabled
                    }
                    
                    let state = gesture.state
                    if state == .began || state == .changed {
                        onGestureChange?(gesture)
                    } else {
                        onGestureEnded?(gesture)
                    }
                }
            )
        } else {
            content
        }
    }
}

extension View {
    
    func panGesture(panGesture: Binding<UIPanGestureRecognizer?>,
                    panIsEnabled: Bool,
                    onGestureChange: ((UIPanGestureRecognizer) -> Void)?,
                    onGestureEnded: ((UIPanGestureRecognizer) -> Void)?) -> some View {
        modifier(PanGestureModifier(panGesture: panGesture,
                                    panIsEnabled: panIsEnabled,
                                    onGestureChange: onGestureChange,
                                    onGestureEnded: onGestureEnded))
    }
}

/// Custom UIKit Gesture
struct PanGesture: UIGestureRecognizerRepresentable {
    
    var handle: (UIPanGestureRecognizer) -> ()
    
    func makeUIGestureRecognizer(context: Context) -> some UIGestureRecognizer {
        return UIPanGestureRecognizer()
    }
    
    func handleUIGestureRecognizerAction(_ recognizer: UIGestureRecognizerType, context: Context) {
        if let panRecognizer = recognizer as? UIPanGestureRecognizer {
            handle(panRecognizer)
        }
    }
    
    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) { }
}

