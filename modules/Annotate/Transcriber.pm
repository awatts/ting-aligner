package Annotate::Transcriber;
use base "Annotate";

use strict;
use warnings;
use Carp;

use XML::Writer;
use IO::File;
use Date::Simple qw/date today/;

use Ctl;

our $VERSION = 0.001;

sub writeAlignment {
    # output Transcriber annotation xml format

    my %params = @_;

    my $ctl = Ctl->new;
    my ($uttsref, $wdsref, $phsref)= $ctl->read_control_file;
    my @utts = @$uttsref;
    my @wds = @$wdsref;
    my @phs = @$phsref;


    my $trs = IO::File->new('annotation.trs', 'w') or croak "Can't open annotation.trs: $!\n";
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


1;
