# App database migration from v76 to v77

## PersistedMessage: Updated entity

+<relationship name="poll" optional="YES" maxCount="1" deletionRule="Cascade" destinationEntity="PersistedPoll" inverseName="message" inverseEntity="PersistedPoll"/>

New optional relationship. Does not prevent lightweight migration.

## PersistedObvContactIdentity: Updated entity

+<relationship name="votes" optional="YES" toMany="YES" deletionRule="Nullify" destinationEntity="PersistedPollVoteReceived" inverseName="contact" inverseEntity="PersistedPollVoteReceived"/>

New optional relationship. Does not prevent lightweight migration.

## PersistedPoll, PersistedPollCandidate, PersistedPollVote, PersistedPollVoteReceived, PersistedPollVoteSent: New entities

Does not prevent lightweight migration.

## Conclusion

A heavyweight migration is required.
