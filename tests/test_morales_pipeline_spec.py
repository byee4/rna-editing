"""
QA-generated tests for the Morales_et_al pipeline containerization.

Tests are derived from the acceptance criteria in:
  .forge/stages/2-architect/architecture-plan.md

These tests validate the Snakemake rule structure and configuration schema
WITHOUT executing any containers. All checks are static (grep/AST-level).
"""
import os
import re
import subprocess
import sys
import unittest
import yaml

PIPELINE_DIR = os.path.join(
    os.path.dirname(__file__), "..", "pipelines", "Morales_et_all"
)
REPO_ROOT = os.path.join(os.path.dirname(__file__), "..")

SMK_FILES = [
    os.path.join(PIPELINE_DIR, "preprocessing.smk"),
    os.path.join(PIPELINE_DIR, "tools.smk"),
    os.path.join(PIPELINE_DIR, "downstream.smk"),
    os.path.join(PIPELINE_DIR, "rules", "references.smk"),
    os.path.join(PIPELINE_DIR, "rules", "wgs.smk"),
]

CONTAINERS_DIR = os.path.join(REPO_ROOT, "containers")


def _all_smk_content():
    parts = []
    for f in SMK_FILES:
        with open(f) as fh:
            parts.append(fh.read())
    return "\n".join(parts)


def _parse_rules(smk_file):
    """Return dict of {rule_name: body_text} for non-localrule rules."""
    with open(smk_file) as fh:
        content = fh.read()
    # Collect localrule names
    local_names = set()
    for m in re.finditer(r"^localrules:\s*(.*)", content, re.MULTILINE):
        for name in m.group(1).split(","):
            local_names.add(name.strip())
    # Parse rule blocks
    rules = {}
    pattern = re.compile(r"^rule (\w+):\n((?:(?!^rule ).*\n?)*)", re.MULTILINE)
    for m in pattern.finditer(content):
        name = m.group(1)
        if name not in local_names:
            rules[name] = m.group(2)
    return rules


def _all_rules():
    """Return dict of {rule_name: body_text} across all SMK files."""
    merged = {}
    for f in SMK_FILES:
        merged.update(_parse_rules(f))
    return merged


class TestAC3_NoUserSpecificPaths(unittest.TestCase):
    """AC-3: No ~/bin or /binf-isilon paths in pipeline files."""

    def test_no_user_paths_in_snakefiles_or_config(self):
        target_files = SMK_FILES + [
            os.path.join(PIPELINE_DIR, "Snakefile"),
            os.path.join(PIPELINE_DIR, "config.yaml"),
        ]
        for f in target_files:
            with open(f) as fh:
                content = fh.read()
            self.assertNotRegex(
                content,
                r"~/bin|/binf-isilon",
                msg=f"User-specific path found in {f}",
            )


class TestAC4_ContainerDirectives(unittest.TestCase):
    """AC-4: All 14 original rules have container: directives (22 total with addendum)."""

    def test_all_non_localrules_have_container(self):
        rules = _all_rules()
        missing = [
            name
            for name, body in rules.items()
            if not re.search(r"^\s+container:", body, re.MULTILINE)
        ]
        self.assertEqual(
            missing,
            [],
            msg=f"Rules missing container: directive: {missing}",
        )

    def test_container_directives_use_container_for_helper(self):
        """All container: lines must call container_for() — no raw SIF paths."""
        for f in SMK_FILES:
            with open(f) as fh:
                content = fh.read()
            for line in content.splitlines():
                if re.match(r"\s+container:\s", line):
                    self.assertIn(
                        "container_for(",
                        line,
                        msg=f"container: line in {f} does not use container_for(): {line!r}",
                    )


