# App database migration from v74 to v75

## PersistedMessageReceived: Updated entity

+<attribute name="dateWhenMessageWasRead" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Added optional attribute, does not prevent lightweight migration. This attribute is set in a lazy fashion after the migration.

## Conclusion

A lightweight migration is sufficient.
