# App database migration from v48 to v49

## PersistedAttachmentSentRecipientInfos - New entity

This does not prevent a lightweight migration.

## PersistedMessageSentRecipientInfos - Modified entity

Adds attachmentInfos toMany relationship that can be empty. This does not prevent a lightweight migration.

## ReceivedFyleMessageJoinWithStatus - Modified entity

Adds the wasOpened attribute, that needs to be set to true for existing ReceivedFyleMessageJoinWithStatus. This prevents lightweight migration but a mapping file is sufficient.

## SentFyleMessageJoinWithStatus - Modified entity

Adds the rawReceptionStatus attribute, that is non optional with default value. This does not prevent a lightweight migration.

## Conclusion

A heavyweight migration is required but a mapping file is sufficient.