class TestAC5_LogDirectives(unittest.TestCase):
    """AC-5: All non-localrule rules have log: directives."""

    def test_all_non_localrules_have_log(self):
        rules = _all_rules()
        missing = [
            name
            for name, body in rules.items()
            if not re.search(r"^\s+log:", body, re.MULTILINE)
        ]
        self.assertEqual(missing, [], msg=f"Rules missing log: directive: {missing}")

    def test_log_directives_use_two_handle_pattern(self):
        """log: blocks should have both stdout and stderr handles per D-5."""
        rules = _all_rules()
        for name, body in rules.items():
            log_match = re.search(
                r"^\s+log:\s*\n((?:\s+\w+=.*\n)+)", body, re.MULTILINE
            )
            if log_match:
                log_block = log_match.group(1)
                self.assertIn(
                    "stdout",
                    log_block,
                    msg=f"Rule '{name}': log: block missing stdout handle",
                )
                self.assertIn(
                    "stderr",
                    log_block,
                    msg=f"Rule '{name}': log: block missing stderr handle",
                )


class TestAC6_ResourcesDirectives(unittest.TestCase):
    """AC-6: All non-localrule rules have resources: with mem_mb and runtime."""

    def test_all_non_localrules_have_resources(self):
        rules = _all_rules()
        missing = [
            name
            for name, body in rules.items()
            if not re.search(r"^\s+resources:", body, re.MULTILINE)
        ]
        self.assertEqual(
            missing, [], msg=f"Rules missing resources: directive: {missing}"
        )

    def test_resources_include_mem_mb_and_runtime(self):
        """Resources blocks must specify both mem_mb and runtime per NFR-5."""
        rules = _all_rules()
        for name, body in rules.items():
            res_match = re.search(
                r"^\s+resources:\s*\n((?:\s+.*\n)+?(?=^\s{4}\w|\Z))",
                body,
                re.MULTILINE,
            )
            if res_match:
                block = res_match.group(1)
                self.assertIn(
                    "mem_mb",
                    block,
                    msg=f"Rule '{name}': resources: missing mem_mb",
                )
                self.assertIn(
                    "runtime",
                    block,
                    msg=f"Rule '{name}': resources: missing runtime",
                )

    def test_resource_lambdas_use_attempt_scaling(self):
        """mem_mb must use lambda with attempt-based scaling per D-6."""
        rules = _all_rules()
        for name, body in rules.items():
            res_match = re.search(r"^\s+resources:\s*\n", body, re.MULTILINE)
            if res_match:
                self.assertRegex(
                    body,
                    r"mem_mb\s*=\s*lambda",
                    msg=f"Rule '{name}': mem_mb should be a lambda for attempt-scaling",
                )


class TestAC7_SetEuoPipefail(unittest.TestCase):
    """AC-7: set -euo pipefail in all shell blocks."""

    def test_all_shell_rules_use_set_euo_pipefail(self):
        rules = _all_rules()
        # Only rules with shell: blocks
        for name, body in rules.items():
            if "shell:" in body:
                self.assertIn(
                    "set -euo pipefail",
                    body,
                    msg=f"Rule '{name}' shell block missing 'set -euo pipefail'",
                )


class TestAC8_MarkDuplicatesPicardWrapper(unittest.TestCase):
    """AC-8: mark_duplicates uses 'picard MarkDuplicates' wrapper, not java -jar."""

    def test_no_java_jar_in_preprocessing(self):
        with open(os.path.join(PIPELINE_DIR, "preprocessing.smk")) as fh:
            content = fh.read()
        self.assertNotIn(
            "java -jar",
            content,
            msg="preprocessing.smk should not use 'java -jar'",
        )

    def test_mark_duplicates_uses_picard_wrapper(self):
        rules = _parse_rules(os.path.join(PIPELINE_DIR, "preprocessing.smk"))
        body = rules.get("mark_duplicates", "")
        self.assertIn(
            "picard MarkDuplicates",
            body,
            msg="mark_duplicates rule must call 'picard MarkDuplicates'",
        )


