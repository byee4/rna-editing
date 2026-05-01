import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SNAKEMAKE = REPO_ROOT / ".conda" / "editing-wgs-snakemake" / "bin" / "snakemake"
PIPELINE_DIR = REPO_ROOT / "pipelines" / "editing_wgs"


class EditingWgsDryRunTest(unittest.TestCase):
    """Dry-run tests for all configured editing_wgs sample branches."""

    def test_all_sample_instance_types_are_schedulable(self):
        """All sample branches build a DAG, including the shared STAR index."""
        with tempfile.TemporaryDirectory(
            prefix="editing_wgs_snakemake_source_cache_",
            dir="/private/tmp",
        ) as source_cache:
            result = subprocess.run(
                [
                    str(SNAKEMAKE),
                    "--snakefile",
                    str(PIPELINE_DIR / "Snakefile"),
                    "--directory",
                    str(PIPELINE_DIR),
                    "--configfile",
                    str(PIPELINE_DIR / "tests" / "config.yaml"),
                    "--replace-workflow-config",
                    "--runtime-source-cache-path",
                    source_cache,
                    "--dry-run",
                    "--cores",
                    "1",
                ],
                cwd=REPO_ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("total                        56", result.stdout)
        self.assertIn("bwa_index                     1", result.stdout)
        self.assertIn("samtools_faidx                1", result.stdout)
        self.assertIn("samtools_index                8", result.stdout)
        self.assertIn("bwa_mem_wgs                   2", result.stdout)
        self.assertIn("star_genome_generate          1", result.stdout)
        self.assertIn("star_align_rna                4", result.stdout)
        self.assertIn("editpredict_filter            4", result.stdout)


if __name__ == "__main__":
    unittest.main()
