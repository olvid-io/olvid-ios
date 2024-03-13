# App database migration from v67 to v68

## PersistedDiscussionLocalConfiguration - Updated entity

-<attribute name="rawDoFetchContentRichURLsMetadata" optional="YES" attributeType="Integer 64" usesScalarValueType="YES"/>

Removes an attribute, this does not prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient.
