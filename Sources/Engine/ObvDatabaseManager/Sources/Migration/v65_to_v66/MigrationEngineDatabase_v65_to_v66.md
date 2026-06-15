#  Engine database migration from v65 to v66

## KeycloakServer: Updated entity

+<attribute name="supportsIdBasedAuth" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

Added mandatory attribute, with a default value. Does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
