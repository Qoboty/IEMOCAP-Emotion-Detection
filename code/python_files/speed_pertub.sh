#!/bin/bash

for file in `ls -1`;do
  if [ -d $file ];then
    for wav in $(find $file -name *.wav);do
      for factor in 0.9 1.1; do
        echo $file $wav ${wav}.perturb.${factor}.wav $factor
        sox -t wav $wav -t wav ${wav}.perturb.${factor}.wav speed $factor
      done
    done
  fi
done
