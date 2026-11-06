# App database migration from v82 to v83

## PersistedDiscussionLocalConfiguration - Updated entity

+<attribute name="doubleTapEmoji" optional="YES" attributeType="String"/>

Adds one optional attribute, holding the emoji a double tap on a message sends in this discussion. Optional and with no default value, so an existing
configuration migrates with a nil value — which the app reads as "no preference for this discussion" and falls back to the app-level default, exactly as
it behaved before this attribute existed. Does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
