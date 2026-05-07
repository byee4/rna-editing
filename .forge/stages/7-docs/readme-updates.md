# Suggested README Updates

The current `README.md` does not mention the `Morales_et_all` pipeline. Suggested addition after the existing `editing_wgs` description:

---

The benchmarking pipeline in `pipelines/Morales_et_all` runs five RNA editing callers (REDItools2, SPRINT, RED-ML, BCFtools, JACUSA2) on paired WT/ADAR1KO samples, following the Morales et al. benchmarking approach. It accepts a samplesheet CSV and optional WGS FASTQs for SNP database generation. See `pipelines/Morales_et_all/config.yaml` for configuration and `.forge/stages/7-docs/user-guide.md` for usage.

Four additional containers are required for this pipeline: `star.sif`, `red_ml.sif`, `fastx.sif`, and `morales_downstream.sif`. Build them with:

```bash
TOOLS="star red_ml fastx morales_downstream" scripts/validate_containers.sh
```

---

Note: This is a diff suggestion only. The README was not modified.
