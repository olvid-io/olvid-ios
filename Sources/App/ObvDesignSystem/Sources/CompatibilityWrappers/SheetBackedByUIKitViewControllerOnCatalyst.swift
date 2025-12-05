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


@MainActor
public protocol UIKitDelegateForSwiftUISheet: AnyObject {
    func userWantsToPresentView<Content>(_ view: some View, @ViewBuilder content: @escaping () -> Content) async where Content : View
    func userWantsToDismissPresentedView(_ view: some View) async
}

extension View {
    
    ///Presents a modal sheet, adapting its behavior between platforms to ensure reliable dismissal and compatibility.
    ///
    ///- On **iOS** and **iPadOS**, this modifier always uses `.sheet(isPresented:content:)`, leveraging the system's reliable native modal presentation and dismissal logic for nested sheets.
    ///
    ///- On **macCatalyst**, nested `.sheet` presentations can cause modal dismissal issues due to differences between SwiftUI and UIKit/AppKit interoperability.
    ///  To address this, this modifier delegates sheet presentation and dismissal to a `UIKitDelegateForSwiftUISheet` (typically a parent `UIViewController`).
    ///  This delegate is responsible for managing presentation using UIKit, typically by presenting or dismissing a `UIHostingController` hosting the SwiftUI content, ensuring programmatic dismissal always works.
    public func sheetBackedByUIKitViewControllerOnCatalyst<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet, @ViewBuilder content: @escaping () -> Content) -> some View where Content : View {
        #if targetEnvironment(macCatalyst)
        return self.modifier(SheetBackedByUIKitViewControllerOnCatalyst(isPresented: isPresented, onDismiss: onDismiss, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet, presentedContent: content))
        #else
        return self.sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }
    
}


private struct SheetBackedByUIKitViewControllerOnCatalyst<PresentedContent: View>: ViewModifier {
    
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    let presentedContent: () -> PresentedContent
    
    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { isPresented in
                if isPresented {
                    Task { @MainActor in
                        await uiKitDelegateForSwiftUISheet.userWantsToPresentView(content, content: presentedContent)
                    }
                } else {
                    Task { @MainActor in
                        await uiKitDelegateForSwiftUISheet.userWantsToDismissPresentedView(content)
                        onDismiss?()
                    }
                }
            }
    }
    
}
