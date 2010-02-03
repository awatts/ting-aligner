package Annotate::Anvil;
use base "Annotate";

use strict;
use warnings;
use Carp;

use XML::Writer;
use IO::File;
use Date::Simple qw/date today/;
use DateTime;

use Ctl;

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

sub writeAlignment {
    # output anvil annotation xml format
    my %params = @_;

    my $ctl = Ctl->new;
    my ($uttsref, $wdsref, $phsref)= $ctl->read_control_file;
    my @utts = @$uttsref;
    my @wds = @$wdsref;
    my @phs = @$phsref;

    # TODO: get the video name from the parent script
    # TODO: get the specification file from the parent script
    my $specification = '/p/hlp/tools/aligner/ting-alginer.xml';
    my $video = 'video.avi';

    my $anvil = IO::File->new("annotation.anvil", ">") or croak "Can't open annotation.anvil: $!\n";
    my $writer = XML::Writer->new(OUTPUT => $anvil, DATA_MODE => 1, DATA_INDENT => 4);

    $writer->xmlDecl('UTF-8');
    $writer->startTag('annotation');
    $writer->startTag('head');
    $writer->emptyTag('specification', 'src' => $specification);
    $writer->emptyTag('video', 'src' => $video);
    $writer->startTag('info', 'key' => 'coder', 'type' => 'String');
    $writer->characters('Ting Qian\'s automatic speech aligner');
    $writer->endTag('info');
    $writer->endTag('head');

    $writer->startTag('body');

    # start of primary track
    $writer->startTag('track', 'name' => 'Transcript.Word', 'type' => 'primary');
    my $j = 0;
    for my $i (0..$#wds) {
        unless ($wds[$i]->{text} =~ /^(<sil>|SIL|<s>|<\/s>|)$/x) {
            $writer->startTag('el', 'index' => $j, 'start' => $wds[$i]->{xmin}, 'end' => $wds[$i]->{xmax});
            $writer->startTag('attribute', 'name' => 'utterance');
            $writer->characters($wds[$i]->{text});
            $writer->endTag('attribute');
            $writer->endTag('el');
            $j++;
        }
    }
    # end of primary track
    $writer->endTag('track');

    # start of second track
    $writer->startTag('track', 'name' => 'Transcript.Phoneme', 'type' => 'primary');
    $j = 0;
    for my $i (0..$#phs) {
        unless ($phs[$i]->{text} =~ /^(<sil>|SIL|<s>|<\/s>|)$/x) {
            $writer->startTag('el', 'index' => $j, 'start' => $phs[$i]->{xmin}, 'end' => $phs[$i]->{xmax});
            $writer->startTag('attribute', name=> 'utterance');
            $writer->characters($phs[$i]->{text});
            $writer->endTag('attribute');
            $writer->endTag('el');
            $j++;
        }
    }
    # end of second track
    $writer->endTag('track');

    # footer
    $writer->endTag('body');
    $writer->endTag('annotation');

    $writer->end;
    $anvil->close;

    return;
}

1;
