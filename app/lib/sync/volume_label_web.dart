/// The browser half of [platformVolumeLabel]: there are no drives.
library;

/// Always null. A tab has no volumes, and the picker this decorates is itself
/// unreachable without [Capability.localFiles].
String? platformVolumeLabel(String driveLetter) => null;
