Moving the completedUnitCount from FyleMessageJoinWithStatus down to ReceivedFyleMessageJoinWithStatus, since it is not used anymore in SentFyleMessageJoinWithStatus.
We can rely on a lightweight migration for this.
