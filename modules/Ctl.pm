package Ctl;

use strict;
use warnings;
use Carp;

use IO::File;

use base qw(Exporter);
our @EXPORT_OK = qw(write_control_file read_control_file);
our %EXPORT_TAGS = ( all => [ qw(write_control_file read_control_file) ] );
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

my $framesPerSecond = 100;

sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $self = {@_};
    bless $self, $class;
    return $self;
}

sub addInterval {
    my ($array, $interval) = @_;
    my $xmax = 0;
    my $secondsPerFrame = 1 / $framesPerSecond;
    my $eps = $secondsPerFrame / 100; #stupid floating point error

    if (@$array > 0) {
        my $diff = $interval->{xmin} - $array->[-1]->{xmax};
        if ($diff > $secondsPerFrame + $eps) {
            push @$array, { xmin => $array->[-1]->{xmax}, xmax => $interval->{xmin}, text => ''};
        } elsif ($diff > 0) {
            $array->[-1]->{xmax} = $interval->{xmin};
        }
    } elsif ($interval->{xmin} > 0) {
        push @$array, { xmin => 0, xmax => $interval->{xmin}, text => ''};
    }
    push @$array, $interval;
    $xmax = $interval->{xmax} if ($interval->{xmax} > $xmax);

    return;
}

sub read_control_file {
    my $ctl = IO::File->new;
    my $outsent = IO::File->new;
    $ctl->open('ctl', 'r') or croak "Can't open ctl: $!\n";
    $outsent->open('insent', 'r') or croak "Can't open ctl: $!\n";

    my (@utts, @wds, @phs);

    while (defined(my $ctlLine = <$ctl>) and defined(my $outsentLine = <$outsent>)) {
        chomp $ctlLine;
        chomp $outsentLine;

        my ($startFrame, $endFrame, $ctlUttID, $outsentUttID);

        if ($ctlLine =~ /^\s*\S+\s+(\d+)\s+(\d+)\s+(\S+)\s*$/x) {
            ($startFrame, $endFrame, $ctlUttID) = ($1,$2,$3);
        } else {
            croak "invalid ctl line: $ctlLine\n";
        }

        if ($outsentLine =~ /\(([^\)]+)\)$/x) {
            $outsentUttID = $1;
        } else {
           croak "invalid outsent line: $outsentLine\n";
        }

        croak "utt id mismatch between ctl ($ctlUttID) and outsent ($outsentUttID)\n" unless ($ctlUttID eq $outsentUttID);

        $outsentLine =~ s/\([^\)]+\)$//x;

        # create utterance interval
        addInterval(\@utts, {
                xmin => $startFrame / $framesPerSecond,
                xmax => $endFrame / $framesPerSecond,
                text => $outsentLine
            }
        );

        # get word intervals in utterance
        my $wdseg = IO::File->new;
        if ($wdseg->open("wdseg/$ctlUttID.wdseg", 'r')) {
            while (my $line = <$wdseg>) {
                chomp $line;
                my $word;
                if ($line =~ /^\s*(\d+)\s+(\d+)\s+(?:-)?\d+\s+(\S+)\s*$/x) {
                    ($startFrame, $endFrame, $word) = ($1,$2,$3);
                    $word =~ s/\([^\)]+\)$//x;
                    addInterval(\@wds, {
                        xmin => $startFrame / $framesPerSecond + $utts[-1]->{xmin},
                        xmax => $endFrame / $framesPerSecond + $utts[-1]->{xmin},
                        text => $word
                        }
                    );
                }
            }
            $wdseg->close;
        } else {
            print STDERR "warning: couldn't open wdseg/$ctlUttID.wdseg, using utt as word\n";
            addInterval(\@wds, {
                xmin => $startFrame / $framesPerSecond,
                xmax => $endFrame / $framesPerSecond,
                text => $outsentLine
                }
            );
        }

        # get phoneme intervals in utterance
        my $phseg = IO::File->new;
        if ($phseg->open("phseg/$ctlUttID.phseg", 'r')) {
            while (my $line = <$phseg>) {
                chomp $line;
                my $phone;
                if ($line =~ /^\s*(\d+)\s+(\d+)\s+(?:-)?\d+\s+(\S+).*$/x) {
                    ($startFrame, $endFrame, $phone) = ($1,$2,$3);
                    $phone =~ s/\([^\)]+\)$//x;
                    addInterval(\@phs, {
                        xmin => $startFrame / $framesPerSecond + $utts[-1]->{xmin},
                        xmax => $endFrame / $framesPerSecond + $utts[-1]->{xmin},
                        text => $phone
                        }
                    );
                }
            }
            $phseg->close;
        } else {
            carp "warning: couldn't open phseg/$ctlUttID.phseg, using utt as word\n";
            addInterval(\@phs, {
                xmin => $startFrame / $framesPerSecond,
                xmax => $endFrame / $framesPerSecond,
                text => $outsentLine
                }
            );
        }
    }

    $ctl->close;
    $outsent->close;

    return (\@utts, \@wds, \@phs);
}

# load manual boundaries
sub load_manual_boundaries {
	my @boundaries;
	my $boundfile = IO::File->new;
	$boundfile->open('boundaries', 'r') or croak "Can't open boundaries file $!\n";
	while(<$boundfile>) {
		chomp;
		push @boundaries, $_;
	}
	$boundfile->close;

	return @boundaries;
}

# load automatic endpoints
sub load_automatic_endpoints {
	my @intervals = ();
	my $ep = IO::File->new;
	$ep->open('ep', 'r') or croak "Can't open ep: $!\n";
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
	$ep->close;
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

	my $ctl = IO::File->new;
	$ctl->open('ctl', 'w') or croak "Can't open ctl: $!\n";
	for my $line (@control) {
		if ($line->{start} == undef) {
			$line->{start} = 0;
		}
		print $ctl './ ' .
		$line->{start} . ' ' .
		$line->{end} . ' ' .
		$line->{uttid} . "\n";
	}
	$ctl->close;
	return;
}

1;
