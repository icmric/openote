"""Name the tests that failed in CI, and say whether each looks real or flaky.

Run from `app/` after `flutter test --file-reporter json:test-results.json`.
See docs/writing-tests.md, "When CI is red".

For every failed test:

  1. An `::error::` annotation naming it and its file. Annotations are public;
     job logs need a login, so this is the one place anyone can see which test.
  2. The test is run again ON ITS OWN, once:
       - fails again  -> "FAILED TWICE": treat it as a real bug until shown
                         otherwise.
       - passes       -> "FLAKY": the test depends on timing, ordering, or
                         another test, and is itself the bug. It goes in the
                         register in docs/writing-tests.md and gets fixed, not
                         re-run until green.

The job stays red either way: a re-run that passes is information, never a
pass. Exits 0 itself so it never hides the real failure behind its own.
"""

import json
import os
import shutil
import subprocess
import sys

RESULTS = 'test-results.json'
MAX_RERUNS = 8  # more than this many failures is not flakiness


def failures():
    tests, suites, out = {}, {}, []
    for line in open(RESULTS, encoding='utf-8'):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        kind = e.get('type')
        if kind == 'suite':
            suites[e['suite']['id']] = e['suite'].get('path') or ''
        elif kind == 'testStart':
            t = e['test']
            tests[t['id']] = (t.get('name', '?'), t.get('suiteID'))
        elif (kind == 'testDone' and e.get('result') != 'success'
              and not e.get('hidden')):
            name, suite = tests.get(e['testID'], ('?', None))
            out.append((name, suites.get(suite, '')))
    return out


def rerun(flutter, path, name):
    """True when the test passes on its own."""
    if not path or name == '?' or name.startswith('loading '):
        return False
    r = subprocess.run(
        [flutter, 'test', path, '--plain-name', name, '--reporter',
         'compact'],
        capture_output=True, text=True, encoding='utf-8', errors='replace')
    return r.returncode == 0


def main():
    if not os.path.exists(RESULTS):
        return  # the build failed, not a test: say nothing misleading
    found = failures()
    for name, path in found:
        print(f'::error::FAILED: {name}  [{path}]')
    if not found:
        return
    flutter = shutil.which('flutter') or shutil.which('flutter.bat')
    if not flutter or len(found) > MAX_RERUNS:
        return
    summary = ['### Failing tests, each run again on its own', '']
    for name, path in found:
        passed = rerun(flutter, path, name)
        if passed:
            print(f'::warning::FLAKY (failed in the suite, passed alone): '
                  f'{name}  [{path}]. The test is the bug: see '
                  f'docs/writing-tests.md.')
            summary.append(f'- FLAKY: `{name}` ({path})')
        else:
            print(f'::error::FAILED TWICE (treat as a real bug): '
                  f'{name}  [{path}]')
            summary.append(f'- FAILED TWICE: `{name}` ({path})')
    step = os.environ.get('GITHUB_STEP_SUMMARY')
    if step:
        with open(step, 'a', encoding='utf-8') as f:
            f.write('\n'.join(summary) + '\n')


if __name__ == '__main__':
    try:
        main()
    except Exception as e:  # never stack a crash of this on the real failure
        print(f'::warning::could not classify the failures: {e}')
    sys.exit(0)
