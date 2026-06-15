# App database migration from v78 to v79

## PersistedGroupV2Member

+<attribute name="rawDateCreated" attributeType="Date" usesScalarValueType="NO"/>

Non-optional added attribute. Requires a heavyweight migration. We will set this date to Date.now during the migration.

+<attribute name="rawDateUnpended" optional="YES" attributeType="Date" usesScalarValueType="NO"/>

Optional attribute. If the group member is still pending, we keep it to nil. If not, we set it to the same date than rawDateCreated.

+<attribute name="rawNeedsReplayOfPastEvents" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>

We keep the default value.

## Conclusion

A heavyweight migration is required.
