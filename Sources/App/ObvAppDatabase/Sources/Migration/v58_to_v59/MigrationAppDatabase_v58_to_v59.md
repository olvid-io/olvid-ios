# App database migration from v58 to v59

## PersistedObvContactDevice

+<attribute name="rawOwnedIdentityIdentity" attributeType="Binary"/>

Adds a non-nil attribute that represents the owned identity relating to the contact to whom this device belongs. This rawOwnedIdentityIdentity attribute is now part of the uniqueness constraint. We cannot perform a lightweight migration here.

## Conclusion

A heavyweight migration is necessary.
