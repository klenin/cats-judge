package CATS::Judge::Log;

use strict;
use warnings;

use Carp;
use Encode;
use POSIX qw(strftime);
use File::Spec;

sub new {
    my ($class) = shift;
    my $self = { last_line => '', dump => '' };
    bless $self, $class;
    $self;
}

sub make_name {
    my (undef, undef, undef, undef, $month, $year) = localtime;
    sprintf 'judge-%04d-%02d.log', $year + 1900, $month + 1;
}

sub set_name {
    my ($self, $name) = @_;
    $self->{name} = $name;
    my $fn = File::Spec->catfile($self->{path}, $self->{name});
    open $self->{file}, '>>', $fn or die "Unable to open log file '$fn': $!";
}

sub init {
    my ($self, $path) = @_;
    $self->{path} = $path;
    $self->set_name(make_name());
}

sub rollover {
    my ($self) = @_;
    my $new_name = make_name();
    $new_name ne $self->{name} or return;
    close $self->{file};
    $self->set_name($new_name);
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
    my ($self, $fmt, @rest) = @_;
    $self->msg("Error: $fmt\n", @rest);
    croak 'Unrecoverable error';
}

sub note {
    my ($self, $fmt, @rest) = @_;
    $self->msg("$fmt\n", @rest);
}

sub warning {
    my ($self, $fmt, @rest) = @_;
    $self->msg("Warning: $fmt\n", @rest);
}

sub dump_write {
    my ($self, $data) = @_;
    syswrite $self->{file}, Encode::encode_utf8($data);
    $self->{dump} .= $data if length $self->{dump} < 50000;
}

sub clear_dump { $_[0]->{dump} = ''; }

1;
