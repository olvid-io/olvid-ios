# App database migration from v72 to v73

## PersistedDiscussion: Updated entity

+<attribute name="serverTimestampOfLastRemoteDeletion" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Optional attribute, does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
