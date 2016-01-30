use v5.10;
use strict;
use warnings;

use File::Copy qw(copy);
use File::Spec;
use Getopt::Long;
use IPC::Cmd;

use lib 'lib';
use CATS::DevEnv::Detector::Utils qw(globq);

$| = 1;

sub usage
{
    my (undef, undef, $cmd) = File::Spec->splitpath($0);
    print <<"USAGE";
Usage:
    $cmd
    $cmd --step <num> ... [--devenv <devenv-filter>]
    $cmd --help|-?
USAGE
    exit;
}

GetOptions(
    \my %opts,
    'step=i@',
    'devenv=s',
    'help|?',
) or usage;
usage if defined $opts{help};

print "Installing cats-judge\n";

my %filter_steps;
if ($opts{step}) {
    my @steps = @{$opts{step}};
    undef @filter_steps{@steps};
    printf "Will only run steps: %s\n", join ' ', sort { $a <=> $b } @steps;
}

my $step_count = 0;

sub step($&) {
    my ($msg, $action) = @_;
    print ++$step_count, ". $msg ...";
    if (!%filter_steps || exists $filter_steps{$step_count}) {
        $action->();
        print " ok\n";
    }
    else {
        print " skipped\n";
    }
}

sub step_copy {
    my ($from, $to) = @_;
    step "Copying $from -> $to", sub {
        -e $to and die "Destination already exists: $to";
        copy($from, $to) or die $!;
    };
}

step 'Verifying', sub {
    -f 'judge.pl' && -d 'lib' or die 'Must run from cats-judge directory';
    -f 'config.xml' and die 'Seems to be already installed';
};

step 'Verifying git', sub {
    my $x = `git --version` or die 'Git not found';
    $x =~ /^git version/ or die "Git not found: $x";
};

step 'Verifying required modules', sub {
    my @bad = grep !eval "require $_; 1;", qw(DBI JSON::XS XML::Parser::Expat File::Copy::Recursive);
    die join "\n", 'Some required modules not found:', @bad, '' if @bad;
};

step 'Verifying optional modules', sub {
    my @bad = grep !eval "require $_; 1;", qw(FormalInput IPC::Run);
    warn join "\n", 'Some optional modules not found:', @bad, '' if @bad;
};

step 'Cloning sumbodules', sub {
    system('git submodule update --init');
    $? and die "Failed: $?, $!";
};

step 'Disabling Windows Error Reporting UI', sub {
    CATS::DevEnv::Detector::Utils::disable_windows_error_reporting_ui;
};

step 'Detecting development environments', sub {
    IPC::Cmd->can_capture_buffer or die 'IPC::Cmd failed';
    print "\n";
    CATS::DevEnv::Detector::Utils::disable_error_dialogs;
    for (globq(File::Spec->catfile(qw[lib CATS DevEnv Detector *.pm]))) {
        my ($name) = /(\w+)\.pm$/;
        next if $name =~ /^(Utils|Base)$/ || $opts{devenv} && $name !~ qr/$opts{devenv}/i;
        require $_;
        my $d = "CATS::DevEnv::Detector::$name"->new;
        printf "    Detecting %s:\n", $d->name;
        printf "      %s %-12s %s\n",
            ($_->{preferred} ? '*' : $_->{valid} ? ' ' : '?'), $_->{version}, $_->{path} for values %{$d->detect};
    }
};

my @p = qw(lib cats-problem CATS);
step_copy(File::Spec->catfile(@p, 'Config.pm.template'), File::Spec->catfile(@p, 'Config.pm'));

step_copy('config.xml.template', 'config.xml');
