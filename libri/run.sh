#!/bin/bash

stage=2       # start from -1 if you need to start from data download
stop_stage=100
ngpu=0         # number of gpus ("0" uses cpu, otherwise use gpu)
debugmode=1
dumpdir=dump   # directory to dump full features


# feature configuration
do_delta=false
compress=false

datadir=/nfs/project/datasets/opensource_data/librispeech

# bpemode (unigram or bpe or char word)
nbpe=5000
bpemode=unigram
space='_'

. utils/parse_options.sh || exit 1;
. ./path.sh
. ./cmd.sh


# Set bash to 'debug' mode, it will exit on :
# -e 'error', -u 'undefined variable', -o ... 'error in pipeline', -x 'print commands',
set -e
set -u
set -x 

train_set=train_960
train_dev=dev
recog_set="test_clean test_other dev_clean dev_other"

if [ ${stage} -le 0 ] && [ ${stop_stage} -ge 0 ]; then
  for part in dev-clean test-clean dev-other test-other train-clean-100 train-clean-360 train-other-500; do
    local/data_prep.sh ${datadir}/LibriSpeech/${part} data/${part//-/_}
  done
fi


feat_tr_dir=${dumpdir}/${train_set}/delta${do_delta}; mkdir -p ${feat_tr_dir}
feat_dt_dir=${dumpdir}/${train_dev}/delta${do_delta}; mkdir -p ${feat_dt_dir}
if [ ${stage} -le 1 ] && [ ${stop_stage} -ge 1 ]; then
    echo "stage 1: Feature Generation"
    fbankdir=fbank
    for x in dev_clean test_clean dev_other test_other train_clean_100 train_clean_360 train_other_500; do
        steps/make_fbank_pitch.sh --cmd "$train_cmd" --nj 32 --write-utt2num-frames true \
            data/${x} exp/make_fbank/${x} ${fbankdir}
    done

    utils/combine_data.sh --extra_files utt2num_frames data/${train_set}_org data/train_clean_100 data/train_clean_360 data/train_other_500
    utils/combine_data.sh --extra_files utt2num_frames data/${train_dev}_org data/dev_clean data/dev_other


    # remove utt having more than 3000 frames
    # remove utt having more than 400 characters
    remove_longshortdata.sh --maxframes 3000 --maxchars 400 data/${train_set}_org data/${train_set}
    remove_longshortdata.sh --maxframes 3000 --maxchars 400 data/${train_dev}_org data/${train_dev}

    # cmopute global CMVN
    compute-cmvn-stats scp:data/${train_set}/feats.scp data/${train_set}/cmvn.ark

    dump.sh --cmd "$train_cmd"  --nj 80 --do_delta ${do_delta} --compress ${compress} \
        data/${train_set}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/train ${feat_tr_dir}
    dump.sh --cmd "$train_cmd"  --nj 80 --do_delta ${do_delta} --compress ${compress} \
        data/${train_dev}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/dev ${feat_dt_dir}
    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}; mkdir -p ${feat_recog_dir}
        dump.sh --cmd "$train_cmd" --nj 32 --do_delta ${do_delta} --compress ${compress} \
            data/${rtask}/feats.scp data/${train_set}/cmvn.ark exp/dump_feats/recog/${rtask} \
            ${feat_recog_dir}
    done
fi


