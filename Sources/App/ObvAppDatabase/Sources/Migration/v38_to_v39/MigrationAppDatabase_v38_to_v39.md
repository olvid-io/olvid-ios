# App database migration from v38 to v39

## PendingRepliedTo - New Entity

Nothing to do in particular, we use this new entity during the migration of the messages.

## PersistedMessage - Modified entity

The optional rawReplyToJSON attribute is removed. During the migration, we should do the following, for each message, if rawReplyToJSON is nil, store its values in memory until the last phase of the migration (when we know all entities and relations are set). In the last phase, for each stored values, look for the message they reference. If found, set the reply <-> replied message relation. If not found, create a PendingRepliedTo instance if the reply is a received message.