class TestAC9_NoUserPathParams(unittest.TestCase):
    """AC-9: No params.sprint_bin, params.jacusa_jar, params.samtools_bin in rules."""

    def test_old_user_path_params_absent(self):
        content = _all_smk_content()
        for param in ("params.sprint_bin", "params.jacusa_jar", "params.samtools_bin"):
            self.assertNotIn(
                param,
                content,
                msg=f"Old user-path param '{param}' found in pipeline files",
            )

    def test_sprint_uses_opt_path(self):
        """sprint rule must call python /opt/sprint/sprint_from_bam.py (FR-10)."""
        rules = _parse_rules(os.path.join(PIPELINE_DIR, "tools.smk"))
        body = rules.get("sprint", "")
        self.assertIn(
            "/opt/sprint/",
            body,
            msg="sprint rule must use /opt/sprint/ path",
        )

    def test_jacusa2_uses_opt_path(self):
        """jacusa2 rule must call java -jar /opt/jacusa2/jacusa2.jar (FR-11)."""
        rules = _parse_rules(os.path.join(PIPELINE_DIR, "tools.smk"))
        body = rules.get("jacusa2", "")
        self.assertIn(
            "/opt/jacusa2/",
            body,
            msg="jacusa2 rule must use /opt/jacusa2/ path",
        )


class TestAC10_DownstreamParamDir(unittest.TestCase):
    """AC-10: No bare 'python Downstream/' references in downstream.smk."""

    def test_no_bare_downstream_references(self):
        with open(os.path.join(PIPELINE_DIR, "downstream.smk")) as fh:
            content = fh.read()
        self.assertNotIn(
            "python Downstream/",
            content,
            msg="downstream.smk must not use bare 'python Downstream/' path",
        )

    def test_downstream_rules_use_params_downstream_dir(self):
        rules = _parse_rules(os.path.join(PIPELINE_DIR, "downstream.smk"))
        for name in ("run_downstream_parsers", "update_alu", "individual_analysis",
                     "reanalysis_multiple", "multiple_analysis"):
            body = rules.get(name, "")
            self.assertIn(
                "params.downstream_dir",
                body,
                msg=f"Rule '{name}' must use params.downstream_dir",
            )


class TestAC11_ConfigDownstreamScriptsDir(unittest.TestCase):
    """AC-11: config.yaml has downstream_scripts_dir key."""

    def test_downstream_scripts_dir_in_config(self):
        with open(os.path.join(PIPELINE_DIR, "config.yaml")) as fh:
            cfg = yaml.safe_load(fh)
        self.assertIn(
            "downstream_scripts_dir",
            cfg,
            msg="config.yaml must have 'downstream_scripts_dir' key",
        )

    def test_no_tools_section_in_config(self):
        with open(os.path.join(PIPELINE_DIR, "config.yaml")) as fh:
            cfg = yaml.safe_load(fh)
        self.assertNotIn(
            "tools",
            cfg,
            msg="config.yaml must not have a 'tools' section (removed per AC-3/FR-3)",
        )

    def test_containers_section_in_config(self):
        with open(os.path.join(PIPELINE_DIR, "config.yaml")) as fh:
            cfg = yaml.safe_load(fh)
        self.assertIn("containers", cfg)
        # All 9 required container keys must be present
        required = {"fastx", "star", "picard", "reditools", "sprint",
                    "wgs", "red_ml", "jacusa2", "morales_downstream"}
        actual = set(cfg["containers"].keys())
        self.assertTrue(
            required.issubset(actual),
            msg=f"containers block missing keys: {required - actual}",
        )


