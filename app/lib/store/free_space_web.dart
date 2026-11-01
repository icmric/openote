/// The web half of [FreeSpace]: there is no volume to measure.
///
/// Null is already the documented "I could not measure" answer, and
/// [FreeSpace] requires every caller to treat it as *refuse*, never as
/// "probably fine". So the browser gets the safe answer for free, and the one
/// caller that asks — the VACUUM precheck in v0.17 Step 7 — is a step the web
/// build does not run anyway.
library;

int? windowsFreeBytes(String dir) => null;
