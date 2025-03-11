# App database migration from v65 to v66

## PersistedObvOwnedIdentity - Updated entity

Adds two attributes with default values:
+<attribute name="badgeCountForDiscussionsTab" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
+<attribute name="badgeCountForInvitationsTab" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
This does not prevent lightweight migration.

Removes the numberOfNewMessages attribute.

## Conclusion

A lightweight migration is sufficient.
