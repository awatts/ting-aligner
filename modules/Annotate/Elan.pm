package Annotate::Elan;
use base "Annotate";

use strict;
use warnings;
use Carp;

use XML::Writer;
use IO::File;
use File::Basename;
use DateTime;

use lib dirname($0);
use Ctl;

our $VERSION = 0.001;

sub writeAlignment {
    # output Elan annotation xml format
    my ($self, $filename, $participant) = @_;

    my $ctl = Ctl->new;
    my ($uttsref, $wdsref, $phsref)= $ctl->read_control_file;
    my @utts = @$uttsref;
    my @wds = @$wdsref;
    my @phs = @$phsref;

    my $eaf_name = $filename;
    $eaf_name =~ s/\.wav//x;

    my $eaf = IO::File->new($eaf_name . '.eaf', 'w') or croak "Can't open " . $eaf_name .".eaf: $!\n";
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
            if ($t->{'time'} == $start) {
                $ts1 = $t->{'slot'};
                #delete $tsids[$j];
                # until i figure out how to delete the item from the array
                # so the array shrinks w/o screwing up the loop, just set
                # the values to undef to prevent reuse
                $t->{'time'} = 0;
                $t->{'slot'} = undef;
                last;
            }
            $j++;
        }
        my $k = 0;
        foreach my $t (@tsids) {
            if ($t->{'time'} == $end) {
                $ts2 = $t->{'slot'};
                #delete $tsids[$k];
                # until i figure out how to delete the item from the array
                # so the array shrinks w/o screwing up the loop, just set
                # the values to undef to prevent reuse
                $t->{'time'} = 0;
                $t->{'slot'} = undef;
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
                      'LINGUISTIC_TYPE_REF' => 'Phoneme',
                      'PARTICIPANT' => $participant,
                      'TIER_ID'=> 'Phoneme',
                      );
        for my $i (0..$#phones) {
            my $phone = shift @elems;
            my $start = $phone->{xmin} * 1000;
            my $end = $phone->{xmax} * 1000;
            my ($ts1,$ts2) = ('','');
            foreach my $t (@tsids) {
                if ($t->{'time'} == $start) {
                    $ts1 = $t->{'slot'};
                    #delete $tsids[$t];
                    # until i figure out how to delete the item from the array
                    # so the array shrinks w/o screwing up the loop, just set
                    # the values to undef to prevent reuse
                    $t->{'time'} = 0;
                    $t->{'slot'} = undef;
                    last;
                }
            }
            foreach my $t (@tsids) {
                if ($t->{'time'} == $end) {
                    $ts2 = $t->{'slot'};
                    #delete $tsids[$t];
                    # until i figure out how to delete the item from the array
                    # so the array shrinks w/o screwing up the loop, just set
                    # the values to undef to prevent reuse
                    $t->{'time'} = 0;
                    $t->{'slot'} = undef;
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

1;