class TestAC12_to_AC15_ContainerFiles(unittest.TestCase):
    """AC-12..AC-15: Four new container build contexts must exist."""

    def _check_container(self, tool):
        cdir = os.path.join(CONTAINERS_DIR, tool)
        self.assertTrue(
            os.path.isfile(os.path.join(cdir, "Dockerfile")),
            msg=f"containers/{tool}/Dockerfile missing",
        )
        self.assertTrue(
            os.path.isfile(os.path.join(cdir, "validate.sh")),
            msg=f"containers/{tool}/validate.sh missing",
        )

    def test_star_container_exists(self):  # AC-12
        self._check_container("star")

    def test_red_ml_container_exists(self):  # AC-13
        self._check_container("red_ml")

    def test_fastx_container_exists(self):  # AC-14
        self._check_container("fastx")

    def test_morales_downstream_container_exists(self):  # AC-15
        self._check_container("morales_downstream")

    def test_validate_scripts_are_executable_or_have_shebang(self):
        for tool in ("star", "red_ml", "fastx", "morales_downstream"):
            vsh = os.path.join(CONTAINERS_DIR, tool, "validate.sh")
            with open(vsh) as fh:
                first_line = fh.readline()
            self.assertTrue(
                first_line.startswith("#!/"),
                msg=f"containers/{tool}/validate.sh missing shebang",
            )

    def test_red_ml_dockerfile_uses_bgired_url(self):
        """RED-ML Dockerfile must use BGIRED (not BGI-shenzhen) URL per spec-deviations.json."""
        with open(os.path.join(CONTAINERS_DIR, "red_ml", "Dockerfile")) as fh:
            content = fh.read()
        self.assertIn("BGIRED/RED-ML", content)
        self.assertNotIn("BGI-shenzhen/RED-ML", content)


class TestAC16_ContainerForHelper(unittest.TestCase):
    """AC-16: container_for() function defined in Snakefile."""

    def test_container_for_defined_in_snakefile(self):
        with open(os.path.join(PIPELINE_DIR, "Snakefile")) as fh:
            content = fh.read()
        self.assertIn(
            "def container_for(",
            content,
            msg="Snakefile must define container_for() helper",
        )

    def test_sif_dir_and_containers_globals_present(self):
        with open(os.path.join(PIPELINE_DIR, "Snakefile")) as fh:
            content = fh.read()
        self.assertIn("SIF_DIR", content)
        self.assertIn("CONTAINERS", content)

    def test_import_re_present(self):
        """import re added for parity with editing_wgs per m-1."""
        with open(os.path.join(PIPELINE_DIR, "Snakefile")) as fh:
            content = fh.read()
        self.assertIn("import re", content)


class TestAC17_AddMdTagUsesWgsContainer(unittest.TestCase):
    """AC-17: add_md_tag rule uses container_for('wgs') per D-7."""

    def test_add_md_tag_uses_wgs_container(self):
        rules = _parse_rules(os.path.join(PIPELINE_DIR, "tools.smk"))
        body = rules.get("add_md_tag", "")
        self.assertIn(
            'container_for("wgs")',
            body,
            msg="add_md_tag must use container_for('wgs')",
        )


