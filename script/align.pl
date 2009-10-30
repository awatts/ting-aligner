#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;

# align.pl
# author: Ting Qian <ting.qian@rochester.edu>
# date: 08/20/2009
# last update: 09/27/2009
# modified by: Andrew Watts <awatts@bcs.rochester.edu>
# modifed date: 2009-10-30

# usage: align.pl AUDIO_FILE TEXT_TRANSCRIPT [MANUAL_END]

use Audio::Wav;
use File::Copy;
use File::Spec;
use File::Util;

my $audio_fn = shift @ARGV;
my $text_fn = shift @ARGV;
my $manual_end = shift @ARGV;

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
write_to_file(clean_transcript($text_fn), "${text_fn}.cleaned");

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
system("process-audio.pl");

if (defined $manual_end) {

# wait for user to define boundaries
    system("clear");

    print "====================================\n";
    print "Press ENTER when you hear a boundary\n";
    print "Then press CTRL + D\n";
    print "====================================\n";

    my $pid = fork();
    if ($pid == -1) {
		croak;
    } elsif ($pid == 0) {
		exec 'find-manual-boundaries.pl';
    }
    while (wait() != -1) {}

# generate control file
    system("make-ctl.pl");
} else {
    # get the length of audio file
    # write control file
    open (my $ctl, ">", "ctl") or croak;
    print $ctl "./\t0\t$length\tutt1\n";
    close $ctl;
}

# align sound and transcript
system("align.sh");

# generate XML output
system("make-anvil-annotation.pl");
