import 'package:uuid/uuid.dart';

/// UUIDv7 everywhere (Data Model Spec §2): time-ordered, eager, immutable.
const _uuid = Uuid();
String newId() => _uuid.v7();
