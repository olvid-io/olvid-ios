Trivial migration: the only change is that deleting a discussion now cascade deletes all its messages.
IMPORTANT: trying to migrate the store creates a bug: the lightweight migration seems to consider that both models are identical and thus, no migration is performed. As a result, the identifier of the store does not change and the migration loops forever. So we decided to force a migration from 21 to 23 directly.
In the end, the version 22 of the model did not go into production. The users migrated directely from v21 to v23 using a heavyweight migration.
