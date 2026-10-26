import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location('analyze_workload', Path(__file__).with_name('analyze-workload.py'))
analyzer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analyzer)


def process(pid, birth, at, cpu, name='node', start=None, memory=10):
    row = dict(identity=dict(pid=pid, startMicroseconds=start if start is not None else int(birth * 1e6)),
               startedAt=birth, sampledAt=at, executable='/private/project/' + name, name=name,
               footprintBytes=memory)
    if cpu is not None:
        row.update(rawUserTicks=cpu, rawSystemTicks=0, numerator=1_000_000_000,
                   denominator=1, sampledAtTicks=int(at * 1e9))
    return row


def scan(seq, at, processes, listed=None, outcomes=None):
    return dict(kind='scan', sequence=seq, listedAt=at, scanSeconds=.01,
                processes=processes, listedPIDs=listed if listed is not None else [p['identity']['pid'] for p in processes],
                outcomes=outcomes or [], unreadableCount=0)


def analyze(scans, footer=True):
    rows = [dict(kind='header', format='agent-monitor-workload-observations', version=1,
                 durationSeconds=60, intervalSeconds=.1, excludedPID=999)] + scans
    if footer:
        rows.append(dict(kind='footer', reason='duration', scanCount=len(scans), elapsedSeconds=60,
                         processCPUSeconds=1))
    return analyzer.analyze(io.StringIO(''.join(json.dumps(r) + '\n' for r in rows)))


def contributor(result, name):
    return next(c for c in result['contributors'] if c['name'] == name)


class AccountingTests(unittest.TestCase):
    def test_baseline_newborn_and_pid_reuse_have_independent_cpu(self):
        result = analyze([
            scan(0, 10, [process(1, 1, 10.001, 100)]),
            scan(1, 11, [process(1, 1, 11.001, 103), process(2, 10.5, 11.002, 2)]),
            scan(2, 12, [process(1, 11.5, 12.001, 4)])])
        node = contributor(result, 'node')
        self.assertEqual(node['observed_cpu_seconds'], 9)
        self.assertEqual(node['newborn_initial_cpu_seconds'], 6)
        self.assertEqual(node['lifetimes'], 3)
        self.assertEqual(node['newborn_lifetimes'], 2)

    def test_missing_counter_bridges_and_counter_regression_excludes_interval(self):
        result = analyze([
            scan(0, 10, [process(1, 1, 10, 100)]),
            scan(1, 11, [process(1, 1, 11, None)]),
            scan(2, 12, [process(1, 1, 12, 104)]),
            scan(3, 13, [process(1, 1, 13, 2)]),
            scan(4, 14, [process(1, 1, 14, 3)])])
        self.assertEqual(contributor(result, 'node')['observed_cpu_seconds'], 5)
        self.assertEqual(result['counter_exclusions'], {'missing': 1, 'discontinuity': 1})

    def test_exec_changes_are_visible_and_cpu_is_not_credited_twice(self):
        result = analyze([
            scan(0, 10, []), scan(1, 11, [process(1, 10.5, 11, 1, 'sh')]),
            scan(2, 12, [process(1, 10.5, 12, 4, 'node')]),
            scan(3, 13, [process(1, 10.5, 13, 6, 'tsc')])])
        self.assertEqual(sum(c['observed_cpu_seconds'] for c in result['contributors']), 6)
        node = contributor(result, 'node')
        self.assertEqual(node['observed_cpu_seconds'], 3)
        self.assertEqual(node['image_transition_cpu_seconds'], 3)
        self.assertEqual(node['newborn_last_image_age_seconds']['median'], 1.5)
        self.assertEqual(node['newborn_lifetime_unobserved_final'], 0)

    def test_memory_uses_per_scan_sum_and_missing_memory_is_reported(self):
        first = process(1, 1, 10, 1, memory=100)
        second = process(2, 1, 10, 1, memory=10)
        third = process(1, 1, 11, 2, memory=10)
        fourth = process(2, 1, 11, 2, memory=100)
        missing = process(3, 1, 11, 2)
        del missing['footprintBytes']
        result = analyze([scan(0, 10, [first, second]), scan(1, 11, [third, fourth, missing])])
        node = contributor(result, 'node')
        self.assertEqual(node['max_scan_footprint_bytes'], 110)
        self.assertEqual(node['missing_footprint_reads'], 1)

    def test_out_of_order_counter_does_not_replace_valid_baseline(self):
        late = process(1, 1, 11, 80)
        late['sampledAtTicks'] = 9_000_000_000
        result = analyze([scan(0, 10, [process(1, 1, 10, 100)]),
                          scan(1, 11, [late]), scan(2, 12, [process(1, 1, 12, 105)])])
        self.assertEqual(contributor(result, 'node')['observed_cpu_seconds'], 5)
        self.assertEqual(result['counter_exclusions'], {'invalid_time': 1})

    def test_same_basename_different_path_flags_transition_and_missing_memory_is_unknown(self):
        first = process(1, 1, 10, 100)
        second = process(1, 1, 11, 102)
        second['executable'] = '/another/runtime/node'
        del first['footprintBytes']
        del second['footprintBytes']
        node = contributor(analyze([scan(0, 10, [first]), scan(1, 11, [second])]), 'node')
        self.assertEqual(node['image_transition_cpu_seconds'], 2)
        self.assertIsNone(node['max_scan_footprint_bytes'])

    def test_baseline_only_cpu_is_unknown_but_a_valid_zero_delta_is_measured(self):
        first = scan(0, 10, [process(1, 1, 10, 100)])
        self.assertIsNone(contributor(analyze([first]), 'node')['observed_cpu_seconds'])
        result = analyze([first, scan(1, 11, [process(1, 1, 11, 100)])])
        self.assertEqual(contributor(result, 'node')['observed_cpu_seconds'], 0)

    def test_later_birth_and_counter_recover_newborn_initial_cpu(self):
        unknown = process(1, 10.5, 11, None)
        del unknown['startedAt']
        node = contributor(analyze([scan(0, 10, []), scan(1, 11, [unknown]),
                                    scan(2, 12, [process(1, 10.5, 12, 2)])]), 'node')
        self.assertEqual(node['newborn_lifetimes'], 1)
        self.assertEqual(node['observed_cpu_seconds'], 2)

    def test_kernel_name_fallback_and_listed_but_unread_final_remain_distinct(self):
        sample = process(1, 10.5, 11, 2, 'java')
        del sample['executable']
        java = contributor(analyze([scan(0, 10, []), scan(1, 11, [sample]),
                                    scan(2, 12, [], listed=[1])]), 'java')
        self.assertEqual(java['fallback_name_lifetimes'], 1)
        self.assertEqual(java['fallback_name_reads'], 1)
        self.assertEqual(java['newborn_lifetime_unobserved_final'], 1)
        self.assertEqual(java['newborn_absent_listing_age_seconds']['count'], 0)

    def test_raw_timebase_scales_components_before_summing_intervals(self):
        first = process(1, 1, 10, 6)
        second = process(1, 1, 11, 9)
        for sample in (first, second):
            sample.update(numerator=2_000_000_000, denominator=3)
        second['rawSystemTicks'] = 6
        node = contributor(analyze([scan(0, 10, [first]), scan(1, 11, [second])]), 'node')
        self.assertEqual(node['observed_cpu_seconds'], 6)


