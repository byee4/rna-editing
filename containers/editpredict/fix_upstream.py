#!/usr/bin/env python3
"""Patch upstream EditPredict scripts for the Python 3 container runtime."""

from pathlib import Path


EDITPREDICT_ROOT = Path("/opt/editpredict")


def patch_get_seq() -> None:
    path = EDITPREDICT_ROOT / "get_seq.py"
    text = path.read_text()
    text = text.replace("\t", "    ")
    text = text.replace("args.length/2", "args.length//2")
    # Upstream looks sequences up by a numeric chromosome INDEX
    # (seqs[get_chr(name)-1]), assuming bare numeric names ('1','2',...,'X') and a
    # fixed chr1..chrM record order. That dies on 'chr'-prefixed GRCh38 names. Load
    # the FASTA into a name-keyed dict and index by the chromosome name verbatim.
    text = text.replace(
        'seqs = list(SeqIO.parse(args.fasta, "fasta"))',
        'seqs = SeqIO.to_dict(SeqIO.parse(args.fasta, "fasta"))',
    )
    text = text.replace("chr=get_chr(words[0])-1", "chr=words[0]")
    path.write_text(text)


def patch_edit_predict() -> None:
    # Upstream editPredict.py prints only the raw prediction arrays (no coordinates)
    # and uppercases the whole line (corrupting chrom names). Rewrite it to emit a
    # mappable TSV: `chrom  pos  prob_edit  pred_class`, one row per scorable input
    # line, uppercasing only the flanking sequence. The input rows (from get_seq.py)
    # are `chrom  pos  sequence`; N-containing sequences are unscorable and skipped.
    path = EDITPREDICT_ROOT / "editPredict.py"
    path.write_text(
        """import argparse
import numpy as np
from keras.models import model_from_json
from argparse import RawTextHelpFormatter


parser = argparse.ArgumentParser(formatter_class=RawTextHelpFormatter)
parser.add_argument("-f", "--txt", help="input txt file", required=True)
parser.add_argument("-c", "--json", help="input model construction JSON", required=True)
parser.add_argument("-w", "--h5", help="input model weights H5", required=True)
args = parser.parse_args()

np.set_printoptions(threshold=np.inf)
model = model_from_json(open(args.json).read())
model.load_weights(args.h5)
# The CNN takes a fixed-length window (model.input_shape == (None, L, 4, 1)).
expected_len = model.input_shape[1]

alphabet = "ACGT"
char_to_int = {c: i for i, c in enumerate(alphabet)}

# Score in batches. Calling model.predict() once per position leaks memory via
# repeated tf.function retracing and OOMs on large candidate sets (tens of
# thousands of sites); batching keeps memory flat and is far faster.
BATCH = 8192
batch_x = []
batch_meta = []


def flush():
    if not batch_meta:
        return
    x = np.stack(batch_x).reshape(len(batch_x), expected_len, 4, 1)
    preds = model.predict(x, batch_size=512, verbose=0)
    for (chrom, pos), pred in zip(batch_meta, preds):
        print("%s\\t%s\\t%.6f\\t%d" % (chrom, pos, float(pred[1]), int(np.argmax(pred))))
    del batch_x[:]
    del batch_meta[:]


with open(args.txt) as tf1:
    for line in tf1:
        fields = line.rstrip("\\n").rstrip("\\r").split("\\t")
        if len(fields) < 3:
            continue
        chrom = fields[0]
        pos = fields[1]
        sequence = fields[-1].upper()
        if "N" in sequence:
            continue
        # get_seq.py yields a short (or, via negative-index slicing, empty) flank for
        # positions within half a window of a contig start/end; those can't be scored
        # and would crash model.predict on the wrong input shape. Skip them.
        if len(sequence) != expected_len:
            continue

        onehot = np.zeros((expected_len, len(alphabet)), dtype="float32")
        for i, ch in enumerate(sequence):
            onehot[i, char_to_int[ch]] = 1
        batch_x.append(onehot)
        batch_meta.append((chrom, pos))
        if len(batch_meta) >= BATCH:
            flush()
    flush()
"""
    )


def main() -> None:
    patch_get_seq()
    patch_edit_predict()


if __name__ == "__main__":
    main()
