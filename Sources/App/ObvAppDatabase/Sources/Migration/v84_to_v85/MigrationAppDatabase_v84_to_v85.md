# App database migration from v84 to v85

Everything below serves one thing: an index on the messages, so that building the cell of a message in a long discussion no longer reads
the whole discussion. Each cell asks for its neighbours (`PersistedMessage.getWhatTheMessageAboveSays`): the message above, for the date
separator, and the nearest one from the same sender. On v84, SQLite answered the first by reading every message of the discussion and sorting
them, and the second by reading every received message of the database. On v85, both go through the new index.

## PersistedMessage - Updated entity

```xml
-<entity name="PersistedMessage" representedClassName="PersistedMessage" isAbstract="YES" syncable="YES">
+<entity name="PersistedMessage" representedClassName="PersistedMessage" isAbstract="YES" versionHashModifier="HashModifierForFetchIndexV85" syncable="YES">
```

```xml
+<fetchIndex name="byDiscussionAndSortIndex">
+    <fetchIndexElement property="discussion" type="Binary" order="ascending"/>
+    <fetchIndexElement property="sortIndex" type="Binary" order="ascending"/>
+</fetchIndex>
```

The index covers the discussion of a message and its `sortIndex`, which is what both neighbour queries filter and sort on.

**The index alone would migrate nothing.** A fetch index is not part of an entity's version hash. `DataMigrationManager` compares hashes,
so it would open an existing store as it is, and the index would never be created. The `versionHashModifier` changes the hash of
`PersistedMessage`, and with it the hashes of its three sub-entities, `PersistedMessageReceived`, `PersistedMessageSent` and
`PersistedMessageSystem`. The store then migrates, and the inferred mapping creates the index. The value of the modifier is arbitrary. Like
the rest of a shipped model, it must never change: a store is recognised as a v85 store by these hashes.

The index could not be added to v84 in place: v84 had already shipped to TestFlight.

Nothing else changes. Xcode also moved the relationship `Fyle.allDraftFyleJoinVariants` to another line of the model file; no hash depends
on the order of the lines.

## Conclusion

A lightweight migration is sufficient. No row is changed. Like every step, the migration copies the whole store into a new file, so a user
several versions behind pays one copy per step on their first launch.
