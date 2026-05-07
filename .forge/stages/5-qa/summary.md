# Stage 5-qa Summary

**Completed**: 2026-05-07T21:00:00Z | **Verdict**: GO_WITH_NOTES

## Results

- **38/38 tests pass** (37 spec-derived structural tests + 1 sprint adapter regression)
- **AC coverage**: 16/17 (AC-1 snakemake --lint technically fails on exit code due to 7 informational warnings, all non-actionable)
- **Snakemake dry-run**: PASS — exit 0, 67-job DAG verified
- New test file: `tests/test_morales_pipeline_spec.py` (37 tests, static AST + grep-level spec verification)

## Key Findings

- All 22 non-localrule rules have container/log/resources directives (confirmed by test)
- No ~/bin or /binf-isilon paths in pipeline source files
- RED-ML uses BGIRED/RED-ML per spec-deviations.json
- snakemake --lint 7 warnings: 2 false-positive comment paths, 2 config.get() false positives, 1 localrule exempt, 2 style advisories — no actionable errors

## Open Notes

- AC-1 deferred: `snakemake --lint` exit code is 1 (informational warnings only). Consider `--lint --ignore-incomplete` or accepting current state.
- Container builds for star/red_ml/fastx/morales_downstream remain a manual post-merge step.
