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


/// Attributes necesssary to conform to the `ObvAccessibilityProvidableView` protocol.
///
/// Provide as much information as possible so that Apple assitive technologies work properly.
/// For static (part of) strings, make sure to localize the content.
/// Please note : by default, actions coming from child accessibility elements are automatically applied to the parent, unlike labels.
/// This struct is not exhaustive on accessibility attributes you can apply on an element.
///
/// - For extensive documentation regarding accessibility view modifiers, see: [Accessibility modifiers](https://developer.apple.com/documentation/swiftui/view-accessibility)
/// - For general accessibility considerations and Apple guidelines, see: [Accessibility](https://developer.apple.com/documentation/Accessibility)
public struct ObvAccessibilityAttributes {
    
    /// String describing the object (e.g. "Message").
    let label: String
    
    /// String describing the value or content of the object (e.g. "From Ada : Hi ! How are you ? Received yesterday, 13:08.").
    let value: String?
    
    /// Array of labeled actions that can be taken by the user on this element (e.g. ["Reply": replyToMessage, "React": reactToMessage]). If no action is given, children accessibility elements' actions are used.
    let actions: [String : () -> Void]?
    
    /// Additional information or context provided to the user if they ask to. (e.g. "Message from Ada, received yesterday in the group Acessibility Guidelines.").
    let hint: String?
    
    /// Array of the accessibility traits. (e.g. [.isButton, .isImage]
    let traits: [AccessibilityTraits]?
    
    /// Behavior for how child accessibility elements are treated. We typically want to ignore them, if so keep the default value.
    let childBehavior: AccessibilityChildBehavior
    
    public init(label: String, value: String?, actions: [String : () -> Void]?, hint: String?, traits: [AccessibilityTraits]?, childBehavior: AccessibilityChildBehavior = .ignore) {
        self.label = label
        self.actions = actions
        self.hint = hint
        self.value = value
        self.traits = traits
        self.childBehavior = childBehavior
    }
}


/// A view that is can be made accessible using the `ObvAccessibleComponent` wrapper or the `accessibleComponent()` modifier.
///
/// Views that conform to this protocol should only be "atomic" accessible elements, i.e. objects that will be accessed as one element in the accesible user interface (e.g. a discussion cell or a message).
/// This is typically used on inner views, whose parent then call `.accessibleComponent()` or its ViewBuilder equivalent `ObvAccessibleComponent { content }` so that the view handed publicly is immediately accessible.
/// A good practice is storing the `ObvAccessibilityAttributes` in the view model if there is one, which will be passed to the InnerView.
public protocol ObvAccessibilityProvidableView: View {
    var accessibilityAttributes: ObvAccessibilityAttributes { get }
}


public extension View where Self: ObvAccessibilityProvidableView {
    
    /// Drops all children accessibility elements and their attributes (except actions) and applies on the view all the accessibility information provided in the `ObvAccessibilityAttributes` required to conform to `ObvAccessibilityProvidable`.
    /// Can either be used as a view modifier with this method, or as a ViewBuilder Wrapper with `ObvAccessibleComponent { content }`
    func obvAccessibleComponent() -> some View {
        ObvAccessibleComponent {
            self
        }
    }
}

/// Wrapper used on views conforming to the `ObvAccessibilityProvidableView` protocol to make them accessible using the `obvAccessibleComponent()` view modifier.
public struct ObvAccessibleComponent<Content: ObvAccessibilityProvidableView>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content.obvAccessibleComponent(accessibilityAttributes: content.accessibilityAttributes)
    }
}


public extension View {
    
    /// In general, we recommend not to use this view modifier, but rather to conform to `ObvAccessibilityProvidableView` to get the `obvAccessibleComponent()` view modifier (with no argument) as it makes the code more readable.
    /// Drops all children accessibility elements and their attributes (except actions) and applies on the view all the accessibility information provided in the `ObvAccessibilityAttributes`.
    func obvAccessibleComponent(accessibilityAttributes: ObvAccessibilityAttributes) -> some View {
        var view = self
            .accessibilityElement(children: accessibilityAttributes.childBehavior)
            .accessibilityLabel(Text(accessibilityAttributes.label))
        
        if let hint = accessibilityAttributes.hint {
            view = view.accessibilityHint(Text(hint))
        }
        
        if let actions = accessibilityAttributes.actions {
            for (name, action) in actions {
                view = view.accessibilityAction(named: Text(name), action)
            }
        }
        
        if let value = accessibilityAttributes.value {
            view = view.accessibilityValue(Text(value))
        }
        
        return view
    }
    
}



#if DEBUG

// MARK: - Examples


/// Some view model containing some text to be displayed.
struct VeryNiceViewModel {
    
    /// Some text that will be shown in the view.
    let textToBeShown: String
    
    /// We typically want the accessibility attributes to be stored in the view model. This allows us to treat any string computing or case disjuction outisde the view.
    var accessibilityAttributes: ObvAccessibilityAttributes {
        .init(label: "VERY_NICE_TEXT_IS", value: textToBeShown, actions: nil, hint: nil, traits: [.isStaticText])
    }
    
}

/// Some view containing some text.
struct VeryNiceView: View {
    
    let model: VeryNiceViewModel
    
    /// In the codebase, we often have this pattern with an InnerView that has a onAppear. This pattern now has a new utility as the InnerView is required to apply the wrapper before exposing the view publicly.
    let onAppear: () -> Void = {}
    
    var body: some View {
        ObvAccessibleComponent {
            VeryNiceInnerView(model: model)
        }
        .onAppear(perform: onAppear)
    }
    
}


/// Some inner view. This is required to apply the view modifier or wrapper on it, before exposing the view publicly. If you really want not to use an InnerView, you can use the .obvAccessibleComponent(accessibilityAttributes: ObvAccessibilityAttributes) view modifier and pass in directly the accessibility attributes.
fileprivate struct VeryNiceInnerView : ObvAccessibilityProvidableView {
    
    let model: VeryNiceViewModel
    var accessibilityAttributes: ObvAccessibilityAttributes { model.accessibilityAttributes }
    
    var body: some View {
        Text("TITLE")
        Text(model.textToBeShown)
    }
    
}

/// Please note having your views wrapped in `ObvAccessibleComponent` does'nt do *all* the job. Supplementary work like grouping these elements or ordering them as intended in the design are still needed from you at the top level of you view.
fileprivate struct SomeOtherVeryNiceView: View {
    
    let modelOne: VeryNiceViewModel
    let modelTwo: VeryNiceViewModel
    let modelThree: VeryNiceViewModel
    
    var body: some View {
        
        HStack {
            VeryNiceView(model: modelTwo)
            VeryNiceView(model: modelThree)
        }
        .accessibilityElement(children: .combine)
        .accessibilitySortPriority(0)
        
        VeryNiceView(model: modelOne)
            .accessibilitySortPriority(1)
    }
}


#endif
