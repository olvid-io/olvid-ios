# App database migration from v49 to v50

## DisplayedContactGroup - New entity

For each PersistedContactGroup, we should create an DisplayedContactGroup instance. To do so, we will add a special migration policy PersistedContactGroupToDisplayedContactGroup.
We should also set the 'displayedContactGroup' inverse relationship of the 'PersistedContactGroup' instances.

## PersistedCallLogItem - Modified entity

Adds an optional 'groupV2Identifier' attribute, nothing to do here.

## PersistedContactGroup - Modified entity

Adds a 'displayedContactGroup' relationship. Its value will be set during the creation of the 'DisplayedContactGroup' entities.

## PersistedObvContactIdentity - Modified entity

Adds a 'asGroupV2Member' to-many relationship. Nothing to do here.

## PersistedObvOwnedIdentity - Modified entity

Adds a 'contactGroupsV2' to-many relationship. Nothing to do here.

## PersistedGroupV2, PersistedGroupV2Details, PersistedGroupV2Discussion, PersistedGroupV2Member - New entities

Nothing to do here

## Conclusion

A heavyweight migration is required but a mapping file is sufficient.

