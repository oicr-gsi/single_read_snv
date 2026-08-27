#!/bin/bash
set -o nounset
set -o errexit
set -o pipefail

cd $1

echo "Count of PASS variants from the output vcfi files"
for v in *vcf.gz;do zcat $v | grep -v ^# | awk '$7=="PASS"' | wc -l;done
