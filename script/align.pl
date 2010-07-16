#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;

# align.pl
# author: Ting Qian <ting.qian@rochester.edu>
# date: 08/20/2009
# last update: 09/27/2009
# modified by: Andrew Watts <awatts@bcs.rochester.edu>
# modifed date: 2010-02-03

# usage: align.pl AUDIO_FILE TEXT_TRANSCRIPT [MANUAL_END]

use Audio::Wav;
use File::Copy;
use File::Spec;
use File::Util;
use File::Temp;
use IO::File;
use Array::Unique;

# we have a few modules that aren't necessarily ready to be installed in
# the normal directories, so for now we'll keep them locally
#use lib '/p/hlp/tools/aligner/modules';
use lib '/Users/awatts/ting-aligner/modules/';
use Annotate::Elan;
use Ctl;

# TODO: make these ENV declarations less HLP Lab centric
local $ENV{MPLAYER} = "mplayer";
local $ENV{APLAY} = "afplay";

# set this to "-x" if you're on a PPC Mac or other big-endian machine
#local $ENV{SWAP_WORD_ORDER} = "-x";

local $ENV{TOOLS_HOME} = "/p/hlp/tools";

# aligner
local $ENV{ALIGNER_BIN_HOME} ="$ENV{TOOLS_HOME}/aligner/bin";
#local $ENV{ALIGNER_SCRIPT_HOME} = "$ENV{TOOLS_HOME}/ting-aligner/script";
local $ENV{ALIGNER_SCRIPT_HOME} = "/Users/awatts/ting-aligner/script";
local $ENV{ALIGNER_DATA_HOME} = "$ENV{TOOLS_HOME}/aligner/data";

# sphinx 3 and SphinxTrain
local $ENV{S3_BIN} = "/usr/local/bin";
local $ENV{S3_MODELS} ="$ENV{ALIGNER_DATA_HOME}/hub4_cd_continuous_8gau_1s_c_d_dd";
local $ENV{S3EP_MODELS} = "/usr/local/share/sphinx3/model/ep";

local $ENV{PATH} = "/bin:/usr/bin:$ENV{S3_BIN}:$ENV{ALIGNER_SCRIPT_HOME}:$ENV{ALIGNER_BIN_HOME}:$ENV{ALIGNER_DATA_HOME}";

my ($audio_fn, $text_fn, $manual_end) = @ARGV;

# find utterance boundaries manually
# based on make-ctl.pl
# Press enter when the audio reaches the end of the currently displayed utterance.
# Press Ctrl-D when done.
sub find_manual_boundaries {
    my $transcript = IO::File->new;
    $transcript->open("transcript", "r") or croak "Can't open transcript: $!\n";
    my $boundaries = IO::File->new;
    $boundaries->open("boundaries", "r") or croak "Can't open boundaries: $!\n";

    system("clear");

    print "====================================\n";
    print "Press ENTER when you hear a boundary\n";
    print "Then press CTRL + D\n";
    print "====================================\n";

    unless (fork) {
        `$ENV{APLAY} audio.wav 2>&1 >/dev/null`;
    } else {
        my $start = time;

        my $line = <$transcript>;
        print $line;

        while (<>) {
            print $boundaries int((time - $start)*100) . "\n";
            $line = <$transcript>;
            print $line;
        }
    }
    $transcript->close;
    $boundaries->close;

    return;
}

# do initial per-segment processing of wav audio
# based on process-audio.pl
sub process_audio {
    my $WAVE2FEAT = "$ENV{S3_BIN}/wave2feat";
    my $S3EP = "$ENV{S3_BIN}/sphinx3_ep";
    my $S3EP_MODELS = $ENV{S3EP_MODELS};

    system("$WAVE2FEAT -i audio.wav -o mfc -mswav yes -seed 2");
    system("$S3EP -input mfc -mean $S3EP_MODELS/means -mixw $S3EP_MODELS/mixture_weights -var $S3EP_MODELS/variances >ep");
    return;
}

# subroutine to get the length of a wave file
# parameter: name of wave file
# return: length in seconds, to 1/100th
sub get_wave_length {
    my ($wave_file) = @_;
    my $wav = Audio::Wav->new;
    my $read = $wav -> read($wave_file);
    my $length = $read -> length_seconds();
    return int($length * 100);
}

