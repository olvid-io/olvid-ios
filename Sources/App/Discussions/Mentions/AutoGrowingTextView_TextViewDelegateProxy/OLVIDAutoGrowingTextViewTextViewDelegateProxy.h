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

@import Foundation;
@import UIKit.UITextView;

NS_HEADER_AUDIT_BEGIN(nullability, sendability)

__attribute__((objc_subclassing_restricted))
NS_SWIFT_NAME(AutoGrowingTextViewTextViewDelegateProxy)
/// A proxy that acts like a middleman to intercept and forward `UITextViewDelegate` methods to both a given instance of `UITextView` and its real delegate
/// The sole purpose of this proxying is to mitigate an issue within `UITextInput` where `-[UITextInput shouldChangeTextInRange:replacementText:]` wasn't called
///
/// This class makes use of the Objective-C runtime to load the appropriate protocol methods and discover them at runtime, making this resilient to API changes
///
/// - Remark: The `textView` will be the first to receive the delegate methods
/// - Important: The `textView` is **not** retained and is unowned (`unowned` in Swift, `unsafe_unretained` in ObjC) to prevent a retain cycle. This object **should** be retained by `textView`
@interface OLVIDAutoGrowingTextViewTextViewDelegateProxy : NSProxy <UITextViewDelegate>

/// Designated initializer to create the proxy
/// - Parameters:
///   - textView: An instance of `UITextView` that conforms to `UITextViewDelegate`
///   - textViewDelegate: The `textView`'s actual delegate
- (instancetype) initWithTextView: (UITextView <UITextViewDelegate> *) textView withTextViewDelegate: (__kindof NSObject <UITextViewDelegate> *) textViewDelegate;

/// An instance of `UITextView` that conforms to `UITextViewDelegate`
@property (nonatomic, unsafe_unretained, readonly, direct) UITextView <UITextViewDelegate> *textView;

/// The actual delegate of `textView`
@property (nonatomic, weak, readonly, nullable, direct) __kindof NSObject <UITextViewDelegate> *textViewDelegate;

@end

NS_HEADER_AUDIT_END(nullability, sendability)
