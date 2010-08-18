#!/usr/bin/env python

# Author: Andrew Watts
#
#
#    Copyright 2010 Andrew Watts and the University of Rochester BCS Department
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Lesser General Public License version 2.1 as
#    published by the Free Software Foundation.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Lesser General Public License for more details.
#
#    You should have received a copy of the GNU Lesser General Public License
#    along with this program.
#    If not, see <http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>

from __future__ import division
import subprocess
import os
import re
import shutil
import wave

def find_manual_boundaries():
    pass

def process_audio():
    """
    Do some preprocessing of the wavefiles with Sphinx3 tools
    """
    subprocess.Popen(['wave2feat',
                        '-i', 'audio.wav', #TODO: this should be parametric
                        '-o', 'mfc',
                        '-mswav', 'yes',
                        '-seed', '2'])

    with open('ep', 'w') as ep_outfile:
        subprocess.Popen(['sphinx3_ep',
            '-input', 'mfc',
            '-mean', 'S3EP_MODELS/means', #FIXME: define S3EP_MODELS
            '-mixw', 'S3EP_MODELS/mixture_weights',
            '-var', 'S3EP_MODELS/variances'],
            stdout = ep_outfile)

def get_wave_length(wave_fn):
    """
    Returns the length in milliseconds of a wavefile
    """
    wf = wave.open(wave_fn, 'r')
    return int((wf.getnframes() / wf.getframerate()) * 100)

def downsample_wav(wave_fn, dest_fn):
    """
    Resamples a wavefile down to 16000Hz mono
    """
    wf = wave.open(wave_fn, 'r')
    if wf.getframerate() != 16000:
        wfo = wave.open(dest_fn, 'w')
        wfo.setframerate(16000) # 16000Hz
        wfo.setnchannels(1) # mono
        wfo.setsampwidth(2) # 16bit
        wfo.writeframes(wf.readframes(wf.getnframes()))
    else:
        shutil.copy(wave_fn, 'audio.wav')

def clean_transcript(trans_fn):
    """
    Removes certain material from the transcripts for the benefit of Sphix3
    """
    with open(trans_fn, 'r') as transcript:
        new_trans = []
        for line in transcript:
            #FIXME: what are we getting rid of any why?
            line = re.sub('@\S+', '', line)
            line = re.sub('\/', '', line)
            new_trans.append(line)
        return new_trans
  
def write_to_file(lines, out_fn):
    """
    Writes the contents of an array of strings to a file
    """
    with open(out_fn, 'w') as f:
        for line in lines:
            f.write(line + '\n')

def resegment_transcript():
    """
    Creates file "insent" based on the "ctl" and "transcript" files
    """
    unttNum = 0
    with open('ctl', 'r') as ctl:
          for ctline in ctl:
            utt = re.compile('utt(?:\d+-)?(\d+)$', re.I)
            res = re.search(utt,ctline)
            if res:
                segname = res.group(0)
                endUttNum = res.group(1)
                words = []
                while uttNum < endUttNum:
                    with open('transcript', 'r') as transcript:
                        transline = transcript.read()
                        uttNum += 1
                        transline = transline.strip().upper()
                        transline = re.sub(r'\[PARTIAL (\w+).*?\]', lambda m: m.group(0), transline)
                        transline = re.sub(r'\<.*?\>','', transline)
                        transline = re.sub(r'\[.*?\]', '', transline)
                        words.append(transline)
                with open('insent', 'w') as insent:
                    insent.write(' '.join(words) + '(' + segname + ')\n')


def get_transcript_vocab():
    """
    Make a list of unique words in the transcript
    """
    wordlist = set()
    wds = re.compile(r"([\w'-]+)")
    with open('transcript', 'r') as transcript:
        for line in transcript:
            w = wds.search(wds, line)
            if w:
                wordlist.add(w.group().upper())
    wordlist = list(wordlist)
    wordlist.sort()

    with open('vocab.txt', 'w') as vocab:
        for w in wordlist:
            vocab.write(w + '\n')

def subdic(vocab_fn, dict_fn, subdic_fn, ood_fn = '',
        verbose = False, novar = False):
    """
    Create a dictionary of words in the transcript
    """
    vocab = {}
    header_re = re.compile('/^\#\#/')
    tag_re = re.compile('/^</')
    with open(vocab_fn, 'r') as vocab:
        for word in vocab:
            if not re.search(header_re, word):
                word = re.sub('^\s*(\S+)\s*$', lambda m: m.group(0), word)
                if not re.search(tag_re, word):
                    vocab[word] = 1
    if verbose:
        print "Read {0} words.".format(len(vocab))

    with open(dict_fn, 'r') as dic:
        with open(subdic_fn, 'w') as subdic:
            #FIXME: what are these regexes about?
            re1 = re.compile('/^([^\s\(]+)/')
            re2 = re.compile('/^([^\s]+)\s/')
            for line in dic:
                word = ""
                if novar:
                    x = re.search(re1, line)
                    word = x.groups(0)
                else:
                    x = re.search(re2, line)
                    word = x.groups(0)

                if vocab.has_key(word):
                    subdic.write(word + '\n')
                    vocab[word] = 2
    if ood_fn:
        with open(ood_fn, 'w') as ood:
            for word in sorted(vocab):
                if vocab[word] != 2:
                    ood.write(word + '\n')


if __name__ == '__main__':
    from sys import argv, exit

    if len(argv != 4):
        print "Usage: align.py audio_file transcript_file [manual_end]"
        exit()

    audio_fn = argv[1]
    trans_fn = argv[2]

    # Below here is mostly pseudo-code based on align.pl

    write_to_file(clean_transcript())

    wavlen = get_wave_length(audio_fn)

    ap, af = os.path.split(audio_fn)

    # get name of subjid
    # create the directory for subjid/audio_fn
    # chdir to the subjid/audio_fn directory

    downsample_wav(audio_fn, 'prefix/audio.wav')

    get_transcript_vocab()

    subdic('var', 1,
           'ood', 'ood-vocab.txt',
           'vocab', 'vocab.txt',
           'dictionary', os.environ['ALIGNER_DATA_HOME'] + '/cmudict_0.6-lg_20060811.dic',
           'subdic', 'vocab.dic')

    process_audio;

    resegment_transcript;

    os.mkdir('phseg')
    os.mkdir('wdseg')

    subprocess.call(['sphinx3_align',
                      '-agc', 'none',
                      '-ctl', 'ctl',
                      '-cepext', 'mfc',
                      '-dict', 'vocab.dic',
                      #FIXME: get these variables from from cfg file, not env
                      '-fdict', os.environ['ALIGNER_DATA_HOME'] + '/filler.dic',
                      '-mdef', os.environ['S3_MODELS'] + '/hub4opensrc.6000.mdef',
                      '-mean', os.environ['S3_MODELS'] + '/means',
                      '-mixw', os.environ['S3_MODELS'] + '/mixture_weights',
                      '-tmat', os.environ['S3_MODELS'] + '/transition_matrices',
                      '-var', os.environ['S3_MODELS'] + '/variances',
                      '-insent', insent,
                      '-logfn', s3alignlog,
                      '-outsent', outsent,
                      '-phsegdir', phseg,
                      '-wdsegdir', wdseg,
                      '-beam', '1e-80'])
