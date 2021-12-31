APP DATABASE
------------

In production: v30
In development: v31

----
PersistedMessageSystem

+<relationship name="optionalCallLogItem" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="PersistedCallLogItem" inverseName="messageSystem" inverseEntity="PersistedCallLogItem"/>

The values of enum rawCategory has been changed
From
    enum Category: Int, CustomStringConvertible, CaseIterable {
        case contactJoinedGroup = 0
        case contactLeftGroup = 1
        case numberOfNewMessages = 2
        case discussionIsEndToEndEncrypted = 3
        case contactWasDeleted = 4
        case missedIncomingCall = 5
        case updatedDiscussionSharedSettings = 6
        case discutionWasRemotelyWiped = 7
        case acceptedIncomingCall = 8
        case acceptedOutgoingCall = 9
        case rejectedIncomingCall = 10
        case rejectedOutgoingCall = 11
        case busyOutgoingCall = 12
        case unansweredOutgoingCall = 13
        case uncompletedOutgoingCall = 14
To:
    enum Category: Int, CustomStringConvertible, CaseIterable {
        case contactJoinedGroup = 0
        case contactLeftGroup = 1
        case numberOfNewMessages = 2
        case discussionIsEndToEndEncrypted = 3
        case contactWasDeleted = 4
        case callLogItem = 5
        case updatedDiscussionSharedSettings = 6
        case discutionWasRemotelyWiped = 7

Category [5] + [8...14] should be changed to 5 (callLogItem), a new PersistedCallLogItem should be created with one PersistedCallLogContact with that is the current 1to1 discussion contact.

----
PersistedObvContactIdentity
+<relationship name="callLogContact" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="PersistedCallLogContact" inverseName="contactIdentity" inverseEntity="PersistedCallLogContact"/>
This relationship will be populated during the migration of the PersistedMessageSystem entries.

----
PersistedCallLogContact

New table

----
PersistedCallLogItem

New table
