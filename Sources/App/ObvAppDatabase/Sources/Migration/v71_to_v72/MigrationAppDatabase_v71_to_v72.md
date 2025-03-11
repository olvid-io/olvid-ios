# App database migration from v71 to v72

## PersistedDiscussion: Updated entity

+<attribute name="rawLocalDateWhenDiscussionRead" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Optional attribute, does not prevent lightweight migration.

## PersistedMessageReceived: Updated entity

+<attribute name="rawObvMessageSource" attributeType="Integer 16" defaultValueString="0" usesScalarValueType="YES"/>

Mandatory attribute, with a default value. Does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
