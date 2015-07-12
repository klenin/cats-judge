package CATS::Judge::Log;

use strict;
use warnings;

use Encode;
use POSIX qw(strftime);
use File::Spec;

sub new {
    my ($class) = shift;
    my $self = { last_line => '', dump => '' };
    bless $self, $class;
    $self;
}

sub init {
    my ($self, $path) = @_;
    my (undef, undef, undef, undef, $month, $year) = localtime;
    $self->{path} = $path;
    $self->{name} = sprintf 'judge-%04d-%02d.log', $year + 1900, $month + 1;
    open $self->{file}, '>>', File::Spec->catfile($self->{path}, $self->{name});
}

sub msg {
    my $self = shift;
    my $fmt = shift;
    my $s = sprintf $fmt, @_;
    syswrite STDOUT, Encode::encode_utf8($s);
    if ($self->{last_line} ne $s) {
        syswrite $self->{file}, Encode::encode_utf8(strftime('%d.%m %H:%M:%S', localtime) . " $s");
        $self->{last_line} = $s;
    }
    $self->{dump} .= $s;
    undef;
}

sub error {
    my $self = shift;
    $self->msg("Error: $_[0]\n");
    die "Unrecoverable error";
}

sub note {
    my $self = shift;
    $self->msg("$_[0]\n");
}

sub warning {
    my $self = shift;
    $self->msg("Warning: $_[0]\n");
}

sub dump_write {
    my ($self, $data) = @_;
    syswrite $self->{file}, Encode::encode_utf8($data);
    $self->{dump} .= $data if length $self->{dump} < 50000;
}

sub clear_dump { $_[0]->{dump} = ''; }

1;
