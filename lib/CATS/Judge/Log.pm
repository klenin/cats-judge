package CATS::Judge::Log;

use strict;
use warnings;

use Carp;
use Encode;
use POSIX qw(strftime);
use File::Spec;

use CATS::ConsoleColor qw();

sub new {
    my ($class) = shift;
    my $self = { last_line => '', dump => '', dump_size => 0, color => undef };
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
    my ($self, $path, %opts) = @_;
    $self->{path} = $path;
    $self->{max_dump_size} = $opts{max_dump_size} || 200000;
    $self->set_name(make_name());
}

sub rollover {
    my ($self) = @_;
    my $new_name = make_name();
    $new_name ne $self->{name} or return;
    close $self->{file};
    $self->set_name($new_name);
}

sub add_dump {
    my ($self, $s) = @_;
    $self->{dump_size} += length $s;
    my $capacity = $self->{max_dump_size} - length($self->{dump});
    return if $capacity <= 0;
    $self->{dump} .= substr($s, 0, $capacity);
}

sub colored {
    my ($self, $color) = @_;
    $self->{color} = $color;
    $self;
}

sub msg {
    my ($self, $fmt, @rest) = @_;
    # In case of message with interpolated string containing %.
    my $s = @rest ? sprintf $fmt, @rest : $fmt;
    my $encoded = Encode::encode_utf8($s);
    if ($self->{color}) {
        # Aviod spilling color across new line.
        my ($line, $eol) = $encoded =~ /^(.*)(\r?\n)?\z/;
        defined $line or confess 'Empty log message';
        syswrite STDOUT, CATS::ConsoleColor::colored($line, $self->{color});
        syswrite STDOUT, $eol if defined $eol;
        $self->{color} = undef;
    }
    else {
        syswrite STDOUT, $encoded;
    }
    if ($self->{last_line} ne $s) {
        syswrite $self->{file}, Encode::encode_utf8(strftime('%d.%m %H:%M:%S', localtime) . " $s");
        $self->{last_line} = $s;
    }
    $self->add_dump($s);
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
    $self->add_dump($data);
}

sub get_dump {
    my ($self) = @_;
    $self->{dump} . ($self->{dump_size} > length $self->{dump} ? " ... $self->{dump_size} bytes" : '');
}

sub clear_dump { $_[0]->{dump} = ''; $_[0]->{dump_size} = 0; }

1;
