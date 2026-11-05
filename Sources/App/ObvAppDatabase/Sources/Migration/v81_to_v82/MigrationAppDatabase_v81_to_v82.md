# App database migration from v81 to v82

## PersistedGroupV2Member - Updated entity

+<attribute name="rawDateBackToPending" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Adds one optional attribute. Does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
