# Writing tests that only fail when the app is wrong

A red CI run should mean "the app is broken". Through November 2026 it mostly
meant "a test guessed wrong about the machine", often enough that the reasonable
reading of a red run became "probably the test". That is worse than no test: a
real failure now gets the same shrug.

This page is the rules that stop it, what CI does when a test fails, and the
register of the flakes found so far. `test/test_hygiene_guard_test.dart` enforces
the one rule a machine can check.

## The rules

Every failure in the register below breaks one of these.

### 1. Wait for the thing, never for a length of time

```dart
// No: a guess that the watcher fires within 400 ms. True on a laptop, false on
// a loaded CI runner, and the failure looks exactly like a bug.
await Future<void>.delayed(const Duration(milliseconds: 400));
expect(fired, isNotEmpty);

// Yes: waits as long as it takes, and fails after 15 s naming what never came.
await eventually(() => fired.isNotEmpty, what: 'a pull');
```

`eventually` is for `test()` bodies. In a `testWidgets` body the clock is fake, so
use `pumpUntil(t, () => ..., what: ...)`, which pumps frames and lets real time
pass for file and database work in between. Both are in `test/support/wait.dart`.

A fixed sleep cannot prove that something did **not** happen either; it only
proves it had not happened yet. For "no pull for our own writes", wait for a
later event that is known to come after it, or test the rule on a fake clock
(rule 2). A negative check after a sleep is tolerated in the existing tests
because it can only pass wrongly, never fail wrongly, but it proves little.

The guard counts fixed sleeps per test file and only lets the number go down. A
sleep that is not a wait (a fake that is slow on purpose, the step of a polling
loop) takes a `// sleep-ok: <why>` comment on the line above.

### 2. A rule about time runs on a fake clock

A debounce, a retry delay, a timeout: these are rules about time, and the real
clock on a shared runner is not a reliable witness. Drive them in a `testWidgets`
body, where timers are fake and `await t.pump(duration)` moves time exactly. If
the timer is behind a filesystem event or a socket, give the class a
`@visibleForTesting` way to feed it the event (`OpFolderWatcher.debugEvent`), and
keep one plain real-filesystem test that checks only that a real event is noticed.

Performance is the same: **counted, never clocked**. Assert how many rebuilds,
yields or reads happened, not how many milliseconds passed. Several tests here
already do (`drag_paints_not_writes_test`, the paced-parse tests).

### 3. Let the app's own background work finish before you set the scene

Opening a notebook, warming its log, joining a folder: each starts work the app
does not wait for (a replay, a fold, a proof of the pictures, a look by the
writing checker). If the test then arranges files or settings, that work can land
in the middle and undo them. Three of the five failures on 17–18 November were
this.

```dart
await app.joinNotebookFromFolder('tree', folderForTest: folder);
await app.settleBackgroundWork(); // the open-time fold finishes here
repo.setSetting(...);             // now nothing will overwrite this
```

If `settleBackgroundWork()` does not cover some background job, that is a gap in
`settleBackgroundWork()`: add the job there (as the open-time fold was on 18
November), and don't work around it in the test.

### 4. `await` means done

If `await thing.refresh()` can return before the refresh has an answer, every
caller in the app has the same problem the test has. `WritingReview.refresh()`
returned empty-handed whenever its own scheduled look superseded it; that was a
real defect the flaky test found, and it was fixed in the app. When a test needs
a sleep to see the result of an awaited call, fix the call.

### 5. Don't depend on an order nobody promised

A directory lists in the filesystem's order, not by name, and that order differs
between machines (ext4 hashes names with a per-filesystem seed). A `Set` or a
`Map` from an unordered source, file events and their batching: none of these
come in a promised order. Sort before comparing, or arrange the test so any order
gives the same answer (`notebook_scan_test`'s budget test puts a notebook in every
folder rather than hiding one in the folder it hoped would be listed last).

### 6. Test hooks must compose with the real state

