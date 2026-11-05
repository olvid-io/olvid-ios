#  Engine database migration from v69 to v70

## PreKeySignatureReceived: New entity

+<entity name="PreKeySignatureReceived" representedClassName="PreKeySignatureReceived" syncable="YES">
+    <attribute name="rawPreKeyId" attributeType="Binary"/>
+    <attribute name="signature" attributeType="Binary"/>
+    <relationship name="preKey" maxCount="1" deletionRule="Nullify" destinationEntity="PreKeyForCurrentOwnedDevice" inverseName="signaturesReceived" inverseEntity="PreKeyForCurrentOwnedDevice"/>
+    <uniquenessConstraints>
+        <uniquenessConstraint>
+            <constraint value="rawPreKeyId"/>
+            <constraint value="signature"/>
+        </uniquenessConstraint>
+    </uniquenessConstraints>
+</entity>

New entity. Does not prevent lightweight migration.

The pair of the prekey's id and the signature is unique, as the owned identity and the signature are in
`ChannelCreationPingSignatureReceived` and `MutualScanSignatureReceived`. A constraint cannot name the relationship, so the
prekey's `rawPreKeyId` is repeated on the row for it; the relationship stays for the cascade. The replay check reads the
table before any row is written, so the constraint is a guard on the store rather than the mechanism; a violation fails the
save and the batch is run again.

One row per signature accepted when unwrapping a message key with a prekey of the current device, so that the same
message, redelivered while the prekey is still kept, is refused. The relationship is required, but the table starts
empty, so no existing row has to be given a value.

The one query made on the table asks whether a given signature was already accepted with a given prekey, once per message
received over a prekey. It filters on `rawPreKeyId` and `signature`, the pair the constraint names, so the unique index the
store builds for the constraint serves it and the table needs no index of its own.

## PreKeyForCurrentOwnedDevice: Updated entity

+<relationship name="signaturesReceived" toMany="YES" deletionRule="Cascade" destinationEntity="PreKeySignatureReceived" inverseName="preKey" inverseEntity="PreKeyForCurrentOwnedDevice"/>

Added relationship, the inverse of the one above. Does not prevent lightweight migration.

A to-many is stored on the destination's side, so the prekey's table does not change. Cascade makes the rows go with
the prekey when it is deleted after its grace period, which is what bounds the table.

## Conclusion

A lightweight migration is sufficient.
