package CATS::Judge::Local;

use v5.10;
use strict;
use warnings;

use List::Util qw (max);
use Encode qw(encode_utf8);
use POSIX qw(strftime);

use CATS::Constants;
use CATS::ConsoleColor;
use CATS::Problem::Parser;
use CATS::Problem::ImportSource;
use CATS::Problem::Source::Zip;
use CATS::Problem::Source::PlainFiles;

use CATS::Utils qw(split_fname);

use base qw(CATS::Judge::Base);

my $pid;

sub auth {
    my ($self) = @_;
    return;
}

sub get_problem_id {
    $pid ||= Digest::MD5::md5_hex(Encode::encode_utf8($_[0]->{parser}{problem}{description}{title}))
}

sub update_state {
    my ($self) = @_;
    0;
}

sub set_request_state {
    my ($self, $req, $state, %p) = @_;
}

sub select_request {
    my ($self, $supported_DEs) = @_;
    -f $self->{problem} or -d $self->{problem} or die "Bad problem '$self->{problem}'";

    my $source = -f $self->{problem} ?
        CATS::Problem::Source::Zip->new($self->{problem}, $self->{logger}) :
        CATS::Problem::Source::PlainFiles->new(dir => $self->{problem}, logger => $self->{logger});

    my $import_source = $self->{db} ?
        CATS::Problem::ImportSource::DB->new :
        CATS::Problem::ImportSource::Local->new(modulesdir => $self->{modulesdir});

    $self->{parser} = CATS::Problem::Parser->new(
        id_gen => \&CATS::DB::new_id,
        source => $source,
        import_source => $import_source,
    );

    eval { $self->{parser}->parse; };
    die "Problem parsing failed: $@" if $@;

    !$self->{run} or open FILE, $self->{run} or die "Couldn't open file: $!";
    {
        id => $self->{run} || 0,
        problem_id => $self->get_problem_id,
        contest_id => 0,
        state => 1,
        is_jury => 0,
        run_all_tests => 1,
        status => $cats::problem_st_ready,
        fname => $self->{run},
        src => $self->{run} ? (join '', <FILE>) : '',
        de_id => $self->{de},
    };
}

sub save_log_dump {
    my ($self, $req, $dump) = @_;
}

sub set_DEs {
    my ($self, $cfg_de) = @_;
    while (my ($key, $value) = each %$cfg_de) {
        $value->{code} = $value->{id} = $key;
    }
    $self->{supported_DEs} = $cfg_de;
}

sub set_def_DEs {
    my ($self, $cfg_def_DEs) = @_;
    $self->{def_DEs} = $cfg_def_DEs;
    $self->{de} = $self->auto_detect_de($self->{run}) if !$self->{de} && $self->{run};
}

sub pack_problem_source
{
    my ($self, %p) = @_;
    use Carp;
    my $s = $p{source_object} or confess;
    {
        id => defined $s->{id} ? $s->{id} : undef,
        problem_id => $self->get_problem_id,
        code => $s->{de_code},
        de_id => defined $s->{de_code} ? $self->{supported_DEs}{$s->{de_code}}{id} || -1 : -1,
        src => $s->{src},
        stype => $p{source_type},
        fname => $s->{path},
        input_file => $s->{inputFile},
        output_file => $s->{outputFile},
        guid => $s->{guid},
        time_limit => $s->{time_limit},
        memory_limit => $s->{memory_limit},
    }
}

sub auto_detect_de {
    my ($self, $fname) = @_;
    my (undef, undef, undef, undef, $ext) = split_fname($fname);
    defined $self->{def_DEs}{$ext} or die "Can not auto-detect DE for file $fname";
    $self->{def_DEs}{$ext};
}

sub ensure_de {
    my ($self, $source) = @_;
    $source->{de_id} = $source->{code} = $self->auto_detect_de($source->{fname}) if !$source->{code};
    exists $self->{supported_DEs}{$source->{code}}
        or die "Unsupported de: $_->{code} for source '$source->{fname}'";
}

