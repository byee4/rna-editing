## Pre-Execution Plan: 5-qa

1. **Three most likely failure modes**:
   - **TSCC-only tests can't run here**: snakemake --lint and dry-run need snakemake9 conda env. The QA stage must mark these as DEFERRED with clear TSCC instructions rather than silently skipping them.
   - **build_downstream_dbs.py has no tests**: The new 241-line script (ratified via architecture-addendum) has no test coverage. Writing meaningful tests requires either real REDIportal data or mock fixtures.
   - **import re missing causes unit test fail**: m-1 fix (import re in Snakefile) was applied in revision; test must verify this.

2. **First verification steps**:
   - Run the existing unit test: `python -m unittest tests/test_sprint_to_deepred_vcf.py`
   - Check if any new tests exist under tests/ already
   - Count grep-verifiable structural ACs from the architecture plan

3. **Context dependencies**:
   - `.forge/stages/4-review/review-report.md` — lists all ACs and deferred items
   - `.forge/stages/2-architect/architecture-plan.md` — original ACs
   - `.forge/stages/2-architect/architecture-addendum.md` — D-13/14/15 additional ACs
   - `tests/` — existing test files
