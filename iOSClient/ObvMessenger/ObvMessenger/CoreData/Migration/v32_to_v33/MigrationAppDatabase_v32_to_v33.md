#  App database migration from v32 to v33

## PersistedMessageTimestampedMetadata

We drop the messageObjectURI column. The reason is that there is *no* guarantee that this URI makes still sense after a migration, a fact that was unclear at the time this table was created.
As a consequence, we also drop the uniqueness constraint and deal with the fact that there might be many metadatas of the same kind for a single message. This is better anyway.

## RemoteDeleteAndEditRequest

Similar situation than the previous one.

## Conclusion


A lightweight migration is sufficient, since we are only dropping columns here.
