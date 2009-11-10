package Annotate::Anvil;
require Exporter;

use strict;
use warnings;
use Carp;

use base qw(Exporter);
our @EXPORT_OK = qw(writeAlignment);
our %EXPORT_TAGS = ( all => [ qw(writeAlignment) ] );
our $VERSION = 0.001;

#
# Based almost entirely on the make-anvil-annotation.pl script written by
# various people in the CS department at the University of Rochester
#
# Rewritten into module form and cleaned up to not make Perl::Critic sob
# too much by Andrew Watts
#
#- makes an anvil annotation xml track from ctl, outsent, wdseg, and phseg
#

my $framesPerSecond = 100;
my $secondsPerFrame = 1 / $framesPerSecond;
my $epsilon = $secondsPerFrame / 100; #stupid floating point error

my @utts = ();
my @wds = ();
my @phs = ();
my $xmax = 0;

sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $self = {@_};
    bless ($self, $class);
    return $self;
}

sub addInterval {
    my ($array, $interval) = @_;
    #  print STDERR "adding interval " . $interval->{text} . " to $array\n";
    if (@$array > 0) {
        my $diff = $interval->{xmin} - $array->[-1]->{xmax};
        if ($diff > $secondsPerFrame + $epsilon) {
            push @$array, { xmin => $array->[-1]->{xmax}, xmax => $interval->{xmin}, text => ""};
        } elsif ($diff > 0) {
            $array->[-1]->{xmax} = $interval->{xmin};
        }
    } elsif ($interval->{xmin} > 0) {
        push @$array, { xmin => 0, xmax => $interval->{xmin}, text => ""};
    }
    push @$array, $interval;
    $xmax = $interval->{xmax} if ($interval->{xmax} > $xmax);

    return;
}

sub doSomethingWithCtl {
    open (my $ctl, "<", "ctl") or croak "Can't open ctl: $!\n";
    open (my $outsent, "<", "insent") or croak "Can't open ctl: $!\n";

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
        croak "invalid outsent line: $outsentLine\n"
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
        if (open (my $wdseg, "<", "wdseg/$ctlUttID.wdseg")) {
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
            close $wdseg;
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
        if (open (my $phseg, "<", "phseg/$ctlUttID.phseg") ) {
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
            close $phseg;
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

    close $ctl;
    close $outsent;
}


sub writeAnvilAnnotation {
    # output anvil annotation xml format

    open (my $anvil, ">", "annotation.anvil") or croak "Can't open annotation.anvil: $!\n";

    # header (I have no idea if the encoding is right)
    # TODO: get the video name from the parent script
    # TODO: get the specification file from the parent script
    print $anvil <<"EOH";
        <?xml version="1.0" encoding="ISO-8859-1"?>
        <annotation>
            <head>
                <specification src="../../specification19.xml" />
                <video src="video.avi" />
                <info key="coder" type="String">
                    Ting Qian's automatic speech aligner
                </info>
            </head>

            <body>
                <track name="Transcript.Word" type="primary">
EOH

    my $j = 0;
    for my $i (0..$#wds) {
        unless ($wds[$i]->{text} =~ /^(<sil>|SIL|<s>|<\/s>|)$/x) {
            print $anvil "      <el index=\"$j\" start=\"" . $wds[$i]->{xmin} . "\" end=\"" . $wds[$i]->{xmax} . "\">\n";
            $j++;
            print $anvil "        <attribute name=\"utterance\">" . $wds[$i]->{text} . "</attribute>\n";
            print $anvil "      </el>\n";
        }
    }

    # end of primary track and start of second track
    print $anvil "      </track>";
    print $anvil "  <track name=\"Transcript.Phoneme\", type=\"primary\">";

    $j = 0;

    for my $i (0..$#phs) {
        unless ($phs[$i]->{text} =~ /^(<sil>|SIL|<s>|<\/s>|)$/x) {
            print $anvil "      <el index=\"$j\" start=\"" . $phs[$i]->{xmin} . "\" end=\"" . $phs[$i]->{xmax} . "\">\n";
            $j++;
            print $anvil "        <attribute name=\"utterance\">" . $phs[$i]->{text} . "</attribute>\n";
            print $anvil "      </el>\n";
        }
    }

    # footer
    print $anvil "           </track>";
    print $anvil "      </body>";
    print $anvil "</annotation>";

    close $anvil;

    return;
}

sub writeAlignment {
    doSomethingWithCtl;
    writeAnvilAnnotation;
    return;
}

1;
