#!/bin/bash
# WebKitGTK needs 1-2 GB per compile job; at one job per core (32 here) it
# ran the host out of memory and the build was killed. Cap it at 12.
# (LFS's ninja honours NINJAJOBS.)
sed -i 's|^unset NINJAJOBS$|export NINJAJOBS=12|; s|^export MAKEFLAGS="-j$(nproc)"$|export MAKEFLAGS="-j12"|' "$1"
grep -q '^export NINJAJOBS=12$' "$1"