sub get_problem_sources {
    my ($self, $pid) = @_;

    my $problem = $self->{parser}->{problem};
    my $problem_sources = [];

    if (my $c = $problem->{checker}) {
        push @$problem_sources, $self->pack_problem_source(
            source_object => $c, source_type => CATS::Problem::checker_type_names->{$c->{style}},
        );
    }

    for (@{$problem->{validators}}) {
        push @$problem_sources, $self->pack_problem_source(
            source_object => $_, source_type => $cats::validator,
        );
    }

    for(@{$problem->{generators}}) {
        push @$problem_sources, $self->pack_problem_source(
            source_object => $_, source_type => $cats::generator,
        );
    }

    for(@{$problem->{solutions}}) {
        push @$problem_sources, $self->pack_problem_source(
            source_object => $_, source_type => $_->{checkup} ? $cats::adv_solution : $cats::solution,
        );
    }

    for (@{$problem->{modules}}) {
        push @$problem_sources, $self->pack_problem_source(
            source_object => $_, source_type => $_->{type_code},
        );
    }

    for my $source ($self->{parser}{import_source}->get_sources_info($problem->{imports})) {
        $source->{problem_id} = $self->get_problem_id;
        $source->{de_id} = $self->{supported_DEs}{$source->{code}}{id};
        push @$problem_sources, $source;
    }

    $self->ensure_de($_) for @$problem_sources;

    [ @$problem_sources ];
}

sub delete_req_details {
    my ($self, $req_id) = @_;
    delete $self->{results}->{$req_id};
}

sub insert_req_details {
    my ($self, $p) = @_;
    push @{$self->{results}->{$p->{req_id}}}, $p;
}

sub get_problem_tests {
    my ($self, $pid) = @_;
    my $tests = [];
    for (sort { $a->{rank} <=> $b->{rank} } values %{$self->{parser}{problem}->{tests}}) {
        push @$tests, {
            generator_id => $_->{generator_id},
            rank => $_->{rank},
            param => $_->{param},
            std_solution_id => $_->{std_solution_id},
            in_file => $_->{in_file},
            out_file => $_->{out_file},
            gen_group => $_->{gen_group}
        };
    }
    [ @$tests ];
}

sub get_problem {
    my ($self, $pid) = @_;
    die "no parser" if !defined $self->{parser};
    my $p = $self->{parser}{problem}{description};
    {
        id => $self->get_problem_id,
        title => $p->{title},
        upload_date => strftime(
            $CATS::Judge::Base::timestamp_format, localtime $self->{parser}->{source}->last_modified),
        time_limit => $p->{time_limit},
        memory_limit => $p->{memory_limit},
        input_file => $p->{input_file},
        output_file => $p->{output_file},
        std_checker => $p->{std_checker},
        contest_id => 0
    };
}

sub is_problem_uptodate {
    my ($self, $pid, $cached_date) = @_;
    my $upload_date = $self->get_problem($pid)->{upload_date};
    # date format: dd-mm-yyyy hh:mm:ss -> yyyy-mm-dd hh:mm:ss
    $upload_date =~ m/^(\d+)-(\d+)-(\d+)\s(.+)$/ or return 0;
    $upload_date = "$3-$2-$1 $4";
    return $upload_date le $cached_date;
}

sub get_testset {
    my ($self, $rid, $update) = @_;
    $self->{testset} or return map { $_->{rank} => undef } values %{$self->{parser}{problem}{tests}};

    my @all_tests = map { $_->{rank} } values %{$self->{parser}{problem}{tests}};
    my %tests = %{CATS::Testset::parse_test_rank($self->{parser}{problem}{testsets}, $self->{testset})};
    map { exists $tests{$_} ? ($_ => $tests{$_}) : () } @all_tests;
}

use constant headers => (
    { c => 'Test'   , n => 'test_rank',       a => 'right'  },
    { c => 'Result' , n => 'result',          a => 'center' },
    { c => 'Time'   , n => 'time_used',       a => 'left'   },
    { c => 'Memory' , n => 'memory_used',     a => 'right'  },
    { c => 'Disk'   , n => 'disk_used',       a => 'right'  },
    { c => 'Comment', n => 'checker_comment', a => 'left'   },
);

use constant state_styles => {
    $cats::st_accepted                => { r => 'OK', c => '#A0FFA0', t => 'green' },
    $cats::st_wrong_answer            => { r => 'WA', c => '#FFA0A0', t => 'red' },
    $cats::st_presentation_error      => { r => 'PE', c => '#FFFFA0', t => 'yellow bold' },
    $cats::st_time_limit_exceeded     => { r => 'TL', c => '#FFFFFF', t => 'cyan bold' },
    $cats::st_runtime_error           => { r => 'RE', c => '#FFA0A0', t => 'magenta' },
    $cats::st_memory_limit_exceeded   => { r => 'ML', c => '#FFA0A0', t => 'cyan bold' },
    $cats::st_idleness_limit_exceeded => { r => 'IL', c => '#FFA0A0', t => 'cyan bold' },
    $cats::st_unhandled_error         => { r => 'UH', c => '#FFA0A0', t => 'on_red' },
    $cats::st_compilation_error       => { r => 'CE', c => '#FFA0A0', t => 'red' },
};

