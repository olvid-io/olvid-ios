# App database migration from v47 to v48

## FyleMessageJoinWithStatus - Modified entity

Changes the name of an attribute: totalUnitCount becomes totalByteCount. Since we set the renaming ID in the destination model, this does not prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient.
