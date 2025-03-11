During this migration, we made several changes to uniqueness constraints. This readme list the manual validation strategy performed within the NSEntityMigrationPolicy subclasses.

- InboxAttachment - ok
messageId,attachmentNumber -> rawMessageIdOwnedIdentity, rawMessageIdUid, attachmentNumber
No manual validation required.

- MessageHeader - ok
messageId, deviceUid -> rawMessageIdOwnedIdentity, rawMessageIdUid, deviceUid, toCryptoIdentity
No manual validation required.

- OutboxAttachment - ok
none -> rawMessageIdOwnedIdentity,rawMessageIdUid,attachmentNumber
Unlikely to fail, we do nothing.

- PendingDeleteFromServer - ok
messageId -> rawMessageIdOwnedIdentity, rawMessageIdUid
No manual validation required.

- ReceivedMessage - ok
messageId -> rawMessageIdOwnedIdentity, rawMessageIdUid
No manual validation required.

- OutboxMessage - ok
none -> rawMessageIdOwnedIdentity, rawMessageIdUid
Validation strategy: Delete the OutboxMessage within the *source* context that have duplicated messageIds. Also delete the associated attachments and headers.

- InboxMessage
none -> rawMessageIdOwnedIdentity, rawMessageIdUid
Validation strategy: Delete the InboxMessage within the *source* context that have duplicated messageIds duplicates and the associated attachments.
