import gzip
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(
    os.path.dirname(__file__), "..", "pipelines", "Morales_et_al", "scripts"))

import compare_all_tools as cat  # noqa: E402

HEADER = ("chr\tcoordinate\tstrand\tifSNP\tgene\treference_base\tupstream_1base\t"
          "downstream_1base\tmajor_base\tmajor_count\ttot_count\tmajor_ratio\t"
          "if_MI\tMI\tpvalue_MI\testimated_allelic_ratio\tifNEG\tif_GLM\t"
          "pvalue_GLM\tRNAE_t\tA\tC\tG\tT\tifRNAE")


def _row(rowname, chrom, coord, rnae_t, tot, ratio, ifrnae):
    # 26 physical fields: leading unnamed row-name + 25 named columns
    cols = [rowname, chrom, str(coord), "+", "0", "GENE", "A", "A", "G", "A",
            "30", str(tot), "0.6", "1", "0.5", "0.001", str(ratio), "0", "1",
            "0.2", rnae_t, "30", "0", "20", "0", str(ifrnae)]
    return "\t".join(cols)


class TestParseGiremi(unittest.TestCase):
    def _write(self, rows):
        fd, path = tempfile.mkstemp(suffix=".txt.gz")
        os.close(fd)
        with gzip.open(path, "wt") as fh:
            fh.write(HEADER + "\n")
            for r in rows:
                fh.write(r + "\n")
        return path

    def test_mi_and_glm_editing_sites_kept(self):
        path = self._write([
            _row("chr1|100|+", "chr1", 100, "AG", 50, 0.4, 1),   # MI-predicted
            _row("chr2|200|-", "chr2", 200, "TC", 80, 0.25, 2),  # GLM-predicted
        ])
        sites = cat.parse_giremi(path)
        os.unlink(path)
        self.assertEqual(sites[("chr1", "100")], (50.0, 0.4, 0.4))
        self.assertEqual(sites[("chr2", "200")], (80.0, 0.25, 0.25))

    def test_non_editing_excluded(self):
        path = self._write([_row("chr1|100|+", "chr1", 100, "AG", 50, 0.4, 0)])
        sites = cat.parse_giremi(path)
        os.unlink(path)
        self.assertEqual(sites, {})

    def test_non_ai_edit_type_excluded(self):
        # ifRNAE=1 but RNAE_t is a non-A>I class -> filtered by EDIT_TYPES
        path = self._write([_row("chr1|100|+", "chr1", 100, "AC", 50, 0.4, 1)])
        sites = cat.parse_giremi(path)
        os.unlink(path)
        self.assertEqual(sites, {})

    def test_empty_file(self):
        fd, path = tempfile.mkstemp(suffix=".txt.gz")
        os.close(fd)
        open(path, "w").close()
        self.assertEqual(cat.parse_giremi(path), {})
        os.unlink(path)


if __name__ == "__main__":
    unittest.main()
