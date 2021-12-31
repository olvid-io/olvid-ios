#  App database migration from v35 to v36

## PersistedObvContactIdentity

+<attribute name="isActive" attributeType="Boolean" defaultValueString="YES" usesScalarValueType="YES"/>

Non nillable attribute, but a default value is provided. This does not prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient.
