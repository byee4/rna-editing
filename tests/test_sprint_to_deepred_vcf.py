import tempfile
import unittest
from pathlib import Path

from scripts.sprint_to_deepred_vcf import convert_sprint_res_to_deepred_vcf


class SprintToDeepRedVcfTest(unittest.TestCase):
    """Tests for converting SPRINT RES rows into DeepRed candidate SNVs."""

    def test_regular_res_rows_are_converted_to_ref_alt_vcf(self):
        """SPRINT one-based end coordinates and edit types become DeepRed rows."""
        with tempfile.TemporaryDirectory() as tmpdir:
            source = Path(tmpdir) / "regular.res"
            target = Path(tmpdir) / "sample.gatk.raw.vcf"
            source.write_text(
                "#Chrom\tStart(0base)\tEnd(1base)\tType\tSupporting_reads\tStrand\tAD:DP\n"
                "chr1\t99\t100\tAG\t5\t+\t5:20\n"
                "chr2\t249\t250\tTC\t3\t-\t3:12\n"
            )

            converted = convert_sprint_res_to_deepred_vcf(str(source), str(target))

            self.assertEqual(converted, 2)
            self.assertEqual(
                target.read_text(),
                "#CHROM\tPOS\tREF\tALT\n"
                "chr1\t100\tA\tG\n"
                "chr2\t250\tT\tC\n",
            )


if __name__ == "__main__":
    unittest.main()
