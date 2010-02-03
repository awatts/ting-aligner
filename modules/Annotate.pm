package Annotate;

use strict;
use warnings;
use Carp;

use vars qw/$VERSION @ISA @EXPORT_OK %EXPORT_TAGS/;

use base qw/Exporter/;
our @EXPORT_OK = qw/writeAlignment/;
our %EXPORT_TAGS = ( all => [ qw/writeAlignment/ ] );
our $VERSION = 0.001;

sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
    my $self = {@_};
    bless $self, $class;
    return $self;
}

sub writeAlignment {
    my %params = @_;
    return;
}

1;
