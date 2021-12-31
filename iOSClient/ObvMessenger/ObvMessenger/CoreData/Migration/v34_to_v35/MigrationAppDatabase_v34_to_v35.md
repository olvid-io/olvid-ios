#  App database migration from v34 to v35

## PersistedDiscussion

+<relationship name="latestSenderSequenceNumbers" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="PersistedLatestDiscussionSenderSequenceNumber" inverseName="discussion" inverseEntity="PersistedLatestDiscussionSenderSequenceNumber"/>

Adding an optional relationship does not prevent a lightweight migration.

## PersistedMessageReceived

+<attribute name="missedMessageCount" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>

Non nillable attribute, but a default value is provided. This does not prevent a lightweight migration.

## PersistedLatestDiscussionSenderSequenceNumber

Adding a new table does not prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient, since we only add a new table.
