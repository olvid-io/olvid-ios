# App database migration from v55 to v56

## DisplayedContactGroup, FyleMessageJoinWithStatus, PersistedDiscussion, PersistedDraft, PersistedDraftFyleJoin, PersistedObvContactIdentity, PersistedObvOwnedIdentity - Modified entities

Adds the permanentUUID attribute, not optional with no default value. Requires a heavyweight migration.

## PersistedMessage

+<attribute name="onChangeFlag" transient="YES" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
+<attribute name="permanentUUID" attributeType="UUID" usesScalarValueType="NO" preserveAfterDeletion="YES"/>

Adds the permanentUUID attribute, not optional with no default value. Requires a heavyweight migration.
The onChangeFlag is transient, it requires no treatment.

## Conclusion

A heavyweight migration is required.
