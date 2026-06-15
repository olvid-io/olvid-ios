/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvAppTypes

@available(iOS 26.0, *)
public struct ComposeMentionTextFormattingDefinition: AttributedTextFormattingDefinition {
    
    public typealias Scope = AttributeScopes.OlvidMentionsOnly
    
    public init() {}
    
    public var body: some AttributedTextFormattingDefinition<Scope> {
        MentionColorConstraint()
        MentionFontConstraint() 
    }
}

/// Constraint that applies colors based on text patterns
@available(iOS 26.0, *)
struct MentionColorConstraint: AttributedTextValueConstraint {
  typealias Scope = AttributeScopes.OlvidMentionsOnly
  typealias AttributeKey = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
  
  func constrain(_ container: inout Attributes) {
      if container.mention != nil {
          container.foregroundColor = .blue
      } else {
          container.foregroundColor = .primary
      }
  }
}

/// Constraint that applies font based on text patterns
@available(iOS 26.0, *)
struct MentionFontConstraint: AttributedTextValueConstraint {
  typealias Scope = AttributeScopes.OlvidMentionsOnly
  typealias AttributeKey = AttributeScopes.SwiftUIAttributes.FontAttribute
  
  func constrain(_ container: inout Attributes) {
      if container.mention != nil {
          container.font = .body.bold()
      } else {
          container.font = .body
      }
  }
}
