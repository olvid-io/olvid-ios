# App database migration from v44 to v45

## PersistedContactGroup

Changes the deletion rule of the discussion relationship from "Cascade" to "Nullify".

## PersistedObvContactIdentity

Changes the deletion rule of the rawOneToOneDiscussion relationship from "Cascade" to "Nullify".

## PersistedDiscussion

New rawStatus attribute with a default value that is always appropriate when migrating non-locked discussions, but never for locked discussions. Locked discussions require a special treatement anyway.

## PersistedDiscussionGroupLocked and PersistedDiscussionOneToOneLocked

Deleted entities that must be mapped to PersistedGroupDiscussion and PersistedOneToOneDiscussion respectively, with an appropriate "locked" status.

## PersistedGroupDiscussion

The contactGroup relationship was renamed to rawContactGroup.
Two new attributes rawGroupUID and rawOwnerIdentityIdentity that are optionals and that we cannot infer during migration, so they will stay nil.

## PersistedOneToOneDiscussion

The contactIdentity relationship is renamed as rawContactIdentity.
New attribute rawContactIdentityIdentity that is optional but that can be set using the rawContactIdentity relationship.

## Conclusion

The heavyweight migration is required.
