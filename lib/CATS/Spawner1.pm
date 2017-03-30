use strict;
use warnings;

package CATS::Spawner1;

use Carp qw(croak);

use CATS::Spawner::Const ':all';

sub new {
    my ($class, $opts) = @_;
    my $self = bless { opts => $opts }, $class;
    $self->_init;
    $self;
}

sub _init {}
sub _run { croak 'Not implemented' }

sub run {
    my ($self, $globals, @programs) = @_;
    $self->_run($globals, @programs);
}

sub run_single {
    my ($self, $globals, @program_params) = @_;
    $self->_run($globals, CATS::Spawner::Program->new(@program_params))->items->[0];
}

sub log {
    my ($self, @rest) = @_;
    $self->{opts}->{logger} or croak 'logger required';
    $self->{logger}->msg(@rest);
}

sub stdout_lines { [] }
sub stderr_lines { [] }
sub stdout_lines_chomp { [] }
sub stderr_lines_chomp { [] }

package CATS::Spawner::Report;

use Carp qw(croak);

use constant { ANY => 1, INT => 2, STR => 3, FLOAT => 4, OPT => 128 };

my $item_schema = {
    params => ANY,
    application => STR,
    arguments => [ STR ],
    method => STR,
    security => {
        level => INT,
        user_name => STR,
    },
    errors => [ STR ],
    limits => {
        wall_clock_time => OPT | FLOAT,
        user_time => OPT | FLOAT,
        idle_time => OPT | FLOAT,
        memory => OPT | INT,
        write => OPT | INT,
        load_ratio => OPT | FLOAT,
    },
    terminate_reason => INT,
    exit_status => STR,
    exit_code => INT,
    consumed => {
        wall_clock_time => OPT | FLOAT,
        user_time => FLOAT,
        system_time => OPT | FLOAT,
        memory => INT,
        write => INT,
    },
};

sub new {
    my ($class, $opts) = @_;
    my $self = bless { items => [], opts => $opts }, $class;
    $self;
}

sub items { $_[0]->{items} }

sub add {
    my ($self, $item) = @_;
    check_item($item, $item_schema, '.');
    push @{$self->{items}}, $item;
    $self;
}

sub error { $_[0]->add({ errors => [ $_[1] ] }) }

sub check_item {
    my ($item, $schema, $path) = @_;
    return if $schema == ANY;
    if (!defined $item) {
        !ref $schema && ($schema & OPT) ? return : croak "Undef at $path";
    }
    my $ref_schema = ref $schema || '<undef>';
    my $ref_item = ref $item || '<undef>';
    $ref_item eq $ref_schema
        or croak sprintf 'Got %s instead of %s at %s', $ref_item, $ref_schema, $path;
    if ($ref_schema eq 'HASH') {
        for (keys %$item) {
            my $s = $schema->{$_} or croak "Unknown key $path/$_";
            check_item($item->{$_}, $s, "$path/$_");
        }
    }
    elsif ($ref_schema eq 'ARRAY') {
        check_item($_, $schema->[0], "$path\@") for @$item;
    }
    elsif (!ref $schema) {
        my $s = $schema & (OPT - 1);
        if ($s == INT) {
            $item =~ /^\d+$/ or croak "Got $item instead of INT at $path";
        }
        elsif ($s == FLOAT) {
            $item =~ /^\d+(:?\.\d+)?$/ or croak "Got $item instead of FLOAT at $path";
        }
        elsif ($s != STR) {
            croak "Bad schema at $path";
        }
    }
    else {
        croak "Bad schema at $path";
    }
}

1;
