#  Engine database migration from v60 to v61

## InboxMessage: Updated entity

+<attribute name="isOnHold" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

New attribute with a default value. This does not prevent a lightweight migration.

## InboxAttachmentChunk: Updated entity

-<attribute name="downloadedTimeStamp" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
-<attribute name="encryptedChunkURL" optional="YES" attributeType="URI"/>

Removes two unused attributes. This does not prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient.
