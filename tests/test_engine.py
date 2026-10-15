"""Exercise the real engine with every OS command mocked; never change power settings."""
import ast
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'chris-cafe'


def definitions():
    tree = ast.parse(SOURCE.read_text())
    stop = next(i for i, node in enumerate(tree.body)
                if isinstance(node, ast.If) and ast.unparse(node.test) == 'parent_gone()')
    scope = {'__name__': 'engine_test'}
    with patch.object(sys, 'argv', ['chris-cafe']):
        exec(compile(ast.Module(body=tree.body[:stop], type_ignores=[]), str(SOURCE), 'exec'), scope)
    return scope


class EngineTests(unittest.TestCase):
    def setUp(self):
        self.g = definitions()

    def result(self, output='', status=0):
        return subprocess.CompletedProcess([], status, output, '')

    def test_missing_lid_is_different_from_failed_probe(self):
        self.g['clamshell'] = lambda: self.result()
        self.assertFalse(self.g['has_lid']())
        self.g['clamshell'] = lambda: self.result(status=1)
        self.assertIsNone(self.g['has_lid']())

    def test_unknown_power_arms_guard_even_with_lid_open(self):
        self.g['lidded'] = True
        self.g['on_battery'] = lambda: None
        self.assertEqual(self.g['carveout'](False), self.g['MURK'])

    def test_ac_and_open_lid_carveouts(self):
        self.g['lidded'] = True
        self.g['on_battery'] = lambda: False
        self.assertEqual(self.g['carveout'](True), self.g['AC'])
        self.assertEqual(self.g['carveout'](False), self.g['LID'])

    def test_invalid_pressure_never_counts_as_cool(self):
        self.g['sudo'] = lambda _: self.result('Current pressure level: Unknown')
        self.assertIsNone(self.g['pressure']())

    def test_display_inventory_failure_does_not_blank(self):
        for output in ['', '{}', '{"SPDisplaysDataType": []}']:
            self.g['run'] = lambda _, output=output: self.result(output)
            self.assertIsNone(self.g['external_displays']())

    def test_external_display_is_not_blanked(self):
        self.g['display_on'] = lambda: True
        self.g['external_displays'] = lambda: [{'external': True}]
        self.g['run'] = lambda _: self.fail('must not blank')
        self.assertFalse(self.g['blank_if_shut'](True, True))

    def test_lid_is_rechecked_before_blanking(self):
        self.g['display_on'] = lambda: True
        self.g['external_displays'] = lambda: []
        self.g['lid_closed'] = lambda: False
        self.g['run'] = lambda _: self.fail('lid opened: must not blank')
        self.assertFalse(self.g['blank_if_shut'](True, True))

    def test_parent_death_is_detected(self):
        self.g['args'].parent_pid = 123
        with patch('os.getppid', return_value=1):
            self.assertTrue(self.g['parent_gone']())

    def test_json_events_flush_and_keep_original_semantics(self):
        self.g['args'].events_json = True
        output = io.StringIO()
        with contextlib.redirect_stderr(output):
            self.g['say']('sleep enabled', self.g['BED'])
        self.assertEqual(json.loads(output.getvalue()), {'kind': '🛌', 'message': 'sleep enabled'})

    def run_loop(self, levels, orphaned=False):
        """Run the actual production loop with fake probes and an in-memory lock."""
        source = SOURCE.read_text()
        source = source[source.index('if parent_gone():\n  sys.exit(0)'):]
        g = self.g
        calls, events = [], []
        g.update({
            'take_lock': lambda: io.StringIO(),
            'has_lid': lambda: True,
            'lid_closed': lambda: True,
            'on_battery': lambda: True,
            'waketime': lambda: 'same-wake',
            'override_set': lambda: True,
            'blank_if_shut': lambda *_: False,
            'say': lambda message, mark=g['CUP']: events.append((mark, message)),
        })
        # Initial pressure check plus one value per tick; no real waiting.
        samples = iter(['Nominal'] + levels)
        g['pressure'] = lambda: next(samples)
        ticks = iter(range(0, 10000, 61))
        g['args'].interval = 60
        parent_checks = iter([False, True]) if orphaned else None
        g['parent_gone'] = lambda: next(parent_checks) if parent_checks else False
        g['sudo'] = lambda vector: (calls.append(vector) or self.result())
        with patch('time.monotonic', side_effect=lambda: next(ticks)), \
             patch('time.time', side_effect=lambda: 0), \
             patch('time.sleep'), patch('signal.signal'), \
             patch('os.fstat', return_value=type('Stat', (), {'st_ino': 1, 'st_dev': 1})()), \
             patch('os.path.exists', return_value=False):
            # StringIO has no fileno; the lock check uses the real descriptor only for identity.
            class Lock:
                def fileno(self): return 999
            g['take_lock'] = Lock
            with self.assertRaises(SystemExit) as exit_result:
                exec(compile(source, str(SOURCE), 'exec'), g)
        return calls, events, exit_result.exception.code

    def test_critical_releases_override_before_sleep(self):
        calls, _, status = self.run_loop(['Critical'])
        self.assertEqual(status, 125)
        self.assertEqual(calls, [self.g['HOLD'], self.g['RELEASE'], self.g['SLEEPNOW']])

    def test_app_crash_releases_override_without_sleeping_machine(self):
        calls, _, status = self.run_loop([], orphaned=True)
        self.assertEqual(status, 0)
        self.assertEqual(calls, [self.g['HOLD'], self.g['RELEASE']])

    def test_three_serious_samples_trigger_sleep(self):
        calls, _, status = self.run_loop(['Serious'] * 3)
        self.assertEqual(status, 125)
        self.assertEqual(calls[-2:], [self.g['RELEASE'], self.g['SLEEPNOW']])

    def test_cool_reading_resets_hot_streak(self):
        _, events, status = self.run_loop(['Serious', 'Serious', 'Nominal', 'Serious', 'Serious', 'Critical'])
        self.assertEqual(status, 125)
        self.assertTrue(any('Critical' in message for _, message in events))

    def test_three_unreadable_samples_release_without_forcing_sleep(self):
        calls, _, status = self.run_loop([None] * 3)
        self.assertEqual(status, 1)
        self.assertEqual(calls, [self.g['HOLD'], self.g['RELEASE']])


if __name__ == '__main__':
    unittest.main()
