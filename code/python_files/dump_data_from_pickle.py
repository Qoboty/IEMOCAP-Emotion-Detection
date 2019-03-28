import os
import sys
import numpy as np
import pickle
import copy
import wave
import scipy

from features import *
from helper import *
import kaldiio

''' dump wav, text, label from pkl '''

code_path = os.path.dirname(os.path.realpath(os.getcwd()))
emotions_used = np.array(['ang', 'exc', 'neu', 'sad'])
data_path = code_path + "/../data/"
sessions = ['Session1', 'Session2', 'Session3', 'Session4', 'Session5']
framerate = 16000

dump_dir='/nfs/project/datasets/opensource_data/emotion/iemocap/data'

def save_wav(data, filename, rate=framerate):
    assert data.dtype == np.int16, data.dtype
    scipy.io.wavfile.write(filename, rate, data)

def save_text(data, filename):
    print('txt', filename, 'data', data)
    with open(filename, 'w') as f:
        f.write(data)

def save_label(data, filename):
    print('label', filename, 'data', data)
    with open(filename, 'w') as f:
        f.write(data)

with open(data_path + 'data_collected.pickle', 'rb') as handle:
    datas = pickle.load(handle)
    # data : dict_keys(['start', 'end', 'id', 'v', 'a', 'd', 'emotion', 'emo_evo', 'signal', 'transcription', 'mocap_hand', 'mocap_rot', 'mocap_head'])
    for data in datas:
        # Ses01F_impro01_F000  Excuse me.  neu
        key = data['id']
        samples = data['signal'] # int16 
        text = data['transcription']
        label = data['emotion']
        
        dirpath = os.path.join(dump_dir, key)
        if not os.path.exists(dirpath):
            os.makedirs(dirpath)
        filepath = os.path.join(dirpath, key) + '.wav' 
        save_wav(np.array(samples, dtype=np.int16), filepath)
        filepath = os.path.join(dirpath, key) + '.txt' 
        save_text(text, filepath)
        filepath = os.path.join(dirpath, key) + '.label' 
        save_label(label, filepath)
