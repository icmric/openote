/// The web half of [SecretStore]: there is no credential store here.
///
/// `secret_store.dart` is explicit that this case exists and what to do about
/// it — *"There is deliberately **no plaintext fallback of any kind**: a
/// machine with no usable store means 'connecting a GitHub account is not
/// available here', said out loud"*. The browser is that machine. These three
/// answers are the same ones a Linux desktop without `libsecret-tools` gives,
/// a path `github_token_storage_test.dart` already covers, so the "cannot save
/// your key" wording the caller shows is already written and already tested.
///
/// **Not `localStorage`, deliberately.** It would be the obvious place and it
/// is the wrong one: a GitHub access key in `localStorage` is readable by any
/// script on the origin and survives in the profile afterwards, which is a
/// worse version of the `workspace.json` leak Task #73 removed. The whole
/// point of this class is that a secret never lands somewhere that casual
/// access can read.
library;

/// False in a browser. The in-memory test map this gates is a `flutter test`
/// safety net; a browser build has no developer credential manager to protect.
bool platformIsUnderTest() => false;

String? platformSecretRead(String key) => null;

Future<bool> platformSecretWrite(String key, String value) async => false;

/// True: there was nothing to remove and nothing is left, which is what
/// callers treat as done. The same answer Linux gives without libsecret.
bool platformSecretDelete(String key) => true;
