#  Engine database migration from v37 to v38

## ProtocolInstance - Modified entity

The `waitingForTrustLevelIncrease` relationship points to the `ProtocolInstanceWaitingForContactUpgradeToOneToOne` that is a renaming of the `ProtocolInstanceWaitingForTrustLevelIncrease` entity (see bellow).

## ProtocolInstanceWaitingForTrustLevelIncrease - Renamed entity

This entity was renamed to `ProtocolInstanceWaitingForContactUpgradeToOneToOne`. To perform the lightweight migration, we set the Renaming ID of the `ProtocolInstanceWaitingForContactUpgradeToOneToOne` entity in the destination (v38) model.

We also removed the `targetTrustLevelRaw` attribute.

## Conclusion

A lightweight migration is sufficient.