sub filtered_headers {
    my ($self) = @_;
    grep !$self->{'result-columns'} || $_->{c} =~ m/$self->{'result-columns'}/, headers;
}

sub html_result {
    my ($self) = @_;
    my $sid = (keys %{$self->{results}})[0];
    defined $sid or return;
    my @headers = $self->filtered_headers;
    my @results = @{$self->{results}->{$sid}};
    my $html_name = strftime($CATS::Judge::Base::timestamp_format, localtime);
    $html_name =~ tr/:/\./;
    $html_name = "$self->{resultsdir}/$html_name.html";
    open my $html, '>', $html_name or die "Can't open '$html_name': $!";
    print $html join "\n",
        '<!DOCTYPE html>',
        '<html>',
        '<head>',
        '  <meta charset="utf-8" >',
        '  <title>' . encode_utf8($self->{parser}{problem}{description}{title}) . '</title>',
        '  <style>',
        map("    .$_->{r} { background-color: $_->{c} }", values %{state_styles()}),
        '    .border { border: 1px solid #4040ff; }',
        '    .left { text-align: left }',
        '    .right { text-align: right }',
        '    .center { text-align: center }',
        '  </style>',
        '</head>',
        '<body>',
        '<table class="border">',
        '<tr>',
        map("<th>$_->{c}</th>", @headers),
        "</tr>\n";
    $_->{result} = state_styles->{$_->{result}}->{r} for @results;
    for my $res (@results) {
        my ($state) = grep $res->{result} eq $_->{r}, values %{state_styles()};
        print $html qq~<tr class="$state->{r}">~;
        print $html join '',
            map sprintf('<td class="%s">%s</td>',
                $_->{a}, encode_utf8($res->{$_->{n}} // '')), @headers;
        print $html "</tr>\n";
    }
    print $html "</table>\n";
    print $html "</body></html>\n";
}

sub get_cell {
    my ($value, $width, $align, $color) = @_;
    $width -= length($value);
    my $left = { center => int($width / 2), left => 1, right => $width - 1 }->{$align};
    my $cell = (' ' x $left) . $value . (' ' x ($width - $left));
    $color ? CATS::ConsoleColor::colored($cell, $color) : $cell;
}

sub ascii_result {
    my ($self) = @_;
    my @runs = sort keys %{$self->{results}} or return;
    for my $req_results (values %{$self->{results}}) {
        for (@$req_results) {
            my $st = state_styles->{$_->{result}};
            $_->{result} = $st->{r};
            $_->{result__color} = $st->{t};
        }
    }
    my @headers = map {
        my $k = $_;
        my $first = 0;
        map +{ %$_, r => $k, f => !$first++ }, $self->filtered_headers;
    } @runs or return;
    my %run_widths = map +{ $_ => 0 }, @runs;
    for my $h (@headers) {
        $h->{width} = 2 + max(length $h->{c},
            map length($_->{$h->{n}} // ''), @{$self->{results}->{$h->{r}}});
        $run_widths{$h->{r}} += $h->{width};
    }
    say join('|', map get_cell($_, $run_widths{$_} + (@headers / @runs) - 1, 'left'), @runs);
    my $separator = join '+', map '-' x $_->{width}, @headers;
    say $separator;
    say join('|', map get_cell($_->{c}, $_->{width}, 'center'), @headers);
    say $separator;
    for my $i (0 .. max(map scalar $#$_, values %{$self->{results}})) {
        say join('|', map {
            my $row = $self->{results}->{$_->{r}}->[$i];
            get_cell($row->{$_->{n}} // '', $_->{width}, $_->{a}, $row->{$_->{n} . '__color'});
        } @headers);
    }
    say $separator;
}

sub finalize {
    my $self = shift;
    $self->{run} or return;
    $self->{result} && $self->{result} eq 'html' ? $self->html_result : $self->ascii_result;
}

1;
