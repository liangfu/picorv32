#!/usr/bin/env python3

import os, sys

out = """WIDTH=32;
DEPTH=4096;

ADDRESS_RADIX=HEX;
DATA_RADIX=HEX;

CONTENT BEGIN
"""
idx = 0
with open(sys.argv[1], 'r') as fp:
    lines = fp.readlines()
    for idx, line in enumerate(lines):
        out += (f"\t{idx:03x}  :   {line.strip()};\n").upper()
        # if idx>30:
        #     break
out += (f"\t[{idx+1:03x}..FFF]  :   00000000;\n").upper()
out += "END;\n"

# print(out)
with open(sys.argv[1].replace(".hex", '.mif'), 'w') as fp:
    fp.write(out)
