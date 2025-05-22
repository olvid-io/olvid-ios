#  Engine database migration from v59 to v60

## OwnedIdentity: Updated entity

+<attribute name="rawBackupSeed" attributeType="Binary"/>

The rawBackupSeed attribute is mandatory as it is used in the new version of the backups. The migration process should compute it in a deterministic way.

## Conclusion

A heavyweight migration is required.
