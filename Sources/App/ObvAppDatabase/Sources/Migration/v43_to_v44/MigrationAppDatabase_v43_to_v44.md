# App database migration from v43 to v44

## FyleMessageJoinWithStatus, SentFyleMessageJoinWithStatus, and ReceivedFyleMessageJoinWithStatus - Modified entities

Adds the "index" attribute on FyleMessageJoinWithStatus, that corresponds to the (now deleted) "numberFromEngine" attribute of the ReceivedFyleMessageJoinWithStatus entity and to the (now deleted) "index" attribute of the SentFyleMessageJoinWithStatus entity.

New attribute called messageSortIndex on FyleMessageJoinWithStatus equal to the sort index of the message associated with the join.

## Conclusion

Although it is not possible to perform a lightweight migration, it should be possible to rely on the mapping file only.
