# App database migration from v64 to v65

## New Entities

### `PersistedUserMention`

### `PersistedUserMentionInDraft`

A concrete implementation of `PersistedUserMention`.

### `PersistedUserMentionInMessage`

A concrete implementation of `PersistedUserMention`.


## Edited Entities

### `PersistedDiscussion`

- Added `aNewReceivedMessageDoesMentionOwnedIdentity` attribute
    - Boolean value with a default value, does not prevent lightweight migration.

### `PersistedDiscussionLocalConfiguration`

- Added `rawDoNotifyWhenMentionnedInMutedDiscussion` attribute
	- Represents the user’s notification mode regarding mentions. This attribute is optional and does not prevent lightweight migration.

### `PersistedDraft`

- Added `mentions` inverse to-many relationship to `PersistedUserMentionInDraft`, with a cascade delete rule. During a lightweight migration, this set will be set to the empty set.

### `PersistedMessage`

- Added `doesMentionOwnedIdentity` attribute with a default value.
- Added `mentions` inverse to-many relationship to `PersistedUserMentionInMessage`, with a cascade delete rule. During a lightweight migration, this set will be set to the empty set.


## Conclusion

A lightweight migration is sufficient.
