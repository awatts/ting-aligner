#!/usr/bin/perl -w
use strict;
use warnings;

# batch-align.pl
# author: Ting Qian <tqian@bcs.rochester.edu>
# date: 9/29/2009

# usage: batch-align INDEX_TABLE_FILE

my $idx_fn = shift @ARGV;

# check for index file and any remaining arguments
unless (defined $idx_fn && @ARGV == 0) {
    die "Usage: batch-align INDEX_TABLE_FILE\n";
}
unless (-e $idx_fn) {
    die "Cannot open index table. Check file name?"
}


# create a directory for storing results
# unless (-e "batch_results") {
#     system("mkdir batch_results");
# }

# iterate over entries in the index table
# index table file should have the following structure
# subjectID.wav[TAB]TRANSCRIPT TEXT
# NOTE: THRER MUST BE NO TAB DELIMITERS INSIDE TRANSCRIPT TEXT
open IDX_FP, $idx_fn;
while (<IDX_FP>) {
    chomp;
    my @data = split(/\t/, $_);
    my $audio_fn = $data[0];
    my $text_transcript = $data[1];
    
    open TEMP_TRS, ">_temp_transcript.txt";
    print TEMP_TRS $text_transcript;
    close TEMP_TRS;

    system("align.pl $audio_fn _temp_transcript.txt");
}
close IDX_FP;

system("rm _temp_transcript.txt");
system("rm _temp*.cleaned");
