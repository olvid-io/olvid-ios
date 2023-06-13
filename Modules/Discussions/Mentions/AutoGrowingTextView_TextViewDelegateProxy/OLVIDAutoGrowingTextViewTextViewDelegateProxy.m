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

@import UIKit;
@import ObjectiveC;
#import "OLVIDAutoGrowingTextViewTextViewDelegateProxy.h"


@interface OLVIDAutoGrowingTextViewTextViewDelegateProxy ()

@property (nonatomic, class, copy, readonly, direct) NSHashTable <Protocol *> *allowedProtocols;

@property (nonatomic, class, copy, readonly, direct) NSHashTable *allowedDelegationSelectors;

/// A set of `SEL`s that if implemented by `textView` and `textView` returns `NO`, **DOES NOT** forward the method to `textViewDelegate`
@property (nonatomic, class, copy, readonly, direct) NSHashTable *delegationSelectorsThatShouldStopIfTextViewReturnedFalse;

@property (nonatomic, unsafe_unretained, readwrite, direct) UITextView <UITextViewDelegate> *textView;

@property (nonatomic, weak, readwrite, direct) __kindof NSObject <UITextViewDelegate> *textViewDelegate;

@end

@implementation OLVIDAutoGrowingTextViewTextViewDelegateProxy : NSProxy

+ (NSHashTable <Protocol *> *) allowedProtocols
{
    static NSHashTable <Protocol *> *_allowedProtocols = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _allowedProtocols = [NSHashTable weakObjectsHashTable];

        [_allowedProtocols addObject: @protocol(UITextViewDelegate)];

        [_allowedProtocols addObject: @protocol(UIScrollViewDelegate)];
    });

    return _allowedProtocols;
}

+ (NSHashTable *) allowedDelegationSelectors
{
    static NSHashTable *_allowedDelegationSelectors = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _allowedDelegationSelectors = NSCreateHashTable(NSNonOwnedPointerHashCallBacks, 0);

        for (Protocol *aProtocol in [self allowedProtocols])
        {
            unsigned int count;

            struct objc_method_description *methods = protocol_copyMethodDescriptionList(aProtocol, NO, YES, &count);

            for (unsigned int i = 0; i < count; i++)
            {
                SEL methodSelector;

                if ((methodSelector = methods[i].name))
                {
                    NSHashInsertIfAbsent(_allowedDelegationSelectors, methodSelector);
                }
            }

            free(methods);
        }
    });

    return _allowedDelegationSelectors;
}

+ (NSHashTable *) delegationSelectorsThatShouldStopIfTextViewReturnedFalse
{
    static NSHashTable *_delegationSelectorsThatShouldStopIfTextViewReturnedFalse = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _delegationSelectorsThatShouldStopIfTextViewReturnedFalse = NSCreateHashTable(NSNonOwnedPointerHashCallBacks, 0);

        const SEL selectors[] = {
            @selector(textView:shouldChangeTextInRange:replacementText:)
        };

#if DEBUG
        for (NSUInteger i = 0; i < sizeof(selectors) / sizeof(SEL); i++)
        {
            const SEL currentSelector = selectors[i];

            BOOL methodIsDefinedInOneOfTheProtocols = ({
                BOOL _methodIsDefinedInOneOfTheProtocols = NO;

                for (Protocol * __unsafe_unretained aProtocol in [self allowedProtocols])
                {
                    if (_methodIsDefinedInOneOfTheProtocols)
                        break;

                    struct objc_method_description method = protocol_getMethodDescription(aProtocol, currentSelector, NO, YES);

                    if (method.name == NULL && method.types == NULL)
                        continue;

                    NSMethodSignature *methodSignature = [NSMethodSignature signatureWithObjCTypes: method.types];

                    NSAssert(strcmp([methodSignature methodReturnType], @encode(BOOL)) == 0, @"expected method to return a BOOL");

                    _methodIsDefinedInOneOfTheProtocols = YES;
                }

                _methodIsDefinedInOneOfTheProtocols;
            });


            NSAssert(methodIsDefinedInOneOfTheProtocols, @"expected %@ to be defined within one of the protocls", NSStringFromSelector(currentSelector));
        }
#endif

        for (NSUInteger i = 0; i < sizeof(selectors) / sizeof(SEL); i++)
        {
            const SEL currentSelector = selectors[i];

            NSHashInsert(_delegationSelectorsThatShouldStopIfTextViewReturnedFalse, currentSelector);
        }
    });

    return _delegationSelectorsThatShouldStopIfTextViewReturnedFalse;
}

- (instancetype) initWithTextView: (UITextView <UITextViewDelegate> *) textView withTextViewDelegate: (__kindof NSObject <UITextViewDelegate> *) textViewDelegate
{
    if (self)
    {
        _textView = textView;

        _textViewDelegate = textViewDelegate;
    }

    return self;
}

- (BOOL) respondsToSelector: (SEL) aSelector
{
    if (NSHashGet([OLVIDAutoGrowingTextViewTextViewDelegateProxy allowedDelegationSelectors], aSelector) == NULL)
    {
#if DEBUG
//        NSLog(@"🏃⌛️ [AutoGrowingTextView Proxy] replied does not respond to %@", NSStringFromSelector(aSelector));
#endif

        return NO;
    }

    return ([[self textViewDelegate] respondsToSelector: aSelector] ||
            [[self textView] respondsToSelector: aSelector]);
}

- (id) forwardingTargetForSelector: (SEL) aSelector
{
    BOOL bothRespond = ([[self textViewDelegate] respondsToSelector: aSelector] &&
                        [[self textView] respondsToSelector: aSelector]);

    if (bothRespond)
        return self;

    if ([[self textViewDelegate] respondsToSelector: aSelector])
        return [self textViewDelegate];
    else if ([[self textView] respondsToSelector: aSelector])
        return [self textView];

    return nil;
}

- (NSMethodSignature *) methodSignatureForSelector: (SEL) sel
{
    NSMethodSignature *signature;

    if ((signature = [[self textViewDelegate] methodSignatureForSelector: sel]))
        return signature;

    return [[self textView] methodSignatureForSelector: sel];
}

- (void) forwardInvocation: (NSInvocation *) invocation
{
    const SEL currentSelector = [invocation selector];

    if ([[self textView] respondsToSelector: currentSelector])
    {
        [invocation invokeWithTarget: [self textView]];

        if (NSHashGet([OLVIDAutoGrowingTextViewTextViewDelegateProxy delegationSelectorsThatShouldStopIfTextViewReturnedFalse], currentSelector) != NULL) //the return type is a BOOL
        {
            BOOL returnValue;

            [invocation getReturnValue: &returnValue];

            if (!returnValue)
            {
                return;
            }
        }
    }

    if ([[self textViewDelegate] respondsToSelector: currentSelector])
        [invocation invokeWithTarget: [self textViewDelegate]];
}

@end
