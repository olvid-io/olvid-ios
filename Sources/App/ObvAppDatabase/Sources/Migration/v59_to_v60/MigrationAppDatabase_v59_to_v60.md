# App database migration from v59 to v60

## PersistedObvOwnedIdentity - Updated entity

+<attribute name="customDisplayName" optional="YES" attributeType="String"/>
+<attribute name="hiddenProfileHash" optional="YES" attributeType="Binary"/>
+<attribute name="hiddenProfileSalt" optional="YES" attributeType="Binary"/>
+<attribute name="numberOfNewMessages" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>

Adds a few attributes that are either optional or have a default value. The numberOfNewMessages attribute is recomputed during bootstrap, so the default value is fine.

## Conclusion

A lightweight migration is sufficient.
