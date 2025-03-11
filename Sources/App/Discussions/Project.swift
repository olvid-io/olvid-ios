import ProjectDescription
import ProjectDescriptionHelpers

let discussionsMentionsAutoGrowingTextViewTextViewDelegateProxy = Target.makeObjectiveCLibraryTarget(
    name: "Discussions_Mentions_AutoGrowingTextView_TextViewDelegateProxy",
    sources: "Mentions/AutoGrowingTextView_TextViewDelegateProxy/*.m",
    headers: .onlyHeaders(
        from: "Mentions/AutoGrowingTextView_TextViewDelegateProxy/*.h",
        umbrella: "Mentions/AutoGrowingTextView_TextViewDelegateProxy/Discussions_Mentions_AutoGrowingTextView_TextViewDelegateProxy.h"),
    dependencies: [],
    isExtensionSafe: true)

let discussionsMentionsBuilderInternals = Target.makeSwiftLibraryTarget(
    name: "_Discussions_Mentions_Builder_Internals",
    sources: "Mentions/Builders/_Internals/*.swift",
    resources: nil,
    dependencies: [],
    isExtensionSafe: true)

let discussionsMentionsBuildersShared = Target.makeSwiftLibraryTarget(
    name: "_Discussions_Mentions_Builders_Shared",
    sources: "Mentions/Builders/Shared/*.swift",
    resources: nil,
    dependencies: [
        .target(discussionsMentionsBuilderInternals),
        .Olvid.App.obvUICoreData,
        .Olvid.App.Platform.base,
    ],
    isExtensionSafe: true)

let discussionsMentionsComposeMessageBuilder = Target.makeSwiftLibraryTarget(
    name: "Discussions_Mentions_ComposeMessageBuilder",
    sources: "Mentions/Builders/ComposeMessageBuilder/*.swift",
    resources: nil,
    dependencies: [
        .target(discussionsMentionsBuildersShared)
    ],
    isExtensionSafe: true)

let discussionsScrollToBottomButton = Target.makeSwiftLibraryTarget(
    name: "ObvDiscussionsScrollToBottomButton",
    sources: "ScrollToBottomButton/*.swift",
    resources: nil,
    dependencies: [
        .Olvid.App.obvSystemIcon,
    ],
    isExtensionSafe: true)

let project = Project.createProjectForFrameworkLegacy(name: "Discussions",
                                                      targets: [
                                                        discussionsMentionsAutoGrowingTextViewTextViewDelegateProxy,
                                                        discussionsMentionsBuildersShared,
                                                        discussionsMentionsBuilderInternals,
                                                        discussionsMentionsComposeMessageBuilder,
                                                        discussionsScrollToBottomButton,
                                                      ])
