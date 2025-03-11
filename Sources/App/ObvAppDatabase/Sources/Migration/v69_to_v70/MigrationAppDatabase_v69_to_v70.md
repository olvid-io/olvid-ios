# App database migration from v69 to v70

## PersistedObvContactDevice: Updated entity

+<attribute name="rawPreKeyAvailable" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

Mandatory attribute with a default value, this does not prevent lightweight migration.

## PersistedObvContactIdentity: Updated entity

+<attribute name="rawWasRecentlyOnline" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>

Mandatory attribute with a default value, this does not prevent lightweight migration.

## PersistedObvOwnedDevice: Updated entity

+<attribute name="rawPreKeyAvailable" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

Mandatory attribute with a default value, this does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
