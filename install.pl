use strict;
use warnings;

use File::Copy qw(copy);
use File::Spec;

$| = 1;
print "Installing cats-judge\n";

my $step_count = 0;

sub step($&) {
    my ($msg, $action) = @_;
    print ++$step_count, ". $msg ...";
    $action->();
    print " ok\n";
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
    my @bad = grep !eval "require $_; 1;", qw(DBI JSON::XS XML::Parser::Expat);
    die join "\n", 'Some required modules not found:', @bad, '' if @bad;
};

step 'Verifying optional modules', sub {
    my @bad = grep !eval "require $_; 1;", qw(FormalInput);
    warn join "\n", 'Some optional modules not found:', @bad, '' if @bad;
};

step 'Cloning sumbodules', sub {
    `git submodule update --init` or die $!;
};

my @p = qw(lib cats-problem CATS);
step_copy(File::Spec->catfile(@p, 'Config.pm.template'), File::Spec->catfile(@p, 'Config.pm'));

step_copy('config.xml.template', 'config.xml');