# subroutine to pre-process transcript
# Parameter: name of transcript file
# Return: an array of strings, one per cell, of
#         the cleaned transcript
sub clean_transcript {
    my ($transcript_fn) = @_;
    my @new_transcript_text;
    my $transcript_fp = IO::File->new;
    $transcript_fp->open($transcript_fn, 'r') or croak "Cannot open $transcript_fn\n";
    while (<$transcript_fp>) {
        chomp;
        $_ =~ s/@\S+//igx;
        $_ =~ s/\///gx;
        push @new_transcript_text, $_;
    }
    $transcript_fp->close;
    return \@new_transcript_text;
}

# subroutine to write an array of strings
# to a text file
# Parameter: 1) scalar reference of an array
#            2) output file name
sub write_to_file {
    my ($arr_ref, $output_fn) = @_;
    print @$arr_ref;
    my $output_fp = IO::File->new;
    $output_fp->open($output_fn, 'w') or croak "Cannot open $output_fn\n";
    foreach my $line (@$arr_ref) {
        print $output_fp "$line\n";
    }
    $output_fp->close;
    return;
}

# makes .transcript suitable for sphinx3_align using a ctl file
# based on resegment-transcript.pl
sub resegment_transcript {

    my $ctl = IO::File->new;
    my $transcript = IO::File->new;
    my $insent = IO::File->new;

    $ctl->open('ctl', 'r') or croak "Can't open file ctl for reading: $!\n";
    $transcript->open('transcript', 'r') or croak "Can't open file transcript for reading: $!\n";
    $insent->open('insent', 'w') or croak "Can't open insent from writing: $!\n";

    my $uttNum = 0;
    while (my $ctlLine = <$ctl>) {
        chomp $ctlLine;
        if ($ctlLine =~ /utt(?:\d+-)?(\d+)$/ix) {
            my $segName = $&; # $& is the whole match
            my $endUttNum = $1;
            my @words = ();
            while ($uttNum < $endUttNum) {
                my $transcriptLine = <$transcript>;
                $uttNum++;
                chomp $transcriptLine;
                $transcriptLine =~ s/^.*?: //x;
                $transcriptLine =~ s/\[PARTIAL (\w+).*?\]/$1/gx;
                $transcriptLine =~ s/\<.*?\>//gx;
                $transcriptLine =~ s/\[.*?\]//gx;
                $transcriptLine = uc($transcriptLine);
                push @words, @{[ $transcriptLine =~ /[\w'-]+/gx ]};
            }
            print $insent join(' ', @words) . " ($segName)\n";
        }
    }

    $transcript->close;
    $ctl->close;
    return;
}

# based very loosly on get-transcript-vocab.sh, which has gone from a one-liner
# to a cleaner, safer, but much longer function
sub get_transcript_vocab {
    my $transcript = IO::File->new;
    my $vocab = IO::File->new;

    $transcript->open('transcript', 'r') or croak "Can't open file transcript for reading: $!\n";
    $vocab->open('vocab.txt', 'w') or croak "Can't open file vocab.txt for writing: $!\n";

    my @wordlist = ();
    tie @wordlist, 'Array::Unique';
    while (my $transline = <$transcript>) {
        while ($transline =~ /([\w'-]+)/gx) {
            push @wordlist, uc($1);
        }
    }
    @wordlist = sort(@wordlist);

    foreach my $word (@wordlist) {
        print $vocab "$word\n";
    }

    $vocab->close;
    $transcript->close;
    return;
}


# Description:
# - input: a vocabulary and a dictionary
# - output: the part of the dic including only words in the vocab
#           (optional) save OOD words to file
# Based on subdic by Lucian Galescu <galescu@cs.rochester.edu> <lgalescu@ihmc.us>
sub subdic {
    my %options = @_;

    my $verbose = 0;
    my $novar = 0;
    my $ood_file = undef;
    my $vocab_file = undef;
    my $dict_file = undef;
    my $subdic_file = undef;
    my %vocab;

    $novar = $options{'var'} if (defined $options{'var'});
    $verbose = $options{'verbose'} if (defined $options{'verbose'});

    $ood_file = $options{'ood'};
    $vocab_file = $options{'vocab'};
    $dict_file = $options{'dictionary'};
    $subdic_file = $options{'subdic'};

    my $voc = IO::File->new;
    $voc->open($vocab_file, 'r') or croak "Can't open vocab file: $!\n";
    while (my $word = <$voc>) {
        next if $word =~ /^\#\#/x; # skip header
        chomp $word;
        $word =~ s/^\s*(\S+)\s*$/$1/x;
        # eliminate tags
        next if $word =~ /^</x;
        $vocab{$word} = 1;
    }
    $voc->close;

    if ($verbose) {
        warn "Read ", scalar(keys %vocab), " words.\n";
    }

    my $dic = IO::File->new;
    my $subdic = IO::File->new;
    $dic->open($dict_file, 'r') or croak "Can't open dictionary: $dict_file $!\n";
    $subdic->open($subdic_file, 'w') or croak "Can't open subdic: $subdic_file $!\n";
    while (<$dic>) {

        #
        # This next statement was in the original, but made it skip every
        # line. I'm commenting it out but leaving it in just in case. --alw
        #
        #next if /^##/x;

        my $word;
        if ($novar) {
            if (m/^([^\s\(]+)/x) {
                $word = $1;
            }
        } else {
            if (m/^([^\s]+)\s/x) {
                $word = $1;
            }
        }

        if (defined $vocab{$word}) {
            print $subdic $_;
            $vocab{$word} = 2;
        }
    }
    $subdic->close;
    $dic->close;

    if (defined $ood_file) {
        my $ood = IO::File->new;
        $ood->open($ood_file, 'w') or croak "Can't open file $ood_file:  $!\n";
        foreach my $word (sort keys %vocab) {
            if ($vocab{$word} != 2) {
                print $ood $word, "\n";
            }
        }
        $ood->close;
    }
    return;
}

unless (defined $audio_fn && defined $text_fn) {
    die "Usage: align.pl AUDIO_FILE TEXT_TRANSCRIPT\n";
}
unless(-e $audio_fn) {
    die "Cannot open audio file. Check file name?\n";
}
unless(-e $text_fn) {
    die "Cannot open transcript. Check file name?\n";
}

# pre-process transcript text
my $cleaned_fp = File::Temp->new(SUFFIX => '.cleaned') or croak "Couldn't make temp file: $!";
write_to_file(clean_transcript($text_fn), $cleaned_fp->filename);

# get the length of the audio file
# this must be done at the beginning to
# avoid conflict with SPHINX
my $length = get_wave_length($audio_fn);

# get the final part of the path component in order to name the results dir
my ($volume,$directories,$file) = File::Spec->splitpath( $audio_fn );
my $cdirs = File::Spec->canonpath($directories);
my @dirs = File::Spec->splitdir($cdirs);

my $experiment;
if ($#dirs >= 0) {
    $experiment = "$dirs[-1]/$file/";
} else {
    $experiment = $file;
}

# make a folder to store the files
File::Util->make_dir($experiment, '--if-not-exists') or croak "Could not make directory: $!";

# copy audio file and transcript to that folder
system("resample -to 16000 $audio_fn $experiment/audio.wav");
copy($cleaned_fp->filename, "${experiment}/transcript") or croak "Copy failed: $!";

chdir($experiment) ||
    croak 'If you see this error message, please contact Ting Qian at ting.qian@rochester.edu\n';

get_transcript_vocab;

subdic('var' => 1,
       'ood' => 'ood-vocab.txt',
       'vocab' =>'vocab.txt',
       'dictionary' => "$ENV{ALIGNER_DATA_HOME}/cmudict_0.6-lg_20060811.dic",
       'subdic' => 'vocab.dic'
);
process_audio;

if (defined $manual_end) {
    # wait for user to define boundaries
    find_manual_boundaries;

    # generate control file
    my $ctl = Ctl->new;
    $ctl->write_control_file;
} else {
    # get the length of audio file
    # write control file
    my $ctl = IO::File->new;
    $ctl->open('ctl', 'w') or croak;
    print $ctl "./\t0\t$length\tutt1\n";
    $ctl->close;
}

# align sound and transcript
resegment_transcript;
mkdir 'phseg';
mkdir 'wdseg';
system("$ENV{S3_BIN}/sphinx3_align \\
       -agc none \\
       -ctl ctl \\
       -cepext mfc \\
       -dict vocab.dic \\
       -fdict $ENV{ALIGNER_DATA_HOME}/filler.dic \\
       -mdef $ENV{S3_MODELS}/hub4opensrc.6000.mdef \\
       -mean $ENV{S3_MODELS}/means \\
       -mixw $ENV{S3_MODELS}/mixture_weights \\
       -tmat $ENV{S3_MODELS}/transition_matrices \\
       -var $ENV{S3_MODELS}/variances \\
       -insent insent \\
       -logfn s3alignlog \\
       -outsent outsent \\
       -phsegdir phseg \\
       -wdsegdir wdseg \\
       -beam 1e-80"
);


# generate XML output
my $annotation = Annotate::Elan->new();
$annotation->writeAlignment($audio_fn, 'AK'); #FIXME: pass the correct participant, not just 'AK'
