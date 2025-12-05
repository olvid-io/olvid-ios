#  Engine database migration from v63 to v64

## ObvObliviousChannel: Updated entity

-<attribute name="rawFullRatchetingCountForGKMV2Support" optional="YES" attributeType="Integer 64" usesScalarValueType="YES"/>
-<attribute name="rawSelfRatchetingCountForGKMV2Support" optional="YES" attributeType="Integer 64" usesScalarValueType="YES"/>

Removes two attributes.

## Conclusion

A lightweight migration is sufficient.
