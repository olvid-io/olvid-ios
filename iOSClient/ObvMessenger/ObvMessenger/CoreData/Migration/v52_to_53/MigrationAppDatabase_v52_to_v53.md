# App database migration from v52 to v53

## FyleMessageJoinWithStatus - Modified entity

Adds three transiant properties (estimatedTimeRemaining, fractionCompleted, throughput) with default values.
This does not prevent a lightweight migration.

## SentFyleMessageJoinWithStatus - Modified entity

Removes the identifierForNotifications that wasn't used.
This does not prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient.
