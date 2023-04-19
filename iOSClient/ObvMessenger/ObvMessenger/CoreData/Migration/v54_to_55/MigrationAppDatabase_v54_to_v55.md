# App database migration from v54 to v55

## PersistedDiscussionSharedConfiguration - Modified entity

The readOnce attribute was optional, it is now mandatory with a default value set to NO. We noticed that a lightweight migration does *not* set the default value if the initial value was nil. Although this does not seem to be a problem in practice (nothing crashes, a nil value seems to be interpreted as a NO), and although it is unlikely to find a nil value for this attribute, we decided to perform a heavyweight migration.

## Conclusion

A heavyweight migration is preferred.
