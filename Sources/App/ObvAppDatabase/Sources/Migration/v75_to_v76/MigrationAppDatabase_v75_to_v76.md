# App database migration from v75 to v76

## PersistedDiscussion: Updated entity

-<attribute name="timestampOfLastMessage" attributeType="Date" usesScalarValueType="NO"/>
+<attribute name="sortDate" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Renames the `timestampOfLastMessage` attribute. The `sortDate` is now optional. When nil, the discussion is considered to be "deleted".

## Conclusion

A heavyweight migration is required.
