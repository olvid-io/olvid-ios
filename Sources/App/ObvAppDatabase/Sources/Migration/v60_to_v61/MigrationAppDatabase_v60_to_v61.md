# App database migration from v60 to v61

## PersistedMessageReaction - Modified entity

-<attribute name="rawEmoji" attributeType="String"/>
+<attribute name="rawEmoji" optional="YES" attributeType="String"/>

Makes the rawEmoji attribute optional. Does not prevent a lightweight migration.

## Conclusion

A lightweight migration is sufficient.
