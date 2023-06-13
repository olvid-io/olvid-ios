# App database migration from v63 to v64

## PersistedDiscussion - Updated entity

<attribute name="normalizedSearchKey" optional="YES" attributeType="String"/>

Adds one optional attribute, with no default value, to store text that will be used for the search feature in the discussions list.

## Conclusion

A lightweight migration will suffice.
