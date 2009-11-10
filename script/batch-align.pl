#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;

use File::Temp;

# batch-align.pl
# author: Ting Qian <tqian@bcs.rochester.edu>
# date: 9/29/2009
# modified by: Andrew Watts <awatts@bcs.rochester.edu>
# modifed date: 2009-10-30

# usage: batch-align INDEX_TABLE_FILE

my $idx_fn = shift @ARGV;

# check for index file and any remaining arguments
unless (defined $idx_fn && @ARGV == 0) {
    die "Usage: batch-align INDEX_TABLE_FILE\n";
}
unless (-e $idx_fn) {
    croak "Cannot open index table. Check file name?"
}


# create a directory for storing results
# unless (-e "batch_results") {
#     system("mkdir batch_results");
# }

# iterate over entries in the index table
# index table file should have the following structure
# subjectID.wav[TAB]TRANSCRIPT TEXT
# NOTE: THRER MUST BE NO TAB DELIMITERS INSIDE TRANSCRIPT TEXT
open (my $idx_fp, '<', $idx_fn) or croak "Couldn't open file: $!";
while (<$idx_fp>) {
    chomp;
    my @data = split(/\t/x, $_);
    my $audio_fn = $data[0];
    my $text_transcript = $data[1];

    my $temp_trs = File::Temp->new(SUFFIX => '.txt');
    print $temp_trs $text_transcript;

    my $temp_fn = $temp_trs->filename;
    system("align.pl $audio_fn $temp_fn");
}
close $idx_fp;
