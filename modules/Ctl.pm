package Ctl;
require Exporter;

use strict;
use warnings;
use Carp;

use base qw(Exporter);
our @EXPORT_OK = qw(make_ctl);
our %EXPORT_TAGS = ( all => [ qw(make_ctl) ] );
our $VERSION = 0.001;

#
# Based almost entirely on the make-ctl.pl script written by
# various people in the CS department at the University of Rochester
#
# Rewritten into module form and cleaned up to not make Perl::Critic sob
# too much by Andrew Watts
#

# this is how much later ep can be than boundaries
my $epsilon = 75;

# load manual boundaries
sub load_manual_boundaries {
	my @boundaries;
	open (my $boundfile, "<", "boundaries") or croak "Can't open boundaries file $!\n";
	while(<$boundfile>) {
		chomp;
		push @boundaries, $_;
	}
	close $boundfile;

	return @boundaries;
}

# load automatic endpoints
sub load_automatic_endpoints {
	my @intervals = ();
	open (my $ep, "<", "ep") or croak "Can't open ep: $!\n";
	while (<$ep>) {
		my ($start, $end);
	    if (/^Utt_Start#\d+, Leader: ([\d\.]+),/x) {
			$start = int($1 * 100);
	    } elsif (/^Utt_Cancel/x) {
			undef $start;
	    } elsif (/^Utt_End#(\d+), End: [\d\.]+,  Trailer: ([\d\.]+)/x) {
			$end = int($2 * 100);
			push @intervals, {start=>$start, end=>$end};
	    }
	}
	close $ep;
	return @intervals;
}

# find control intervals
sub find_control_intervals {
	my (@boundaries, @intervals) = @_;
	my $nextInterval = 1;
	my @control = ();
	for my $uttid (1..@boundaries) {
		while ($nextInterval < @intervals and $intervals[$nextInterval]->{end} < $boundaries[$uttid-1] + $epsilon) {
			$nextInterval++;
		}
		my $newControl = {
			start => (@control > 0)? $control[-1]->{end} + 1 : 0,
			end => $nextInterval-1,
			uttid => "utt$uttid"
		};
		if ($intervals[$newControl->{end}]->{end} < $boundaries[$uttid-1] - $epsilon) {
			# too much of a difference, snap to the manual boundary
			$intervals[$newControl->{end}]->{end} = $boundaries[$uttid-1];
		}
		if ($newControl->{start} <= $newControl->{end}) {
			push @control, $newControl;
		} else {
			$control[-1]->{uttid} =~ s/^utt(\d+)(?:\-\d+)?$/utt$1-$uttid/x;
		}
	}

	# snap interval pointers
	for my $c (@control) {
		$c->{start} = $intervals[$c->{start}]->{start};
		$c->{end} = $intervals[$c->{end}]->{end};
	}

	# fix overlapping intervals by setting both to their average
	for my $i (1..$#control) {
		if ($control[$i-1]->{end} > $control[$i]->{start}) {
			$control[$i-1]->{end} = $control[$i]->{start} = int(($control[$i-1]->{end} + $control[$i]->{start}) / 2);
		}
	}

	return @control;
}

# write control file
sub write_control_file {
	my @boundaries = load_manual_boundaries;
	my @intervals = load_automatic_endpoints;
	my @control = find_control_intervals(@boundaries, @intervals);

	open (my $ctl, ">", "ctl") or croak "Can't open ctl: $!\n";
	for my $line (@control) {
		if ($line->{start} == undef) {
			$line->{start} = 0;
		}
		print $ctl './ ' .
		$line->{start} . ' ' .
		$line->{end} . ' ' .
		$line->{uttid} . "\n";
	}
	close $ctl;
	return;
}

1;
