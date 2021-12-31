#  App database migration from v31 to v32

## ReceivedFyleMessageJoinWithStatus

Adds
<attribute name="downsizedThumbnail" optional="YES" attributeType="Binary"/>

This migration requires almost no work since it only adds an optional attribute, we can perform a lightweight migration.
