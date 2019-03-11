#!/bin/bash

stage=1
stop_stage=1
ngpu=0
debugmode=1
dumpdir=dump


# features
do_delta=false
compress=false

datadir=/nfs/project/datasets/opensource_data/emotion/iemocap/data

npbe=5000
bpemode=unigram
space='_'

. utils/parse_options.sh || exit 1;
. ./path.sh
. ./cmd.sh

echo $PATH
echo $LD_LIBRARY_PATH

# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -x

if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
    local/data_prep.sh ${datadir} data/test
fi


# test feat
train_set=iemocap_test
feat_tr_dir=${dumpdir}/${train_set}/delta${do_delta}; mkdir -p ${feat_tr_dir}
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    echo "stage 1: Feature Generation"
    fbankdir=fbank
    #for x in test; do
    #    ./make_fbank_pitch.sh --cmd "$train_cmd" --nj 32 --write-utt2num-frames true \
    #          data/${x} exp/make_fbank/${x} ${fbankdir}
    #done

    #utils/combine_data.sh --extra_files utt2num_frames --skip-fix true data/${train_set}_org data/test

    # remove utt having more than 3000 frames
    # remove utt having more than 400 characters
    #./remove_longshortdata.sh --maxframes 3000 --maxchars 400 data/${train_set}_org data/${train_set} || exit 1

    # cmopute global CMVN, cp from libri
    #compute-cmvn-stats scp:data/${train_set}/feats.scp data/${train_set}/cmvn.ark
    libri_train_set=/nfs/cold_project/dataset/opensource/librispeech/prepare_data/data/train_960
    cp $libri_train_set/cmvn.ark data/${train_set}/cmvn.ark

    #creat feat.scp, feat.ark, with apply cmvn and/or add-delta
    dump.sh --cmd "$train_cmd"  --nj 80 --do_delta ${do_delta} --compress ${compress} \
            data/${train_set}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/${train_set} ${feat_tr_dir}
fi


if [ ${stage} -le 2 ] && [  ${stop_stage} -ge 2 ]; then
  echo "Stage 2: (charactor) label"
  # make json labels
  ./data2json.sh --feat ${feat_tr_dir}/feats.scp  --space ${space} \
        data/${train_set} ${dict} data/${train_set}/lang_char
  copy-int-vector ark,t:data/${train_set}/lang_char/output/tokenid.scp \
        ark,scp:$(realpath ${feat_tr_dir})/label_char.ark,$(realpath ${feat_tr_dir})/label_char.scp

fi