class TestEdgeCases(unittest.TestCase):
    """Edge cases from architecture-plan §9 Risk Register."""

    def test_ec1_downstream_submodule_documented_in_config(self):
        """EC-1/R-6: config.yaml has comment about git submodule init."""
        with open(os.path.join(PIPELINE_DIR, "config.yaml")) as fh:
            raw = fh.read()
        self.assertIn(
            "submodule",
            raw.lower(),
            msg="config.yaml should document submodule init requirement (EC-1)",
        )

    def test_ec4_bcftools_sentinel_stdout(self):
        """EC-4/D-8: bcftools rule writes sentinel to log.stdout."""
        rules = _parse_rules(os.path.join(PIPELINE_DIR, "tools.smk"))
        body = rules.get("bcftools", "")
        self.assertIn(
            "log.stdout",
            body,
            msg="bcftools rule must write to log.stdout (sentinel echo per D-8)",
        )

    def test_ec5_jacusa2_log_paths_have_no_wildcards(self):
        """EC-5: jacusa2 log paths must be literal strings (no wildcards)."""
        rules = _parse_rules(os.path.join(PIPELINE_DIR, "tools.smk"))
        body = rules.get("jacusa2", "")
        log_match = re.search(
            r"^\s+log:\s*\n((?:\s+.*\n)+)", body, re.MULTILINE
        )
        if log_match:
            log_block = log_match.group(1)
            self.assertNotIn(
                "{condition}",
                log_block,
                msg="jacusa2 log paths must not contain wildcards",
            )
            self.assertNotIn(
                "{sample}",
                log_block,
                msg="jacusa2 log paths must not contain wildcards",
            )

    def test_downstream_log_paths_have_no_wildcards(self):
        """EC-6: downstream rule log paths use literal rule names."""
        rules = _parse_rules(os.path.join(PIPELINE_DIR, "downstream.smk"))
        for name in ("run_downstream_parsers", "update_alu", "individual_analysis",
                     "reanalysis_multiple", "multiple_analysis"):
            body = rules.get(name, "")
            log_match = re.search(
                r"^\s+log:\s*\n((?:\s+.*\n)+)", body, re.MULTILINE
            )
            if log_match:
                log_block = log_match.group(1)
                self.assertNotIn(
                    "{condition}",
                    log_block,
                    msg=f"Rule '{name}' log paths must not contain wildcards",
                )

    def test_mark_duplicates_has_no_java_jar_with_heap_flag(self):
        """R-1 mitigation: mark_duplicates uses wrapper, not java -jar with heap."""
        with open(os.path.join(PIPELINE_DIR, "preprocessing.smk")) as fh:
            content = fh.read()
        self.assertNotRegex(
            content,
            r"java\s+-Xmx",
            msg="mark_duplicates should use picard wrapper, not java -Xmx flags",
        )

    def test_star_mapping_resources_floor_is_32gb(self):
        """NFR-5: star_mapping base mem_mb must be >= 32000."""
        rules = _parse_rules(os.path.join(PIPELINE_DIR, "preprocessing.smk"))
        body = rules.get("star_mapping", "")
        mem_match = re.search(r"mem_mb\s*=\s*lambda[^:]+:\s*(\d+)", body)
        if mem_match:
            base_mb = int(mem_match.group(1))
            self.assertGreaterEqual(
                base_mb,
                32000,
                msg=f"star_mapping base mem_mb {base_mb} is below 32000 MB floor",
            )

    def test_jacusa2_resources_floor_is_32gb(self):
        """NFR-5: jacusa2 base mem_mb must be >= 32000."""
        rules = _parse_rules(os.path.join(PIPELINE_DIR, "tools.smk"))
        body = rules.get("jacusa2", "")
        mem_match = re.search(r"mem_mb\s*=\s*lambda[^:]+:\s*(\d+)", body)
        if mem_match:
            base_mb = int(mem_match.group(1))
            self.assertGreaterEqual(
                base_mb,
                32000,
                msg=f"jacusa2 base mem_mb {base_mb} is below 32000 MB floor",
            )

    def test_data_pipeline_idempotency_dryrun(self):
        """AC-2 idempotency: dry-run twice produces identical output."""
        result1 = subprocess.run(
            ["conda", "run", "-n", "snakemake9",
             "snakemake", "-n", "--snakefile", "Snakefile",
             "--configfile", "config.yaml", "--cores", "1",
             "--quiet", "rules"],
            cwd=os.path.join(REPO_ROOT, "pipelines", "Morales_et_all"),
            capture_output=True, text=True, timeout=60,
        )
        result2 = subprocess.run(
            ["conda", "run", "-n", "snakemake9",
             "snakemake", "-n", "--snakefile", "Snakefile",
             "--configfile", "config.yaml", "--cores", "1",
             "--quiet", "rules"],
            cwd=os.path.join(REPO_ROOT, "pipelines", "Morales_et_all"),
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result1.returncode, 0, msg="First dry-run failed")
        self.assertEqual(result2.returncode, 0, msg="Second dry-run failed")
        self.assertEqual(
            result1.stdout, result2.stdout,
            msg="Dry-run output is not idempotent",
        )


if __name__ == "__main__":
    unittest.main()
