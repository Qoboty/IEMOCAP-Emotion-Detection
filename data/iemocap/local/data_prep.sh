#!/bin/bash

# gen wav.scp, text.scp, labels.scp

set -x
set -e

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <src-dir> <dst-dir>"
  echo "e.g.: $0 /export/data/LibriSpeech/dev-clean data/dev-clean"
  exit 1
fi

src=$1
dst=$2

mkdir -p $dst || exit 1;
[ ! -d $src ] && echo "$0: no such directory $src" && exit 1;
#
#wav_scp=$dst/wav.scp; [[ -f "$wav_scp" ]] && rm $wav_scp
#trans=$dst/text; [[ -f "$trans" ]] && rm $trans
#labels=$dst/label.scp; [[ -f "$labels" ]] && rm $labels
#utt2spk=$dst/utt2spk; [[ -f "$utt2spk" ]] && rm $utt2spk
#spk2gender=$dst/spk2gender; [[ -f $spk2gender ]] && rm $spk2gender
#
#echo "current work dir : $PWD"
#
#for reader_dir in $(find -L $src -mindepth 1 -maxdepth 1 -type d | sort); do
#    reader=$(basename $reader_dir)
#    reader_gender=${reader:5:1}
#    if [ "$reader_gender" != 'F' ] && [ "$reader_gender" != 'M' ]; then
#        echo "$0: unexpected gender: '$reader_gender'"
#        exit 1;
#    fi
#
#    # wav 
#    find -L $reader_dir/ -iname "*.wav" | sort | xargs -I% basename % .wav | \
#        awk -v "dir=$reader_dir" '{printf "%s %s/%s.wav\n", $0, dir, $0}' >> $wav_scp || exit 1
#
#    # text
#    for txtfile in $(find -L $reader_dir/ -iname "*.txt" | sort); do
#        key=$(basename $txtfile .txt)
#        text=$(cat < $txtfile | tr [:lower:] [:upper:]) 
#        echo "$key $text" >> $trans
#    done
#
#    # label
#    for labelfile in $(find -L $reader_dir/ -iname "*.label" | sort); do
#        key=$(basename $labelfile .label)
#        emotion=$(cat $labelfile)
#        echo "$key $emotion" >> $labels
#    done
#
#done

wav_scp=$dst/wav.scp; 
trans=$dst/text; 
labels=$dst/label.scp; 

# copy vocab from libri
vocabdir=/nfs/cold_project/dataset/opensource/librispeech/prepare_data/data/lang_char/
[[ -d data/vocab ]] && rm -rf data/vocab 
mkdir -p data/vocab  || exit 1
cp $vocabdir/*units.txt data/vocab
echo "copy vocab from libri dir: $vocabdir"

vocabfile=data/vocab/train_960_char_units.txt
echo "vocab file: $vocabfile"

[[ -f $dst/non-lang-syms.txt ]] && rm $dst/non-lang-syms.txt 
[[ -f $dst/special_syms_not_in_vocab.txt ]] && rm $dst/special_syms_not_in_vocab.txt 
[[ -f $dst/special_syms.txt ]] && rm $dst/special_syms.txt 
[[ -f $dst/vocab ]] && rm $dst/vocab 
[[ -f $dst/text.filter.non-lang ]] && rm $dst/text.filter.non-lang
[[ -f $dst/text.filter.non-lang.special ]] && rm $dst/text.filter.non-lang.special

# generage non lang syms, e.g. [laugher] etc. 
cut -d' ' -f 2- $trans | tr [:lower:] [:upper:] | grep -oP '\[[A-Z]*\]' | tr -d '.?!:,' | sort -u > $dst/non-lang-syms.txt || exit 1

# generage vocab
cut -d' ' -f 2- $trans | tr [:lower:] [:upper:] | ./text2token.py -l $dst/non-lang-syms.txt -n 1 --space '' | ./text2vocabulary.py -o $dst/vocab || exit 1

# extract specail syms not int vocab
comm -13 <(sort -u $vocabfile | cut -d' ' -f 1) <(sort -u $dst/vocab | cut -d' ' -f 1) > $dst/special_syms_not_in_vocab.txt || exit 1
comm -23 <(sort -u $dst/special_syms_not_in_vocab.txt) <(sort -u $dst/non-lang-syms.txt) > $dst/special_syms.txt || exit 1

# filter out non lang syms
cut -d' ' -f 1 $trans > $dst/key
./filt.py --exclude $dst/non-lang-syms.txt <(cut -d ' ' -f 2- $trans | tr "-" " " | tr -d '.,') > $dst/value
paste -d ' ' $dst/key $dst/value > $dst/text.filter.non-lang

# filter out special syms
filter=$(echo $(< $dst/special_syms.txt) | tr -d " ")
cut -d' ' -f 2- $dst/text.filter.non-lang | tr -d ${filter} > $dst/value
paste -d ' ' $dst/key $dst/value > $dst/text.filter.non-lang.special
rm $dst/key $dst/value 
mv $dst/text $dst/text.org
cp $dst/text.filter.non-lang.special $dst/text

# sort  
for x in $trans $labels $wav_scp; do
    mv $x ${x}.unsort
    sort ${x}.unsort -o ${x}.sort
    mv ${x}.sort ${x} 
    unlink ${x}.unsort
done

# dummy spk
utt2spk=$dst/utt2spk; [[ -f $utt2spk ]] && rm $utt2spk
spk2gender=$dst/spk2gender; [[ -f $spk2gender ]] && rm $spk2gender

temp=$(mktemp -d /tmp/iemocap.XXXXXX)
trap "rm -rf $temp" EXIT INT TERM QUIT

spkfile=$temp/spk
genderfile=$temp/gender
keyfile=$temp/key
for key in $(cut -d' ' -f 1 $trans); do
    speaker=${key: -4}
    gender=${key: -4:1}
    echo "$speaker" >> $spkfile
    echo "$gender" >> $genderfile
    echo "$key" >> $keyfile
done

paste $keyfile $spkfile >>$utt2spk || exit 1

# dummy gender
paste $keyfile $genderfile >>$spk2gender || exit 1

spk2utt=$dst/spk2utt
utils/utt2spk_to_spk2utt.pl <$utt2spk >$spk2utt || exit 1

ntrans=$(wc -l <$trans)
nutt2spk=$(wc -l <$utt2spk)
! [ "$ntrans" -eq "$nutt2spk" ] && \
    echo "Inconsistent #transcripts($ntrans) and #utt2spk($nutt2spk)" && exit 1;

./validate_data_dir.sh --no-feats $dst || exit 1;

echo "$0: successfully prepared data in $dst"

exit 0
