#!/usr/bin/env python3
"""Patch upstream EditPredict scripts for the Python 3 container runtime."""

from pathlib import Path


EDITPREDICT_ROOT = Path("/opt/editpredict")


def patch_get_seq() -> None:
    path = EDITPREDICT_ROOT / "get_seq.py"
    text = path.read_text()
    text = text.replace("\t", "    ")
    text = text.replace("args.length/2", "args.length//2")
    path.write_text(text)


def patch_edit_predict() -> None:
    path = EDITPREDICT_ROOT / "editPredict.py"
    path.write_text(
        """import argparse
import numpy as np
from keras.models import model_from_json
from numpy import array
from argparse import RawTextHelpFormatter


parser = argparse.ArgumentParser(formatter_class=RawTextHelpFormatter)
parser.add_argument("-f", "--txt", help="input txt file", required=True)
parser.add_argument("-c", "--json", help="input model construction JSON", required=True)
parser.add_argument("-w", "--h5", help="input model weights H5", required=True)
args = parser.parse_args()

np.set_printoptions(threshold=np.inf)
model = model_from_json(open(args.json).read())
model.load_weights(args.h5)

alphabet = "ACGT"
char_to_int = {c: i for i, c in enumerate(alphabet)}

with open(args.txt) as tf1:
    for line in tf1:
        line = line.upper().strip("\\n").split("\\t")
        if "N" in line[-1]:
            continue

        sequence = line[-1]
        values = array(list(sequence))
        integer_encoded = [char_to_int[char] for char in values]
        onehot_encoded = []
        for value in integer_encoded:
            letter = [0 for _ in range(len(alphabet))]
            letter[value] = 1
            onehot_encoded.append(letter)

        onehot_encoded = array(onehot_encoded)
        onehot_encoded = onehot_encoded.reshape(1, len(sequence), 4, 1)
        result = model.predict(onehot_encoded)
        result1 = np.argmax(result, axis=1)
        print(result, result1)
"""
    )


def main() -> None:
    patch_get_seq()
    patch_edit_predict()


if __name__ == "__main__":
    main()
