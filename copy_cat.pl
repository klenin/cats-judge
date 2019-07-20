use strict;
use warnings;

use File::Spec;
use FindBin;
use Getopt::Long qw(GetOptions);

use lib File::Spec->catdir($FindBin::Bin, 'lib');
use lib File::Spec->catdir($FindBin::Bin, 'lib', 'cats-problem');

use CATS::ConsoleColor;
use CATS::FileUtil;
use CATS::Loggers;

sub usage {
    my ($error) = @_;
    print "$error\n" if $error;

    my $text = <<"USAGE";
Copies input to either output or STDOUT.

Usage:
    $FindBin::Script -i <input> -o <output> -m <mode>

Options:
    #-i#    Input file
    #-o#    Output file
    #-m#    *STDOUT, *NONE or output file name
USAGE
    ;
    $text =~ s/#(\S+)#/CATS::ConsoleColor::colored($1, 'bold white')/eg;
    print $text;
    exit;
}

GetOptions(
    'i=s' => \(my $input),
    'o=s' => \(my $output),
    'm=s' => \(my $mode = ''),
);

$input && ($output || $mode) or usage;

if ($mode =~ /^\*STDOUT|\*NONE$/) {
    open my $fin, '<', $input;
    print while <$fin>;
}
else {
    CATS::FileUtil->new({ logger => CATS::Logger::Die->new })->copy($input, $output);
}