dict=data/lang_char/${train_set}_char_units.txt
echo "char dictionary: ${dict} "
if [ ${stage} -le 2 ] && [  ${stop_stage} -ge 2 ]; then
    ### Task dependent. You have to check non-linguistic symbols used in the corpus.
    echo "stage 2: (charactor) Dictionary and label Data Preparation"
    mkdir -p data/lang_char/
    cut -f 2- -d' ' data/${train_set}/text > data/lang_char/input.txt
    < data/lang_char/input.txt python text2token.py -s 0 -n 1 --space ${space} > data/lang_char/tokens.txt
    < data/lang_char/tokens.txt python text2vocabulary.py > ${dict}
    wc -l  ${dict}

    # make json labels
    ./data2json.sh --feat ${feat_tr_dir}/feats.scp  --space ${space} \
        data/${train_set} ${dict} data/${train_set}/lang_char
    copy-int-vector ark,t:data/${train_set}/lang_char/output/tokenid.scp \
        ark,scp:$(realpath ${feat_tr_dir})/label_char.ark,$(realpath ${feat_tr_dir})/label_char.scp

    ./data2json.sh --feat ${feat_dt_dir}/feats.scp  --space ${space} \
        data/${train_dev} ${dict} data/${train_dev}/lang_char
    copy-int-vector ark,t:data/${train_dev}/lang_char/output/tokenid.scp \
        ark,scp:$(realpath ${feat_dt_dir})/label_char.ark,$(realpath ${feat_dt_dir})/label_char.scp

    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}
        ./data2json.sh --feat ${feat_recog_dir}/feats.scp --space ${space} \
            data/${rtask} ${dict} data/${rtask}/lang_char
        copy-int-vector ark,t:data/${rtask}/lang_char/output/tokenid.scp \
            ark,scp:$(realpath ${feat_recog_dir})/label_char.ark,$(realpath ${feat_recog_dir})/label_char.scp
    done
fi

dict=data/lang_char/${train_set}_${bpemode}${nbpe}_units.txt
bpemodel=data/lang_char/${train_set}_${bpemode}${nbpe}
echo "dictionary: ${dict}"
if [ ${stage} -le 3 ] && [ ${stop_stage} -ge 3 ]; then
    ### Task dependent. You have to check non-linguistic symbols used in the corpus.
    echo "stage 3: (unigram) Dictionary and Label Data Preparation"
    mkdir -p data/lang_char/
    echo "<unk> 1" > ${dict} # <unk> must be 1, 0 will be used for "blank" in CTC
    cut -f 2- -d" " data/${train_set}/text > data/lang_char/input.txt
    spm_train --input=data/lang_char/input.txt --vocab_size=${nbpe} --model_type=${bpemode} --model_prefix=${bpemodel} --input_sentence_size=100000000
    spm_encode --model=${bpemodel}.model --output_format=piece < data/lang_char/input.txt | tr ' ' '\n' | sort | uniq | awk '{print $0 " " NR+1}' >> ${dict}
    wc -l ${dict}

    # make json labels
    ./data2json.sh --feat ${feat_tr_dir}/feats.scp --bpecode ${bpemodel}.model \
        data/${train_set} ${dict} data/${train_set}/lang_${bpemode} 
    copy-int-vector ark,t:data/${train_set}/lang_${bpemode}/output/tokenid.scp \
        ark,scp:$(realpath ${feat_tr_dir})/label_${bpemode}.ark,$(realpath ${feat_tr_dir})/label_${bpemode}.scp

    ./data2json.sh --feat ${feat_dt_dir}/feats.scp --bpecode ${bpemodel}.model \
        data/${train_dev} ${dict} data/${train_dev}/lang_${bpemode}
    copy-int-vector ark,t:data/${train_dev}/lang_${bpemode}/output/tokenid.scp \
        ark,scp:$(realpath ${feat_dt_dir})/label_${bpemode}.ark,$(realpath ${feat_dt_dir})/label_${bpemode}.scp

    for rtask in ${recog_set}; do
        feat_recog_dir=${dumpdir}/${rtask}/delta${do_delta}
        ./data2json.sh --feat ${feat_recog_dir}/feats.scp --bpecode ${bpemodel}.model \
            data/${rtask} ${dict} data/${rtask}/lang_${bpemode}
        copy-int-vector ark,t:data/${rtask}/lang_${bpemode}/output/tokenid.scp \
            ark,scp:$(realpath ${feat_recog_dir})/label_${bpemode}.ark,$(realpath ${feat_recog_dir})/label_${bpemode}.scp
    done
fi