A `debug…` setter that overwrites what the app is tracking breaks the moment the
app is tracking something real at the same time. `debugSetOpening(true)` used to
set the opening count to 1, so the app's own opening finishing a moment later
cleared the test's too. It counts now, like a real opening.

### 7. Each test owns everything it touches

Its own temporary directory, its own `Repository` and `AppState`, deleted or
disposed in `addTearDown`. Statics it changes (`AppState.syncLogEnabled`,
`AppState.blobProofPatience`) are put back in `addTearDown`, not at the end of the
body, where a failure would skip it and break the next test instead.

### 8. Never weaken the assertion to make it pass

A flaky test that checks the right thing is fixed by making the *wait* right, not
the *claim* weaker. `folder_watch_test`'s burst test went from "one pull" to
"at most two" to "fewer than eight" before it was moved to a fake clock, where it
checks "exactly one, and only after the burst stopped". Backlog §1.13 says the
same about the purge test's byte-equality check.

## Before you push a test that touches time, files or another thread

Run it many times on a busy machine:

```sh
cd app
tool/stress_test.sh test/folder_watch_test.dart 20
tool/stress_test.sh test/review_writing_test.dart 20 "real checker"
```

It runs one busy loop per CPU while the test repeats, which is roughly how a
shared CI runner feels to a test: timers fire late and file events arrive in
clumps. Zero failures in 20 is the bar. It runs on Linux and macOS, and in Git
Bash on Windows.

## When CI is red

The job's annotations name every failing test, then run each one again **on its
own** (`app/tool/ci_failures.py`):

- **FAILED TWICE.** Treat it as a real bug until shown otherwise. Read the test's
  output in the job log.
- **FLAKY (failed in the suite, passed alone).** The test is the bug: it depends
  on timing, on order, or on another test. Add it to the register below, find
  which rule it breaks, and fix that. Don't re-run the job until it is green.

The job stays red in both cases. A re-run that passes is information, never a
pass.

## Register

Every flake found, what it broke, and the fix. When a test turns up here twice,
the first fix was wrong.

| Found | Test | Where | Rule | Cause | Fix |
|---|---|---|---|---|---|
| 12 Nov | `cloud_sync_test`: purging a joined notebook leaves the other device alone | Windows | 3 | Device A's own pending autosave appended after the baseline | Flush both devices' saves first (backlog §1.13) |
| 17 Nov | `folder_join_test`: a notebook not read in all the way shows no page | Windows | 3, 6 | The join's open-time fold finished mid-test: re-marked the notebook folded, and cleared the test's `debugSetOpening` | `settleBackgroundWork()` waits for folds; `debugSetOpening` counts; the test settles after joining |
| 17 Nov | `cloud_sync_test`: a burst of writes settles into a single pull | macOS | 1, 2 | 20 ms gaps against a 120 ms window, on a loaded runner | Moved to a fake clock in `folder_watch_test` |
| 17 Nov | `blob_proof_test`: copies left by an earlier repair are cleared once per notebook | macOS | 3 | The proof that opening the log starts raced the test for the stray files | Settle first, then lay the strays down |
| 18 Nov | `notebook_scan_test`: it gives up rather than walk a whole drive | Linux | 5 | Hid a notebook in `f29` and assumed it was listed late | A notebook in every folder; count what the budget reaches |
| 18 Nov | `review_writing_test`: with the real checker: found, fixed, counted | Windows | 4 | The review's own 50 ms look superseded the awaited refresh, which then returned empty | `refresh()` waits for the look that superseded it (an app fix) |

Fixed at the same time, before they failed: the remaining fixed waits in
`folder_watch_test`, `single_instance_test`, `phone_layout_test`,
`notebook_scan_test` and one in `blob_proof_test` (rule 1).

Still allowed by the guard, to be worked down: 36 fixed sleeps across 21 files
(the `_known` table in `test_hygiene_guard_test.dart`). Many are polling loops
with a short deadline, which are better as `eventually`.
