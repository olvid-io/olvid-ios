# App database migration from v83 to v84

Everything below serves one feature: letting the reader choose, in the composition bar, which of four sizes the photos and videos of a draft
are sent at (Low, Med, Hi, or the original, Max). The smaller files are produced when the attachment is added rather than when the message
is sent: all three at once for a photo, only the chosen one for a video, whose export takes far longer. So each attachment of a draft needs
somewhere to keep several files at once, and the draft needs somewhere to keep the choice.

## PersistedDraftFyleJoinVariant - New entity

```xml
+<entity name="PersistedDraftFyleJoinVariant" representedClassName="PersistedDraftFyleJoinVariant" syncable="YES">
+    <attribute name="byteCount" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
+    <attribute name="fileName" attributeType="String"/>
+    <attribute name="pixelHeight" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
+    <attribute name="pixelWidth" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
+    <attribute name="rawFormat" attributeType="String"/>
+    <attribute name="uti" attributeType="String"/>
+    <relationship name="draftFyleJoin" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="PersistedDraftFyleJoin" inverseName="variants" inverseEntity="PersistedDraftFyleJoin"/>
+    <relationship name="fyle" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Fyle" inverseName="allDraftFyleJoinVariants" inverseEntity="Fyle"/>
+</entity>
```

One row per (attachment of a draft, size): which `Fyle` holds that size, and what it weighs and measures, so the menu can state it without going
to disk. A brand-new entity has no existing rows to map, so it does not prevent a lightweight migration.

`rawFormat` holds the raw value of `ObvMediaFormat` — `"low"`, `"med"`, `"hi"`, `"max"`. Those spellings are persisted here and are therefore
frozen.

## PersistedDraftFyleJoin - Updated entity

```xml
+<relationship name="variants" toMany="YES" deletionRule="Cascade" destinationEntity="PersistedDraftFyleJoinVariant" inverseName="draftFyleJoin" inverseEntity="PersistedDraftFyleJoinVariant"/>
```

Adds one to-many relationship, empty for every existing row. **Cascade**, as `PersistedDraft.unsortedDraftFyleJoins` already is: removing an
attachment from a draft must take its alternative sizes with it, or they are left behind with nothing pointing at them.

The existing `fileName`, `uti` and `fyle` are **not** touched, and keep meaning exactly what they meant: what will be sent and shown.
Choosing a different size rewrites those three from the chosen variant, which is why nothing downstream of a draft — the sent message, the
extended payload, the hardlinks — needed changing.

## Fyle - Updated entity

```xml
+<relationship name="allDraftFyleJoinVariants" toMany="YES" deletionRule="Cascade" destinationEntity="PersistedDraftFyleJoinVariant" inverseName="fyle" inverseEntity="PersistedDraftFyleJoinVariant"/>
```

The inverse of the above, empty for every existing row. **Cascade**, matching its two siblings `allDraftFyleJoins` and
`allFyleMessageJoinWithStatus`.

Note for whoever reads this next: this relationship also had to be added to `Fyle.Predicate.isOrphaned`, which until now asked only whether a
`Fyle` had no message join and no draft join. A transcoded size is referenced by *neither*, so without that third clause every file this
feature produces would be swept by `DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation` — and the Cascade rule above would then
delete the variant row along with it, leaving a menu offering sizes whose files are gone. That is a code change rather than a model change,
but it is inseparable from this one.

## PersistedDraft - Updated entity

```xml
+<attribute name="rawSelectedMediaFormat" optional="YES" attributeType="String"/>
```

Adds one optional attribute, holding the size chosen for this draft's photos and videos. Optional and with no default value, so an existing
draft migrates with a nil value — which the app reads as "this draft has never been asked" and answers with the app-wide default
(`ObvMessengerSettings.Discussions.defaultMediaFormat`), exactly as a draft created after this attribute existed and never touched. Does not
prevent lightweight migration.

## Existing drafts

A draft that survives this migration carries attachments with no variants at all. That is a state the app tolerates rather than one the
migration repairs: the missing sizes are written in the background shortly after the launch that upgrades, and until they exist the draft
sends its attachments exactly as it would have on v83. Once they exist, the draft sends at the app-wide default, Med. Doing it in the
migration instead would mean transcoding every attachment of every draft before the app opens.

## Conclusion

A lightweight migration is sufficient.
