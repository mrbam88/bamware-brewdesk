#!/bin/sh
set -eu

legacy_pattern='Bamware''Cafe|bamware[-._ ]?''cafe|bam''Cafe|wfh[-._ ]?''Cafe'

if git grep -Eni "$legacy_pattern" -- .; then
  printf '%s\n' 'Legacy product identity detected. BrewDesk is the only canonical app identity.' >&2
  exit 1
fi
