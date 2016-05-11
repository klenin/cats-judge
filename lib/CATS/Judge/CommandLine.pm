package CATS::Judge::CommandLine;

use strict;
use warnings;

use Getopt::Long qw(GetOptions);

sub new {
    my ($class) = shift;
    my $self = { command => '', opts => {} };
    bless $self => $class;
}

sub command { $_[0]->{command} }
sub opts { $_[0]->{opts} }

sub usage
{
    my ($error) = @_;
    print "$error\n" if $error;
    my (undef, undef, $cmd) = File::Spec->splitpath($0);
    print <<"USAGE";
Usage:
    $cmd serve
    $cmd install --problem <zip_or_directory_or_name>
    $cmd run --problem <zip_or_directory_or_name>
        --solution <file>... [--de <de_code>] [--testset <testset>]
        [--result text|html] [--result=columns <regexp>]
    $cmd download --problem <zip_or_directory_or_name>
        --system cats|polygon --contest <url>
    $cmd upload --problem <zip_or_directory_or_name>
        --system cats|polygon --contest <url>
    $cmd config --print <regexp>
    $cmd help|-?

Common options:
    --config-set <name>=<value> ...
    --db
    --package cats|polygon
    --verbose
USAGE
    exit;
}

my %commands = (
    '-?' => [],
    config => [
        '!print:s'
    ],
    download => [
        '!problem=s',
        '!system=s',
        '!contest=s',
    ],
    help => [],
    install => [
        '!problem=s',
    ],
    run => [
        '!problem=s',
        '!run=s@',
        'de=i',
        'testset=s',
        'result=s',
        'result-columns=s',
    ],
    serve => [],
    upload => [
        '!problem=s',
        '!system=s',
        '!contest=s',
    ],
);

sub get_command {
    my ($self) = @_;
    my $command = shift(@ARGV) // '';
    $command or usage('Command required');
    my @candidates = grep /^\Q$command\E/, keys %commands;
    @candidates == 0 and usage("Unknown command '$command'");
    @candidates > 1 and usage(sprintf "Ambiguous command '$command' (%s)", join ', ', sort @candidates);
    $self->{command} = $candidates[0];
}

sub get_options {
    my ($self) = @_;
    my $command = $self->command;
    GetOptions(
        $self->opts,
        'help|?',
        'db',
        'config-set=s%',
        'package=s',
        'verbose',
        map m/^\!?(.*)$/, @{$commands{$command}},
    ) or usage;
    usage if $command =~ /^(help| -?)$/ || defined $self->opts->{help};

    for (@{$commands{$command}}) {
        m/^!([a-z\-]+)/ or next;
        defined $self->opts->{$1} or die "Command $command requires --$1 option";
    }
}

sub parse {
    my ($self) = @_;
    $self->get_command;
    $self->get_options;
}

1;
