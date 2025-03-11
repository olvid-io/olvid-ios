Migration performed during the refactoring of the Fetch Manager.

New entity called InboxAttachmentChunk, associated to InboxAttachment (one attachment has one or more chunks)
New entity called InboxAttachmentSession, associated to InboxAttachment (one attachment has at most one session)

Chunks are created at the same time the attachment, so they should be created during migration.
InboxAttachmentSession can be nil during migration.

The only migration policy we need concerns InboxAttachment, where we must create the InboxAttachmentChunk for each attachment
