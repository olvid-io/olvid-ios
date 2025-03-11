#  Engine database migration from v57 to v58

## KeycloakServer: Updated entity

+<attribute name="isTransferRestricted" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

Adds a mandatory attribute with a default value. Does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
