There is no explicit migration from v21 to v22. The "only" change was to add a few preserveAfterDeletion to OutboxMessage and OutboxAttachment, so as to keep certain values after deletion. The objective was to re-play certain notifications from the Engine, to the App, within the main app even though the (outbox) message was delete by the share extension.

We had to revert those changes due to migration issues. It seems that the way Xcode Version 11.5 (11E608c) computes the "hash value" of an Entity is flawed when creating an .xcmappingmodel file: activating the preserveAfterDeletion does *not* change the hash value, although it should. On the contrary, when looking for an appropriate migration file, the migration procedure computes the "hashes" of all entities of the source model (as currently written on disk, in the database) and of the destination model. In our case we wanted to migrate from v21 (without preserveAfterDeletion) to v22 (with a few preserveAfterDeletion). During the migration procedure, the .xcmappingmodel we had created was never found, because the hash remained constant on both side of the mapping, although this hash should have been different on the rhs of the mapping for both OutboxMessage and OutboxAttachment. As a result, the hashes of the rhs of the mapping did not match the hashes of the destination model, because of the hashes of OutboxMessage and OutboxAttachment did not match.

Because a few TestFlight users did migrate from v21 to v22 (using lightweight migration), we decided to remove the preserveAfterDeletion from v23, and to specify the following migration procedure :

v21 -> v23 : (skipping the v22) using a specific .xcmappingmodel, required due to the multiple changes v21 and v23
v22 -> v21 : going back, using lightweight migration (only used for TestFlight users)
v21 -> v22 : deleted (used to be a lightweight migration), replaced by v21 -> v23.

