#!/usr/bin/env perl
use strict;
use warnings;
use Carp;

# align.pl
# author: Ting Qian <ting.qian@rochester.edu>
# date: 08/20/2009
# last update: 09/27/2009
# modified by: Andrew Watts <awatts@bcs.rochester.edu>
# modifed date: 2010-09-10

# usage: align.pl AUDIO_FILE TEXT_TRANSCRIPT [MANUAL_END]

use Audio::Wav;
use File::Copy;
use File::Spec::Functions qw(:ALL);
use File::Util;
use File::Temp;
use File::Basename;
use IO::File;
use Array::Unique;
use Time::HiRes qw(time);

# we have a few modules that aren't necessarily ready to be installed in
# the normal directories, so for now we'll keep them locally
#use lib '/p/hlp/tools/aligner/modules';
use lib catdir(dirname($0), updir(), 'modules');
use Annotate::Elan;
use Ctl;

# aligner
my $tools_home = "/p/hlp/tools";
my $aligner_bin_home ="${tools_home}/aligner/bin";
my $aligner_data_home = "${tools_home}/aligner/data";

# sphinx 3 and SphinxTrain
my $S3_bin = "/usr/local/bin";
my $S3_models ="${aligner_data_home}/hub4_cd_continuous_8gau_1s_c_d_dd";
my $S3EP_models = "/usr/local/share/sphinx3/model/ep";

local $ENV{PATH} = "/bin:/usr/bin:${S3_bin}:${aligner_bin_home}:${aligner_data_home}";

my ($audio_fn, $text_fn, $manual_end) = @ARGV;
my $participant = 'XXX'; #FIXME: pass the correct participant, not just 'XXX'

# find utterance boundaries manually
# based on make-ctl.pl
# Press enter when the audio reaches the end of the currently displayed utterance.
# Press Ctrl-D when done.
sub find_manual_boundaries {
    my $transcript = IO::File->new;
    $transcript->open("transcript", "r") or croak "Can't open transcript: $!\n";
    my $boundaries = IO::File->new;
    $boundaries->open("boundaries", "r") or croak "Can't open boundaries: $!\n";

    # we need a program that plays wav files with little to no screen output
    # Linux using ALSA has aplay.
    # MacOS X >= 10.5 comes with afplay
    my $aplay;
    if ( $^O eq "linux" ) {
        $aplay = "aplay";
    } elsif ($^O eq "darwin") {
        $aplay = "afplay";
    }

    system("clear");

    print "====================================\n";
    print "Press ENTER when you hear a boundary\n";
    print "Then press CTRL + D to finish\n";
    print "====================================\n";

    unless (fork) {
        `$aplay audio.wav 2>&1 >/dev/null`;
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
    my $WAVE2FEAT = "${S3_bin}/wave2feat";
    my $S3EP = "${S3_bin}/sphinx3_ep";

    system("$WAVE2FEAT -i audio.wav -o mfc -mswav yes -seed 2");
    system("$S3EP -input mfc -mean ${S3EP_models}/means -mixw ${S3EP_models}/mixture_weights -var ${S3EP_models}/variances >ep");
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
        # eliminate whitespace
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
    die "Cannot open audio file:" . $audio_fn . ". Check file name?\n";
}
unless(-e $text_fn) {
    die "Cannot open transcript: " . $text_fn . ". Check file name?\n";
}

# set whether we want messages for when we enter each stage
my $debug = 1;

# pre-process transcript text
print "DEBUG: cleaning transcript\n" if $debug;
my $cleaned_fp = File::Temp->new(SUFFIX => '.cleaned') or croak "Couldn't make temp file: $!";
write_to_file(clean_transcript($text_fn), $cleaned_fp->filename);

# get the length of the audio file
# this must be done at the beginning to
# avoid conflict with SPHINX
my $length = get_wave_length($audio_fn);

# get the final part of the path component in order to name the results dir
my ($volume,$directories,$file) = splitpath( $audio_fn );
my $cdirs = canonpath($directories);
my @dirs = splitdir($cdirs);

my $experiment;
if ($#dirs >= 0) {
    $experiment = "$dirs[-1]/$file/";
} else {
    $experiment = $file . "_aligned";
}

# make a folder to store the files
File::Util->make_dir($experiment, '--if-not-exists') or croak "Could not make directory: $!";

# copy audio file and transcript to that folder
print "DEBUG: Copying cleaned transcript to experiment folder\n" if $debug;
system("resample -to 16000 $audio_fn $experiment/audio.wav");
copy($cleaned_fp->filename, "${experiment}/transcript") or croak "Copy of cleaned transcript failed: $!";

chdir($experiment) ||
    croak 'If you see this error message, please contact Ting Qian at ting.qian@rochester.edu\n';

print "DEBUG: Getting transcript vocab.\n" if $debug;
get_transcript_vocab;

print "DEBUG: Creating subdic.\n" if $debug;
subdic('var' => 1,
       'ood' => 'ood-vocab.txt',
       'vocab' =>'vocab.txt',
       #'dictionary' => "${aligner_data_home}/cmudict_0.6-lg_20060811.dic",
       'dictionary' => "${aligner_data_home}/cmudict.0.7a_SPHINX_40.dic",
       'subdic' => 'vocab.dic',
       'verbose' => 1
);
print "DEBUG: Processing audio\n" if $debug;
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
    print "DEBUG: Writing Ctl file\n" if $debug;
    my $ctl = IO::File->new;
    $ctl->open('ctl', 'w') or croak;
    print $ctl "./\t0\t$length\tutt1\n";
    $ctl->close;
}

# align sound and transcript
print "DEBUG: Resegmenting transcript\n" if $debug;
resegment_transcript;
mkdir 'phseg';
mkdir 'wdseg';
system("${S3_bin}/sphinx3_align \\
       -agc none \\
       -ctl ctl \\
       -cepext mfc \\
       -dict vocab.dic \\
       -fdict ${aligner_data_home}/filler.dic \\
       -mdef ${S3_models}/hub4opensrc.6000.mdef \\
       -mean ${S3_models}/means \\
       -mixw ${S3_models}/mixture_weights \\
       -tmat ${S3_models}/transition_matrices \\
       -var ${S3_models}/variances \\
       -insent insent \\
       -logfn s3alignlog \\
       -outsent outsent \\
       -phsegdir phseg \\
       -wdsegdir wdseg \\
       -beam 1e-80"
);

if ($? == -1) {
    print "Failed to align: $!\n";
} else {
    # generate XML output
    my $annotation = Annotate::Elan->new();
    print "DEBUG: writing final aligned file" if $debug;
    $annotation->writeAlignment($audio_fn, $participant);
}
