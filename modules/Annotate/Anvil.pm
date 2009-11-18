package Annotate::Anvil;

use strict;
use warnings;
use Carp;

use XML::Writer;
use IO::File;
use Date::Simple qw(date today);

use Ctl;

use vars qw($VERSION @ISA @EXPORT_OK %EXPORT_TAGS);

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

sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $self = {@_};
    bless ($self, $class);
    return $self;
}

sub writeAnvilAnnotation {
    # output anvil annotation xml format

    my ($uttsref, $wdsref, $phsref) = @_;
    my @utts = @$uttsref;
    my @wds = @$wdsref;
    my @phs = @$phsref;

    my $specification = "../../specification19.xml";
    my $video = "video.avi";

    my $anvil = IO::File->new("annotation.anvil", ">") or croak "Can't open annotation.anvil: $!\n";
    my $writer = XML::Writer->new(OUTPUT => $anvil, DATA_MODE => 1, DATA_INDENT => 4);

    # header (I have no idea if the encoding is right)
    # TODO: get the video name from the parent script
    # TODO: get the specification file from the parent script
    $writer->xmlDecl("UTF-8");
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

sub writeTranscriberAnnotation {
    # output Transcriber annotation xml format

    my ($uttsref, $wdsref, $phsref) = @_;
    my @utts = @$uttsref;
    my @wds = @$wdsref;
    my @phs = @$phsref;

    my $trs = IO::File->new("annotation.trs", ">") or croak "Can't open annotation.trs: $!\n";
    my $writer = XML::Writer->new(OUTPUT => $trs, DATA_MODE => 1, UNSAFE => 1, DATA_INDENT => 4);

    my $date = today();

    $writer->xmlDecl('ISO-8859-1');
    $writer->doctype('Trans', '', 'trans-13.dtd');

    $writer->startTag('Trans',
                      'scribe' => 'Ting Qian\'s automatic speech aligner',
                      'audio_filename' => 'audio.wav',
                      'version_date' => $date->format("%y%m%d"));

    $writer->startTag('Topics');
    $writer->emptyTag('Topic', 'id' => 'to1', 'desc' => 'topic#1');
    $writer->endTag('Topics');

    $writer->startTag('Speakers');
    $writer->emptyTag('Speaker', 'id' => 'spk1', 'name' => 'speaker#1',
                      'check' => 'no', 'dialect' => 'native',
                      'accent' => '', 'scope' => 'local');
    $writer->endTag('Speakers');

    $writer->startTag('Episode');
    $writer->startTag('Section', 'type' => 'report',
                     'startTime' => , $wds[0]->{xmin}, 'endTime' => $wds[-1]->{xmax},
                     'topic' => 'to1');

    $writer->startTag('Turn', 'startTime' => , $wds[0]->{xmin},
                      'endTime' => $wds[-1]->{xmax},
                      'speaker' => 'spk1');

    for my $i (0..$#wds) {
        unless ($wds[$i]->{text} =~ /^(<sil>|SIL|<s>|<\/s>|)$/x) {
            $writer->emptyTag('Sync', 'time' => $wds[$i]->{xmin});
            $writer->characters($wds[$i]->{text});
        }
    }

    $writer->endTag('Turn');
    $writer->endTag('Section');
    $writer->endTag('Episode');
    $writer->endTag('Trans');

    $writer->end;
    $trs->close;

    return;
}

sub writeAlignment {
    my $ctl = Ctl->new;
    my ($uttsref, $wdsref, $phsref)= $ctl->read_control_file;
    my @utts = @$uttsref;
    my @wds = @$wdsref;
    my @phs = @$phsref;

    writeAnvilAnnotation(\@utts, \@wds, \@phs);
    #writeTranscriberAnnotation(\@utts, \@wds, \@phs);
    return;
}

1;
