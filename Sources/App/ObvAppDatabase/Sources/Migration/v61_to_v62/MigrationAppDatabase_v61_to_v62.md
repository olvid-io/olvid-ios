# App database migration from v61 to v62

## PersistedDiscussion - Updated entity

+<attribute name="pinnedSectionKeyPath" attributeType="String" defaultValueString="0"/>
+<attribute name="rawPinnedIndex" optional="YES" attributeType="Integer 64" usesScalarValueType="YES"/>

Adds two attribute, one with a default value, the other is optional. This does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
