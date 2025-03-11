#  Engine database migration from v51 to v52

## PendingServerQuery: Updated entity

+<attribute name="rawCreationDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Although the new rawCreationDate attribute is optional, we want to set a default date. We use a heavyweight migration.

## Conclusion

A heavyweight migration is necessary.
