# App database migration from v70 to v71

## PersistedDiscussion: Updated entity

+<attribute name="rawServerTimestampWhenDiscussionReadOnAnotherOwnedDevice" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Optional attribute, that can be nil while the app is running. Does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
