#!/bin/bash

# Copyright 2017 Johns Hopkins University (Shinji Watanabe)
#  Apache 2.0  (http://www.apache.org/licenses/LICENSE-2.0)

echo "$0 $*" >&2 # Print the command line for logging
. ./path.sh

nj=1
cmd=run.pl
nlsyms=""
space="_"
lang=""
feat="" # feat.scp
oov="<unk>"
bpecode=""
verbose=0
filetype=""
preprocess_conf=""
out="" # If omitted, write in stdout

. utils/parse_options.sh

if [ $# != 3 ]; then
    cat << EOF 1>&2
Usage: $0 <data-dir> <dict> <tmp-dri>
e.g. $0 data/train data/lang_1char/train_units.txt
Options:
  --nj <nj>                                        # number of parallel jobs
  --cmd (utils/run.pl|utils/queue.pl <queue opts>) # how to run jobs.
  --feat <feat-scp>                                # feat.scp
  --oov <oov-word>                                 # Default: <unk>
  --out <outputfile>                               # If omitted, write in stdout
  --filetype <mat|hdf5|sound.hdf5>                 # Specify the format of feats file
  --preprocess-conf <json>                         # Apply preprocess to feats when creating shape.scp
  --verbose <num>                                  # Default: 0
  --space < _|<space> >                            # replace space to [_|<space>] 
EOF
    exit 1;
fi

set -euo pipefail

dir=$1
dic=$2
tmpdir=$3
#tmpdir=$(mktemp -d ${dir}/tmp-XXXXX)
echo "tmpdir : ${tmpdir}"
#trap 'rm -rf ${tmpdir}' EXIT

# 1. Create scp files for inputs
#   These are not necessary for decoding mode, and make it as an option
mkdir -p ${tmpdir}/input
if [ -n "${feat}" ]; then
    cat ${feat} > ${tmpdir}/input/feat.scp

    # gen key to filetype
    # Dump in the "legacy" style JSON format
    if [ -n "${filetype}" ]; then
        awk -v filetype=${filetype} '{print $1 " " filetype}' ${feat} \
            > ${tmpdir}/input/filetype.scp
    fi

    # gen key to feat shape 
    feat_to_shape.sh --cmd "${cmd}" --nj ${nj} \
        --filetype "${filetype}" \
        --preprocess-conf "${preprocess_conf}" \
        --verbose ${verbose} ${feat} ${tmpdir}/input/shape.scp
fi

# 2. Create scp files for outputs
mkdir -p ${tmpdir}/output
if [ -n "${bpecode}" ]; then
    paste -d " " <(awk '{print $1}' ${dir}/text) <(cut -f 2- -d" " ${dir}/text \
        | spm_encode --model=${bpecode} --output_format=piece) \
        > ${tmpdir}/output/token.scp
elif [ -n "${nlsyms}" ]; then
    text2token.py -s 1 -n 1 -l ${nlsyms} ${dir}/text > ${tmpdir}/output/token.scp
elif [ -n "${space}" ]; then
    text2token.py -s 1 -n 1 --space ${space} ${dir}/text > ${tmpdir}/output/token.scp
else
    text2token.py -s 1 -n 1 ${dir}/text > ${tmpdir}/output/token.scp
fi
# convert token to int id
< ${tmpdir}/output/token.scp utils/sym2int.pl --map-oov ${oov} -f 2- ${dic} > ${tmpdir}/output/tokenid.scp
# +2 comes from CTC blank and EOS
vocsize=$(tail -n 1 ${dic} | awk '{print $2}')
odim=$(echo "$vocsize + 2" | bc) # output dim per timestep, `vocabszie + 2`
# gen key to token shape
< ${tmpdir}/output/tokenid.scp awk -v odim=${odim} '{print $1 " " NF-1 "," odim}' > ${tmpdir}/output/shape.scp

cat ${dir}/text > ${tmpdir}/output/text.scp


# 3. Create scp files for the others
mkdir -p ${tmpdir}/other
if [ -n "${lang}" ]; then
    awk -v lang=${lang} '{print $1 " " lang}' ${dir}/text > ${tmpdir}/other/lang.scp
fi
cat ${dir}/utt2spk  > ${tmpdir}/other/utt2spk.scp

echo "Done"
exit 0

# 4. Merge scp files into a JSON file
opts=""
for intype in input output other; do
    if [ ${intype} != other ]; then
        opts+="--${intype}-scps "
    else
        opts+="--scps "
    fi

    for x in ${tmpdir}/${intype}/*.scp; do
        k=$(basename ${x} .scp)
        if [ ${k} = shape ]; then
            opts+="shape:${x}:shape "
        else
            opts+="${k}:${x} "
        fi
    done
done

if [ -n "${out}" ]; then
    opts+="-O ${out}"
fi

merge_scp2json.py --verbose ${verbose} ${opts}

#rm -fr ${tmpdir}