class CoverageTests(unittest.TestCase):
    def test_age_is_not_lifetime_and_listed_unread_is_not_a_worker_count(self):
        result = analyze([
            scan(0, 10, [], listed=[50, 999]),
            scan(1, 10.1, [process(1, 10.08, 10.101, 0)], listed=[1, 50, 60, 999]),
            scan(2, 10.2, [], listed=[50, 999])])
        node = contributor(result, 'node')
        self.assertAlmostEqual(node['newborn_last_image_age_seconds']['median'], .021)
        self.assertAlmostEqual(node['newborn_absent_listing_age_seconds']['median'], .13)
        self.assertEqual(node['newborn_single_image_read'], 1)
        self.assertEqual(result['listed_unread_pid_values'], {'baseline': 1, 'first_listed_later': 1})

    def test_reappearance_clears_earlier_absence_and_retains_counter_endpoint(self):
        result = analyze([scan(0, 10, []), scan(1, 11, [process(1, 10.5, 11, 1)]),
                          scan(2, 12, []), scan(3, 13, [process(1, 10.5, 13, 3)])])
        node = contributor(result, 'node')
        self.assertEqual(node['observed_cpu_seconds'], 3)
        self.assertEqual(node['newborn_absent_listing_age_seconds']['count'], 0)
        self.assertEqual(node['newborn_lifetime_unobserved_final'], 0)

    def test_missing_footer_is_reported_without_inventing_duration(self):
        result = analyze([scan(0, 10, [])], footer=False)
        self.assertIsNone(result['footer'])
        self.assertIn('Missing footer', result['warnings'][0])

    def test_unknown_version_malformed_records_and_discontinuous_scans_fail(self):
        for text in ['{"kind":"header","version":99}', 'not json']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                analyzer.analyze(io.StringIO(text))
        with self.assertRaises(ValueError):
            analyze([scan(1, 10, [])])

    def test_output_contains_basename_but_no_process_ids_or_executable_paths(self):
        result = analyze([scan(0, 10, [process(54321, 1, 10, 1)])])
        encoded = json.dumps(result)
        self.assertNotIn('/private/project', encoded)
        self.assertNotIn('54321', encoded)
        self.assertEqual(contributor(result, 'node')['name'], 'node')

    def test_cli_reports_incomplete_capture_and_leaves_input_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.jsonl'
            contents = json.dumps(dict(kind='header', format='agent-monitor-workload-observations', version=1)) + '\n'
            path.write_text(contents)
            result = subprocess.run([sys.executable, SPEC.origin, '--json', str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)[0]['scans'], 0)
            self.assertIsNone(json.loads(result.stdout)[0]['footer'])
            self.assertEqual(path.read_text(), contents)
            path.write_text(contents + '{')
            result = subprocess.run([sys.executable, SPEC.origin, str(path)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('line 2', result.stderr)
            self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
