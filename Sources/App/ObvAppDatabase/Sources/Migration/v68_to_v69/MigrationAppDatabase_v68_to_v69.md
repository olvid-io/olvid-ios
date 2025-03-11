# App database migration from v68 to v69

## PersistedGroupV2 - Updated entity

+<attribute name="serializedGroupType" optional="YES" attributeType="Binary"/>

Adds an optional attribute, this does not prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient.
