package CATS::SourceManager;

use strict;
use warnings;

use CATS::Utils qw(escape_xml);
use CATS::Constants;
use CATS::Problem::BinaryFile;

use File::Spec;
use XML::Parser::Expat;
use Scalar::Util qw(looks_like_number);

sub get_tags()
{[
    'id',
    'stype',
    'guid',
    'code',
    'memory_limit',
    'time_limit',
    'input_file',
    'output_file',
    'fname',
    'src',
]}

sub on_end_tag
{
    my ($source, $text, $p, $el, %atts) = @_;
    for (@{get_tags()}) {
        if ($el eq $_) {
            $$text =~ s/^\s+//;
            $$text += 0 if looks_like_number($$text);
            $source->{$_} = $$text ne '' ? $$text : undef;
            last;
        }
    }
    $$text = undef;
}

sub save
{
    my ($source, $dir) = @_;
    -d $dir || mkdir $dir || die "Unable to create $dir";
    $source->{guid} or return;
    my $fname = File::Spec->catfile($dir, "$source->{guid}.xml");
    {
        open my $fh, '>', $fname or die "Unable to open $fname for writing";
        print $fh "<description>\n";
        print $fh "<$_>" . escape_xml($source->{$_} ? $source->{$_} : '') . "</$_>\n" for (@{get_tags()});
        print $fh "</description>";
    }
}

sub save_all
{
    my ($sources, $dir) = @_;
    save($_, $dir) for @$sources;
}

sub load
{
    my ($guid, $dir) = @_;
    my $fname = File::Spec->catfile($dir, "$guid.xml");

    my $parser = XML::Parser::Expat->new;
    my $text = undef;
    my $source = {};
    $parser->setHandlers(
        End => sub { on_end_tag($source, \$text, @_) },
        Char => sub { $text .= $_[1] if defined $text || (!defined $text && $_[1] ne "\n") },
    );
    CATS::Problem::BinaryFile::load($fname, \my $data);
    $parser->parse($data);
    return $source;
}


1;
