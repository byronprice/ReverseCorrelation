#!/bin/bash -l

# 24 hour time limit
#$ -l h_rt=24:00:00
#$ -N RevCorr1
#$ -j y
#$ -o RevCorr1Outputs.txt
#$ -l mem_per_core=16G
#$ -pe omp 16

module load matlab/2017a

matlab -nodisplay -r "RevCorrMov2(43652,20170421,'pink');exit"
