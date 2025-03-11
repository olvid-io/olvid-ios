# App database migration from v56 to v57

## PersistedDiscussion - Modified entity

Adds the illustrativeMessage relationship to PersistedMessage. This relationship being optional, and recomputed at bootstrap, a lightweight migration is sufficient.

## PersistedMessage - Modified entity

Adds the illustrativeMessageForDiscussion relationship (inverse of the previous one). For the same reasons as above, a lightweight migration is sufficient.

## Conclusion

A lightweight migration is sufficient.
