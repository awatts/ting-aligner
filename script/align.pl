#!/usr/bin/perl -w
use strict;
use warnings;

# align.pl
# author: Ting Qian <ting.qian@rochester.edu>
# date: 08/20/2009
# last update: 09/27/2009

# usage: align.pl AUDIO_FILE TEXT_TRANSCRIPT [MANUAL_END]

use Audio::Wav;

my $audio_fn = shift @ARGV;
my $text_fn = shift @ARGV;
my $manual_end = shift @ARGV;

# subroutine to get the length of a wave file
# parameter: name of wave file
# return: length in seconds, to 1/100th
sub get_wave_length {
    my $wave_file = "";
    ($wave_file) = @_;
    my $wav = new Audio::Wav;
    my $read = $wav -> read($wave_file);
    my $length = $read -> length_seconds();
    return int($length * 100);
}

# subroutine to pre-process transcript
# Parameter: name of transcript file
# Return: an array of strings, one per cell, of
#         the cleaned transcript
sub clean_transcript {
    my $transcript_fn;
    my @new_transcript_text;
    ($transcript_fn) = @_;
    open TRANSCRIPT_FP, $transcript_fn;
    while (<TRANSCRIPT_FP>) {
	chomp;
	$_ =~ s/@\S+//ig;
	$_ =~ s/\///g;
	push @new_transcript_text, $_;
    }
    return \@new_transcript_text;
}

# subroutine to write an array of strings
# to a text file
# Parameter: 1) scalar reference of an array
#            2) output file name
sub write_to_file {
    my ($arr_ref, $output_fn) = @_;
    print @$arr_ref;
    open OUTPUT_FP, ">$output_fn";
    foreach my $line (@$arr_ref) {
	print OUTPUT_FP "$line\n";
    }
    close OUTPUT_FP;
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
&write_to_file(&clean_transcript($text_fn), "$text_fn.cleaned");

# get the length of the audio file
# this must be done at the beginning to 
# avoid conflict with SPHINX
my $length = &get_wave_length($audio_fn);

# get the name of the subject
# assuming the audio file is named as subject.wav
$audio_fn =~ /(\w*)[.]wav/;
my $experiment = $1;

# make a folder to store the files
unless (-e $experiment) {
    system("mkdir $experiment");
}

# copy audio file and transcript to that folder
system("resample -to 16000 $audio_fn $experiment/audio.wav");
system("cp $text_fn.cleaned $experiment/transcript");

chdir($experiment) || 
    die 'If you see this error message, please contact Ting Qian at ting.qian@rochester.edu\n';

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
	die;
    } elsif ($pid == 0) {
	exec 'find-manual-boundaries.pl';
    }
    while (wait() != -1) {}
    
# generate control file
    system("make-ctl.pl");
} else {
    # get the length of audio file    
    # write control file
    open CTL, ">ctl";
    print CTL "./\t0\t$length\tutt1\n";
    close CTL;
}

# align sound and transcript
system("align.sh");

# generate XML output
system("make-anvil-annotation.pl");
