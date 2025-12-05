#  Engine database migration from v64 to v65

## ContactGroupV2: Updated entity

+<attribute name="groupVersionOfDetailsTrustedOnAnotherOwnedDevice" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>

Added mandatory attribute, with a default value. Does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
