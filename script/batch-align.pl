#!/usr/bin/perl -w
use strict;
use warnings;
use Carp;

use File::Temp;
use Text::CSV_XS;

# batch-align.pl
# author: Ting Qian <tqian@bcs.rochester.edu>
# date: 9/29/2009
# modified by: Andrew Watts <awatts@bcs.rochester.edu>
# modifed date: 2010-07-16

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
# index table file should be a tab delimited file with the following two columns:
# subjectID.wav and TRANSCRIPT TEXT
# NOTE: THERE MUST BE NO TAB DELIMITERS INSIDE TRANSCRIPT TEXT
my $csv = Text::CSV_XS->new({
                            binary => 1,
                            sep_char => "\t"
                        }) or croak "Cannot use CSV: ".Text::CSV->error_diag();
$csv->column_names(qw/audio transcript/);
open (my $idx_fp, '<', $idx_fn) or croak "Couldn't open file: $!";
while (my $row = $csv->getline_hr($idx_fp)) {
    my $audio_fn = $row->{audio};
    my $text_transcript = $row->{transcript};

    my $temp_trs = File::Temp->new(SUFFIX => '.txt');
    print $temp_trs $text_transcript;

    my $temp_fn = $temp_trs->filename;
    system("align.pl $audio_fn $temp_fn");
}
$csv->eof or $csv->error_diag();
close $idx_fp;
