use strict;
use warnings;

package CATS::Spawner;

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

package CATS::Spawner::ReportItem;

use CATS::Spawner::Const ':all';

sub new {
    my ($class, $self) = @_;
    bless $self, $class;
}

sub errors { $_[0]->{errors} }
sub tr_ok { !@{$_[0]->errors} && $_[0]->{terminate_reason} == $TR_OK }
sub ok { $_[0]->tr_ok && $_[0]->{exit_code} == 0 }

package CATS::Spawner::Report;

use Carp qw(croak);

use CATS::Spawner::Const ':all';
use CATS::Utils qw(group_digits);

use constant { ANY => 1, INT => 2, STR => 3, FLOAT => 4, OPT => 128 };

my $item_schema = {
    params => ANY,
    application => STR,
    arguments => [ STR ],
    method => OPT | STR,
    security => {
        level => OPT | INT,
        user_name => OPT | STR,
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
    original_terminate_reason => STR,
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
    my ($class, $opts, $exit_code) = @_;
    my $self = bless { items => [], opts => $opts, exit_code => $exit_code }, $class;
    $self;
}

sub items { $_[0]->{items} }

sub add {
    my ($self, $item) = @_;
    check_item($item, $item_schema, '.');
    push @{$self->{items}}, CATS::Spawner::ReportItem->new($item);
    $self;
}

sub exit_code { defined $_[1] ? $_[0]->{exit_code} = $_[1] : $_[0]->{exit_code} }

sub error { $_[0]->add({ errors => [ $_[1] ] }) }

sub check_item {
    my ($item, $schema, $path) = @_;
    $schema or die 'Schema required';
    return 1 if $schema == ANY;
    return 1 if !defined $item && !ref $schema && ($schema & OPT);
    $item //= {} if ref $schema eq 'HASH';
    $item //= [] if ref $schema eq 'ARRAY';
    ref $item eq ref $schema
        or croak sprintf 'Got %s instead of %s at %s',
        ref $item  || (defined $item ? 'scalar' : '<undef>'), ref $schema || $schema, $path;
    if (ref $schema eq 'HASH') {
        $schema->{$_} or croak "Unknown key $path/$_" for keys %$item;
        check_item($item->{$_}, $schema->{$_}, "$path/$_") for keys %$schema;
    }
    elsif (ref $schema eq 'ARRAY') {
        my $i = 0;
        check_item($_, $schema->[0], "$path#" . $i++) for @$item;
    }
    elsif (!ref $schema) {
        my $s = $schema & (OPT - 1);
        if ($s == INT) {
            $item //= '<undef>';
            $item =~ /^\d+$/ or croak sprintf 'Got %s instead of INT at %s', $item, $path;
        }
        elsif ($s == FLOAT) {
            $item //= '<undef>';
            $item =~ /^\d+(:?\.\d+)?(:?e[+\-]?\d+)?$/
                or croak sprintf 'Got %s instead of FLOAT at %s', $item, $path;
        }
        elsif ($s == STR) {
            defined $item or croak sprintf 'Got <undef> instead of STR at %s', $path;
        }
        else {
            croak "Bad schema at $path";
        }
    }
    else {
        croak "Bad schema at $path";
    }
    1;
}

sub write_to_log {
    my ($self, $log) = @_;

    for my $item (@{$self->items}) {
        $log->msg("-> Process: %s | ", $item->{application});
        if (@{$item->{errors}}) {
            $log->msg("spawner error: %s\n", join(' ', @{$item->{errors}}));
            next;
        }

        my $reason = $item->{terminate_reason};
        my $msg = {
            $TR_TIME_LIMIT => "time limit exceeded\n",
            $TR_IDLENESS_LIMIT => "idleness limit exceeded\n",
            $TR_WRITE_LIMIT => "write limit exceeded\n",
            $TR_MEMORY_LIMIT => "memory limit exceeded\n",
        }->{$reason};

        if ($msg) {
            $log->msg($msg);
        }
        elsif ($reason == $TR_OK && $item->{exit_code} != 0) {
            $log->msg("exit code: $item->{exit_code}\n");
        }
        elsif ($reason == $TR_ABORT) {
            $log->msg("abnormal termination. code: $item->{exit_code}, status: $item->{exit_code}\n");
        }
        elsif ($reason == $TR_SECURITY) {
            $log->msg("secirity violated: $item->{original_terminate_reason}\n");
        }
        my $c = $item->{consumed};
        $log->msg(sprintf
            "User: %.2f s | Wall: %.2f s | Memory: %s b | Written: %s b\n",
            $c->{user_time}, $c->{wall_clock_time}, map group_digits($c->{$_}, '_'), qw(memory write)
        );
    }
    $self;
}

1;
