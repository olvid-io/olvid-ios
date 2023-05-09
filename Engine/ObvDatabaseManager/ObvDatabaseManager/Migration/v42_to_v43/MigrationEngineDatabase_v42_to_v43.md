#  Engine database migration from v42 to v43

## OwnedIdentity

+<attribute name="isDeletionInProgress" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

Adds an attribute with a default value that is fine. Does not prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient.
