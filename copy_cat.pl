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
    $FindBin::Script -i <input> -o <output> -m <mode> [-l <line>]

Options:
    #-i#    Input file
    #-o#    Output file
    #-m#    *STDOUT, *NONE or FILE
    #-l#    Copy only line with given number
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
    'l=i' => \(my $line_number = ''),
);

$input && ($output || $mode) or usage;

my $is_stdout = $mode =~ /^\*STDOUT|\*NONE$/;
if ($line_number) {
    my $fout;
    if ($is_stdout) {
        $fout = *STDOUT;
    }
    else {
        open $fout, '>', $output or die $!;
    }
    open my $fin, '<', $input or die $!;
    for (my $line = 1; <$fin>; ++$line) {
        print $fout $_ if $line == $line_number;
    }
}
elsif ($is_stdout) {
    open my $fin, '<', $input or die $!;
    print while <$fin>;
}
else {
    CATS::FileUtil->new({ logger => CATS::Logger::Die->new })->copy($input, $output);
}
