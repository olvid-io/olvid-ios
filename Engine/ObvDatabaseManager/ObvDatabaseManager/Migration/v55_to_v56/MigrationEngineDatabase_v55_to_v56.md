#  Engine database migration from v55 to v56

## ObvObliviousChannel: Updated entity

+<attribute name="rawFullRatchetingCountForGKMV2Support" optional="YES" attributeType="Integer 64" usesScalarValueType="YES"/>
+<attribute name="rawSelfRatchetingCountForGKMV2Support" optional="YES" attributeType="Integer 64" usesScalarValueType="YES"/>

Adding two optional attributes. This does not prevent lightweight migration.

## Conclusion

A lightweight migration is sufficient.
