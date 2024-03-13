#  Engine database migration from v50 to v51

## InboxMessage: Updated entity

+<attribute name="markedAsListedOnServer" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

The added attribute has a default value. This change does prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient.
