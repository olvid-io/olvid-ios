# App database migration from v42 to v43

## PersistedInvitationOneToOneInvitationSent - New entity

Does not prevent lightweight migration.

## PersistedObvContactIdentity - Modified entity

Adds three attributes (capabilityGroupsV2, capabilityOneToOneContacts, isOneToOne), but the isOneToOne must be set to true during the migration although its default value is false.
We need a heavyweight migration.

The oneToOneDiscussion relationship is renamed rawOneToOneDiscussion

## PersistedObvOwnedIdentity - Modified entity

Adds two attributes (capabilityGroupsV2, capabilityOneToOneContacts).

## PersistedOneToOneDiscussion - Modified entity

The deletion rule of the contactIdentity relationship changes, nothing to do during migration.

## Conclusion

A heavyweight migration is required
