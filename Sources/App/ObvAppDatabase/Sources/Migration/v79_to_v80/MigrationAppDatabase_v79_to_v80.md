# App database migration from v79 to v80

## PersistedMessageReceived

+<attribute name="messageUploadTimestampFromServer" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Adds an optional attribute. Does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
