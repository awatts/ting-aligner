package Annotate::Anvil;

use strict;
use warnings;
use Carp;

use XML::Writer;
use IO::File;
use Date::Simple qw/date today/;
use DateTime;

use Ctl;

use vars qw/$VERSION @ISA @EXPORT_OK %EXPORT_TAGS/;

use base qw/Exporter/;
our @EXPORT_OK = qw/writeAlignment/;
our %EXPORT_TAGS = ( all => [ qw/writeAlignment/ ] );
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
    bless $self, $class;
    return $self;
}

sub writeAnvilAnnotation {
    # output anvil annotation xml format

    my ($uttsref, $wdsref, $phsref) = @_;
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

sub writeTranscriberAnnotation {
    # output Transcriber annotation xml format

    my ($uttsref, $wdsref, $phsref) = @_;
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


sub writeElanAnnotation {
    # output Elan annotation xml format
    my ($uttsref, $wdsref, $phsref, $filename, $participant) = @_;
    my @utts = @$uttsref;
    my @wds = @$wdsref;
    my @phs = @$phsref;

    my $eaf = IO::File->new('annotation.eaf', 'w') or croak "Can't open annotation.eaf: $!\n";
    my $writer = XML::Writer->new(OUTPUT => $eaf, DATA_MODE => 1, UNSAFE => 1, DATA_INDENT => 4);

    my $date = DateTime->now(time_zone => 'America/New_York');

    my $annotation_id = 1;
    my @time_slots = ();
    my @words = ();
    my @phones = ();
    my @tsids = ();
    my @elems = ();

    for my $i (0..$#wds) {
        unless ($wds[$i]->{text} =~ /^(<sil>|SIL|<s>|<\/s>|)$/x) {
            push @time_slots, $wds[$i]->{xmin} * 1000;
            push @time_slots, $wds[$i]->{xmax} * 1000;
            push @words, $wds[$i]->{text};
            push @elems, $wds[$i];
        }
    }

    for my $i (0..$#phs) {
        unless ($phs[$i]->{text} =~ /^(<sil>|SIL|<s>|<\/s>|)$/x) {
            push @time_slots, $phs[$i]->{xmin} * 1000;
            push @time_slots, $phs[$i]->{xmax} * 1000;
            push @phones, $phs[$i]->{text};
            push @elems, $phs[$i];
        }
    }

    @time_slots = sort {$a <=> $b} @time_slots;
    for my $t (0..$#time_slots) {
        my $ts = {'slot' => 'ts' . ($t+1),
                  'time' => $time_slots[$t]
                 };
        push @tsids, $ts;
    }

    $writer->xmlDecl('UTF-8');

    $writer->startTag('ANNOTATION_DOCUMENT',
                      'AUTHOR' => 'Ting Automatic Aligner',
                      'DATE' => $date->strftime('%FT%R%z'),
                      'FORMAT' => '2.6',
                      'VERSION' => '2.6',
                      'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                      'xsi:noNamespaceSchemaLocation' => 'http://www.mpi.nl/tools/elan/EAFv2.6.xsd'
                    );

    $writer->startTag('HEADER',
                      'MEDIA_FILE' => '',
                      'TIME_UNITS' => 'milliseconds'
                      );
    $writer->emptyTag('MEDIA_DESCRIPTOR',
                      'MEDIA_URL' => 'file://' . $filename,
                      'MIME_TYPE' => 'audio/x-wav',
                      'RELATIVE_MEDIA_URL' => 'file:' . $filename
                      );
    $writer->startTag('PROPERTY', 'NAME' => 'lastUsedAnnotationId');
    $writer->characters($#words + $#phones + 2);
    $writer->endTag('PROPERTY');
    $writer->endTag('HEADER');

    $writer->startTag('TIME_ORDER');
    for my $i (0..$#time_slots) {
        $writer->emptyTag('TIME_SLOT',
                          'TIME_SLOT_ID' => 'ts' . ($i +1),
                          'TIME_VALUE' => $time_slots[$i]
                          );
    }
    $writer->endTag('TIME_ORDER');

    $writer->startTag('TIER',
                      'ANNOTATOR' => 'Auto',
                      'DEFAULT_LOCALE' => 'en',
                      'LINGUISTIC_TYPE_REF' => 'Word',
                      'PARTICIPANT' => $participant,
                      'TIER_ID'=> 'Word'
                      );
    for my $i (0..$#words) {
        my $word = shift @elems;
        my $start = $word->{xmin} * 1000;
        my $end = $word->{xmax} * 1000;
        my ($ts1,$ts2) = ('','');
        my $j = 0;
        foreach my $t (@tsids) {
            print $tsids[$j] . "\n";
            if ($t->{'time'} == $start) {
                $ts1 = $t->{'slot'};
                #delete $tsids[$j];
                last;
            }
            $j++;
        }
        my $k = 0;
        foreach my $t (@tsids) {
            if ($t->{'time'} == $end) {
                $ts2 = $t->{'slot'};
                #delete $tsids[$k];
                last;
            }
            $k++;
        }
        $writer->startTag('ANNOTATION');
        $writer->startTag('ALIGNABLE_ANNOTATION',
                          'ANNOTATION_ID' => 'a' . ($annotation_id++),
                          'TIME_SLOT_REF1' =>  $ts1,
                          'TIME_SLOT_REF2' =>  $ts2
                          );
        $writer->dataElement('ANNOTATION_VALUE', $words[$i]);
        $writer->endTag('ALIGNABLE_ANNOTATION');
        $writer->endTag('ANNOTATION');
    }
    $writer->endTag('TIER');

    $writer->startTag('TIER',
                      'ANNOTATOR' => 'Auto',
                      'DEFAULT_LOCALE' => 'en',
                      'LINGUISTIC_TYPE_REF' => 'Word',
                      'PARTICIPANT' => 'AK',
                      'TIER_ID'=> 'Word',
                      );
        for my $i (0..$#phones) {
            my $phone = shift @elems;
            my $start = $phone->{xmin} * 1000;
            my $end = $phone->{xmax} * 1000;
            my ($ts1,$ts2) = ('','');
            foreach my $t (@tsids) {
                if ($t->{'time'} == $start) {
                    $ts1 = $t->{'slot'};
                    delete $tsids[$t];
                    last;
                }
            }
            foreach my $t (@tsids) {
                if ($t->{'time'} == $end) {
                    $ts2 = $t->{'slot'};
                    delete $tsids[$t];
                    last;
                }
            }
        $writer->startTag('ANNOTATION');
        $writer->startTag('ALIGNABLE_ANNOTATION',
                          'ANNOTATION_ID' => 'a' . ($annotation_id++),
                          'TIME_SLOT_REF1' => $ts1,
                          'TIME_SLOT_REF2' => $ts2
                          );
        $writer->dataElement('ANNOTATION_VALUE', $phones[$i]);
        $writer->endTag('ALIGNABLE_ANNOTATION');
        $writer->endTag('ANNOTATION');
    }
    $writer->endTag('TIER');

    $writer->emptyTag('LINGUISTIC_TYPE',
                      'GRAPHIC_REFERENCES'=> 'false',
                      'LINGUISTIC_TYPE_ID' => 'default-lt',
                      'TIME_ALIGNABLE' => 'true'
                      );
    $writer->emptyTag('LINGUISTIC_TYPE',
                      'GRAPHIC_REFERENCES' => 'false',
                      'LINGUISTIC_TYPE_ID' => 'Word',
                      'TIME_ALIGNABLE' => 'true'
                      );
    $writer->emptyTag('LINGUISTIC_TYPE',
                      'GRAPHIC_REFERENCES' => 'false',
                      'LINGUISTIC_TYPE_ID' => 'Phoneme',
                      'TIME_ALIGNABLE' => 'true'
                      );
    $writer->emptyTag('LOCALE',
                      'COUNTRY_CODE' => 'US',
                      'LANGUAGE_CODE' => 'en'
                     );
    $writer->emptyTag('CONSTRAINT',
                      'DESCRIPTION' => "Time subdivision of parent annotation's time interval, no time gaps allowed within this interval",
                      'STEREOTYPE' => 'Time_Subdivision'
                      );
    $writer->emptyTag('CONSTRAINT',
                      'DESCRIPTION' => "Symbolic subdivision of a parent annotation. Annotations refering to the same parent are ordered",
                      'STEREOTYPE' => 'Symbolic_Subdivision'
                      );
    $writer->emptyTag('CONSTRAINT',
                      'DESCRIPTION' => "1-1 association with a parent annotation",
                      'STEREOTYPE' => 'Symbolic_Association'
                      );
    $writer->emptyTag('CONSTRAINT',
                      'DESCRIPTION' => "Time alignable annotations within the parent annotation's time interval, gaps are allowed",
                      'STEREOTYPE' => 'Included_In'
                      );

    $writer->endTag('ANNOTATION_DOCUMENT');

    $writer->end;
    $eaf->close;

    return;

}

sub writeAlignment {
    my ($self, $filename, $participant) = @_;
    my $ctl = Ctl->new;
    my ($uttsref, $wdsref, $phsref)= $ctl->read_control_file;
    my @utts = @$uttsref;
    my @wds = @$wdsref;
    my @phs = @$phsref;

    #writeAnvilAnnotation(\@utts, \@wds, \@phs);
    #writeTranscriberAnnotation(\@utts, \@wds, \@phs);
    writeElanAnnotation(\@utts, \@wds, \@phs, $filename, $participant);
    return;
}

1;
