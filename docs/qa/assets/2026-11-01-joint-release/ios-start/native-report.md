# ios.catalog.header-collapse

- target: ios-sim
- result: **FAILED**
- duration: 115070ms
- git commit: 2ce7feddf69ee2b9fba547fcc6f3003075d07a62 (dirty: false)

## Failure

```
InstanceDiscoveryException: no Pleya Verify instance announced itself within 0:01:00.000000 at any of: /Volumes/SSD/CoreSimulator/Devices/0EF7D62F-941E-41B8-B289-F1257DBC78E4/data/Containers/Data/Application/56DE725F-7774-4839-8122-F6814A26BD13/Library/Caches/pleya-verify/instance.json, /Volumes/SSD/CoreSimulator/Devices/0EF7D62F-941E-41B8-B289-F1257DBC78E4/data/Containers/Data/Application/56DE725F-7774-4839-8122-F6814A26BD13/tmp/pleya-verify/instance.json
```

## Steps
- [PASS] `reset_app` (line 8)
- [PASS] `seed` (line 9)
- [FAIL] `launch` (line 10) — InstanceDiscoveryException: no Pleya Verify instance announced itself within 0:01:00.000000 at any of: /Volumes/SSD/CoreSimulator/Devices/0EF7D62F-941E-41B8-B289-F1257DBC78E4/data/Containers/Data/Application/56DE725F-7774-4839-8122-F6814A26BD13/Library/Caches/pleya-verify/instance.json, /Volumes/SSD/CoreSimulator/Devices/0EF7D62F-941E-41B8-B289-F1257DBC78E4/data/Containers/Data/Application/56DE725F-7774-4839-8122-F6814A26BD13/tmp/pleya-verify/instance.json
