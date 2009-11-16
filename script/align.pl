#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;

# align.pl
# author: Ting Qian <ting.qian@rochester.edu>
# date: 08/20/2009
# last update: 09/27/2009
# modified by: Andrew Watts <awatts@bcs.rochester.edu>
# modifed date: 2009-11-11

# usage: align.pl AUDIO_FILE TEXT_TRANSCRIPT [MANUAL_END]

use Audio::Wav;
use File::Copy;
use File::Spec;
use File::Util;
use File::Temp;
use IO::File;

# we have a few modules that aren't necessarily ready to be installed in
# the normal directories, so for now we'll keep them locally
#use lib '/p/hlp/tools/aligner/modules';
use lib '/Users/awatts/ting-aligner/modules/';
use Annotate::Anvil;
use Ctl;

# TODO: make these ENV declarations less HLP Lab centric
local $ENV{MPLAYER} = "mplayer";
local $ENV{APLAY} = "afplay";

# set this to "-x" if you're on a PPC Mac or other big-endian machine
#local $ENV{SWAP_WORD_ORDER} = "-x";

local $ENV{TOOLS_HOME} = "/p/hlp/tools";

# aligner
local $ENV{ALIGNMENT_HOME} = "$ENV{TOOLS_HOME}/aligner/tools/";
local $ENV{ALIGNER_BIN_HOME} ="$ENV{TOOLS_HOME}/aligner/bin";
local $ENV{ALIGNER_SCRIPT_HOME} = "$ENV{TOOLS_HOME}/aligner/script";
local $ENV{ALIGNER_DATA_HOME} = "$ENV{TOOLS_HOME}/aligner/data";

# sphinx 3
local $ENV{S3_BIN} = "/usr/local/bin";
local $ENV{S3_MODELS} ="$ENV{ALIGNER_DATA_HOME}/hub4_cd_continuous_8gau_1s_c_d_dd";
local $ENV{S3EP_MODELS} = "/usr/local/share/sphinx3/model/ep";

# SphinxTrain
local $ENV{WAVE2FEAT} = "$ENV{TOOLS_HOME}/SphinxTrain-1.0/bin.i686-apple-darwin9.7.0/wave2feat";

local $ENV{PATH} = "/usr/bin:$ENV{S3_BIN}:$ENV{ALIGNMENT_HOME}:$ENV{ALIGNER_SCRIPT_HOME}:$ENV{ALIGNER_BIN_HOME}:$ENV{ALIGNER_DATA_HOME}";

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
	my $WAVE2FEAT = $ENV{WAVE2FEAT};
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
    open (my $transcript_fp, '<' ,$transcript_fn) or croak "Cannot open $transcript_fn\n";
    while (<$transcript_fp>) {
		chomp;
		$_ =~ s/@\S+//igx;
		$_ =~ s/\///gx;
		push @new_transcript_text, $_;
    }
	close $transcript_fp;
    return \@new_transcript_text;
}

# subroutine to write an array of strings
# to a text file
# Parameter: 1) scalar reference of an array
#            2) output file name
sub write_to_file {
    my ($arr_ref, $output_fn) = @_;
    print @$arr_ref;
    open (my $output_fp, '>', $output_fn) or croak "Cannot open $output_fn\n";
    foreach my $line (@$arr_ref) {
		print $output_fp "$line\n";
    }
    close $output_fp;
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
#unless (-e '${ALIGNMENT_HOME}/') { die "Cannot find aligning scripts.\n";}

# pre-process transcript text
my $cleaned_fp = File::Temp->new(SUFFIX => '.cleaned');
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
copy("${text_fn}.cleaned", "${experiment}/transcript") or croak "Copy failed: $!";

chdir($experiment) ||
    croak 'If you see this error message, please contact Ting Qian at ting.qian@rochester.edu\n';

system("get-transcript-vocab.sh");
system('subdic -var -ood ood-vocab.txt vocab.txt <${ALIGNER_DATA_HOME}/cmudict_0.6-lg_20060811.dic >vocab.dic');
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
    $ctl->open("ctl", "w") or croak;
    print $ctl "./\t0\t$length\tutt1\n";
    $ctl->close;
}

# align sound and transcript
system("align.sh");

# generate XML output
my $annotation = Annotate::Anvil->new;
$annotation->writeAlignment;
