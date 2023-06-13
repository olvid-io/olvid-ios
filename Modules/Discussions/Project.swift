import ProjectDescription
import ProjectDescriptionHelpers

let discussionsMentionsAutoGrowingTextViewTextViewDelegateProxy = Target.objectiveCLibrary(
    name: "Discussions_Mentions_AutoGrowingTextView_TextViewDelegateProxy",
    isExtensionSafe: true,
    sources: "Mentions/AutoGrowingTextView_TextViewDelegateProxy/*.m",
    headers: .onlyHeaders(
        from: "Mentions/AutoGrowingTextView_TextViewDelegateProxy/*.h",
        umbrella: "Mentions/AutoGrowingTextView_TextViewDelegateProxy/Discussions_Mentions_AutoGrowingTextView_TextViewDelegateProxy.h"),
    dependencies: [],
    resources: [])

let discussionsMentionsBuilderInternals = Target.swiftLibrary(
    name: "_Discussions_Mentions_Builder_Internals",
    isExtensionSafe: true,
    sources: "Mentions/Builders/_Internals/*.swift"
)

let discussionsMentionsBuildersShared = Target.swiftLibrary(
    name: "_Discussions_Mentions_Builders_Shared",
    isExtensionSafe: true,
    sources: "Mentions/Builders/Shared/*.swift",
    dependencies: [
        .target(discussionsMentionsBuilderInternals),
        .Modules.obvUICoreData,
        .Modules.Platform.base,
    ]
)

let discussionsMentionsComposeMessageBuilder = Target.swiftLibrary(
    name: "Discussions_Mentions_ComposeMessageBuilder",
    isExtensionSafe: true,
    sources: "Mentions/Builders/ComposeMessageBuilder/*.swift",
    dependencies: [
        .target(discussionsMentionsBuildersShared)
    ]
)

let discussionsMentionsTextBubbleBuilder = Target.swiftLibrary(
    name: "Discussions_Mentions_TextBubbleBuilder",
    isExtensionSafe: true,
    sources: "Mentions/Builders/TextBubbleBuilder/*.swift",
    dependencies: [
        .target(discussionsMentionsBuildersShared)
    ]
)

let discussionsScrollToBottomButton = Target.swiftLibrary(
    name: "Discussions_ScrollToBottomButton",
    isExtensionSafe: true,
    sources: "ScrollToBottomButton/*.swift",
    dependencies: [
        .Modules.UI.systemIcon,
        .Modules.UI.systemIconUIKit
    ],
    resources: [])

let discussionsAttachmentsDropView = Target.swiftLibrary(
    name: "Discussions_AttachmentsDropView",
    isExtensionSafe: true,
    sources: "AttachmentsDropView/*.swift",
    dependencies: [
        .Modules.Platform.sequenceKeyPathSorting,
        .Modules.Platform.nsItemProviderUTTypeBackport,
        .Modules.UI.systemIcon,
        .Modules.UI.systemIconUIKit,
    ],
    resources: [
        "AttachmentsDropView/*.lproj/Localizable.strings"
    ])

let project = Project.createProject(name: "Discussions",
                                    packages: [],
                                    targets: [discussionsMentionsAutoGrowingTextViewTextViewDelegateProxy,
                                              discussionsMentionsBuildersShared,
                                              discussionsMentionsBuilderInternals,
                                              discussionsMentionsComposeMessageBuilder,
                                              discussionsMentionsTextBubbleBuilder,
                                              discussionsScrollToBottomButton,
                                              discussionsAttachmentsDropView],
                                    shouldEnableDefaultResourceSynthesizers: true)

