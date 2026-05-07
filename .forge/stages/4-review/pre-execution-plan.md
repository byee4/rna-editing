## Pre-Execution Plan: 4-review

1. **Three most likely failure modes**:
   - **Scope drift in post-implement commits**: The 5 commits after the implement stage (wgs.smk, references.smk, build_downstream_dbs.py) added 566 lines not tracked by the architect plan. Reviewer may flag these as out-of-scope. Signal: review report mentions files not in the architect's file allowlist.
   - **Missing container directives in new rules**: wgs.smk and references.smk were added post-implementation; they may lack container:/log:/resources: directives or use hardcoded paths. Signal: grep for ~/bin, /home, or missing container: in those files.
   - **Dockerfile correctness**: The 4 new Dockerfiles (star, red_ml, fastx, morales_downstream) have not been built or run. They may have dependency version issues or wrong base images. Signal: reviewer flags unvalidated Dockerfiles.

2. **First verification steps**:
   - Confirm architecture-plan.md and implementer-prompt.md exist in 2-architect stage
   - Confirm all modified files exist in the working tree
   - Check wgs.smk and references.smk for container/log/resources directives

3. **Context dependencies**:
   - `.forge/stages/2-architect/architecture-plan.md` — the spec the reviewer judges against
   - `.forge/stages/3-implement/implementation-report.md` — what was claimed as done
   - `pipelines/Morales_et_all/` — all .smk files
   - `containers/*/Dockerfile` — all 4 new Dockerfiles
