# App database migration from v57 to v58

## PersistedDiscussion - Modified entity

+<attribute name="numberOfNewMessages" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>

Adds the numberOfNewMessages attributes, which has a default value. Does not prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient.
