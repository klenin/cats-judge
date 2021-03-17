my $x = do { open my $f, '<', $ARGV[0] or die $!; <$f>; };
open $f, '>', $ARGV[0] or die $!;
print $f $x + 1;
