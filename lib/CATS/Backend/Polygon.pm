package CATS::Backend::Polygon;

use strict;
use warnings;

use Archive::Zip;
use Cwd;
use Encode;
use File::Glob 'bsd_glob';
use File::Temp qw(tempfile tempdir);
use File::Spec;
use List::Util 'max';

my $has_mechanize;
BEGIN { $has_mechanize = eval { require WWW::Mechanize; require HTML::TreeBuilder; 1; } }

sub new {
    my ($class, $problem, $log, $problem_path, $url, $exist_problem, $root, $proxy, $verbose) = @_;
    $has_mechanize or $log->error('WWW::Mechanize is required to use Polygon back-end');
    my $self = {
        root => $root,
        problem => $problem,
        log => $log,
        name => $exist_problem ? $problem->{description}{title} : $problem_path,
        path => $exist_problem ? $problem_path : "$problem_path.zip",
        url => $url,
        mech => WWW::Mechanize->new(autocheck => 1, ssl_opts => { verify_hostname => 0 }),
        pid => undef,
        ccid => undef,
        session => undef,
        downloading => {
            tests => [],
            sources => [],
            xml => undef,
            input_file => undef,
            output_file => undef,
            memory_limit => undef,
            time_limit => undef,
            pattern => undef,
        },
        verbose => $verbose,
    };
    ($self->{ccid}) = $url =~ m/ccid=([a-z0-9]+)/;
    ($self->{name}) = $url =~ m~/p/[a-zA-Z0-9-]+/([a-zA-Z0-9-]+)~;
    $self->{mech}->proxy('https', $proxy) if $proxy;
    return bless $self => $class;
}

sub needs_login { !defined $_[0]->{ccid} }

sub login {
    my ($self, $login, $password) = @_;
    my $mech = $self->{mech};
    $mech->get("$self->{root}/login");
    $mech->form_with_fields('login', 'password');
    $mech->set_fields(
        login => $login,
        password => $password,
    );
    $mech->submit;
    $mech->uri->path eq '/problems' or die 'invalid login/email or password';
}

sub start {
    my $self = shift;
    my $mech = $self->{mech};
    my $log = $self->{log};
    my $elem = HTML::TreeBuilder->new_from_content($mech->content)->look_down(_tag => 'tr', problemName => $self->{name});
    $self->{pid} = $elem->{problemid} or $log->error('problem not found');
    ($self->{ccid}) = $mech->uri =~ m/ccid=([a-z0-9]*)/;
    if ($self->{mech}->find_link(url_regex => qr/edit-start\?problemId=$self->{pid}/)) {
        $self->{mech}->get("/edit-start\?problemId=$self->{pid}\&ccid=$self->{ccid}");
    } else {
        $self->{mech}->get($elem->look_down(_tag => 'a', class => 'CONTINUE_EDIT_SESSION')->{href});
    }
    ($self->{session}) = $mech->uri =~ m/session=([a-z0-9]*)&ccid=$self->{ccid}/;
}

sub list { die 'Not implemented' }

sub upload_statements {
    my $self = shift;
    my $mech = $self->{mech};
    my $problem = $self->{problem};
    $mech->uri =~ m/generalInfo/ or $mech->get("generalInfo\?ccid=$self->{ccid}&session=$self->{session}");
    $mech->form_with_fields('inputFile', 'outputFile', 'timeLimit', 'memoryLimit');
    $mech->set_fields(
        inputFile => $problem->{description}{input_file},
        outputFile => $problem->{description}{output_file},
        timeLimit => $problem->{description}{time_limit} * 1000,
        memoryLimit => $problem->{description}{memory_limit},
    );
    $mech->submit;
}

sub upload {
    my ($self, $path, $input) = @_;
    my $mech = $self->{mech};
    $mech->form_with_fields($input);
    my $wd = Cwd::cwd();
    my ($new_wd, $fname) = File::Spec->catfile($self->{path}, $path) =~ m/^(.*)[\\\/](.*)$/;
    chdir($new_wd);
    $mech->set_fields($input => $fname);
    $mech->submit;
    chdir($wd);
}

sub upload_one_source {
    my ($self, $path, $name) = @_;
    $path or return;
    my $mech = $self->{mech};
    my $problem = $self->{problem};
    $mech->get("$name\?ccid=$self->{ccid}&session=$self->{session}");
    $self->upload($path, 'file_added');
}

sub upload_generators {
    my $self = shift;
    my $mech = $self->{mech};
    my $problem = $self->{problem};
    $mech->get("files\?ccid=$self->{ccid}&session=$self->{session}");
    $self->upload($_->{path}, 'source_file_added') for @{$problem->{generators}};
}

sub upload_modules {
    my $self = shift;
    my $mech = $self->{mech};
    my $problem = $self->{problem};
    for (@{$problem->{modules}}) {
        if ($_->{type} eq 'checker') {
            $self->upload_one_source($_->{path}, 'checker');
        } elsif ($_->{type} eq 'validator') {
            $self->upload_one_source($_->{path}, 'validation');
        } elsif ($_->{type} eq 'generator') {
            $mech->get("files\?ccid=$self->{ccid}&session=$self->{session}");
            $self->upload($_->{path}, 'source_file_added');
        }
    }
}

sub upload_solutions {
    my $self = shift;
    my $mech = $self->{mech};
    my $problem = $self->{problem};
    $mech->get("solutions\?ccid=$self->{ccid}&session=$self->{session}");
    $self->upload($_->{path}, 'solutions_file_added') for @{$problem->{solutions}};
}

sub get_generators {
    my $self = shift;
    my $generators = $self->{problem}{generators};
    my $gen_table;
    for (@{$generators}) {
        $_->{path} =~ m/([^\\\/]*)\.(.*)$/;
        $gen_table->{$_->{id}} = $1;
    }
    $gen_table;
}

sub upload_tests {
    my $self = shift;
    $self->upload_generators;
    my $mech = $self->{mech};
    $mech->get("tests\?ccid=$self->{ccid}\&session=$self->{session}");
    $mech->get("tests\?action=add\&testset=tests\&ccid=$self->{ccid}\&session=$self->{session}");
    my $gen_table = $self->get_generators();
    for my $test (values %{$self->{problem}{tests}}) {
        $mech->form_with_fields('testIndex', 'testType', 'testScriptLine', 'testInput');
        $test->{generator_id}
            ? $mech->set_fields(
                testIndex => $test->{rank},
                testType => 'Script',
                testScriptLine => $gen_table->{$test->{generator_id}} . ' ' . $test->{param},
            )
            : $mech->set_fields(
                testIndex => $test->{rank},
                testType => 'Manual',
                testInput => $test->{in_file},
            );
        $mech->submit;
    }
}

sub upload_problem {
    my $self = shift;
    my $mech = $self->{mech};
    my $problem = $self->{problem};
    $self->upload_statements;
    $self->upload_one_source($problem->{checker}{path}, 'checker');
    $self->upload_one_source($problem->{validators}[0]{path}, 'validation');
    $self->upload_modules($problem->{modules});
    $self->upload_solutions;
    $self->upload_tests;
}

sub download_statements {
    my $self = shift;
    my $mech = $self->{mech};
    $mech->get("/generalInfo?ccid=$self->{ccid}&session=$self->{session}");
    my $tree = HTML::TreeBuilder->new_from_content($mech->content);
    $self->{downloading}{input_file} = $tree->look_down(_tag => 'input', id => 'inputFile')->{value};
    $self->{downloading}{output_file} = $tree->look_down(_tag => 'input', id => 'outputFile')->{value};
    $self->{downloading}{time_limit} = $tree->look_down(_tag => 'input', id => 'timeLimit')->{value};
    $self->{downloading}{memory_limit} = $tree->look_down(_tag => 'input', id => 'memoryLimit')->{value} * 1024 * 1024;
}

sub set_download_links {
    my $self = shift;
    my $mech = $self->{mech};

    $mech->get("/solutions\?ccid=$self->{ccid}&session=$self->{session}?");
    my $tree = HTML::TreeBuilder->new_from_content($mech->content);
    my $main_solution_name = $tree->look_down(_tag => 'a', href => qr/modify\?type=solutions.*?back/)->as_text;
    for ($tree->look_down(_tag => 'a', href => qr/solutions\/(.*?)\?file=\1&action=view&ccid=$self->{ccid}/)) {
        my ($name) = $_->{href} =~ m/solutions\/(.*?)\?file=\1&action=view&ccid=$self->{ccid}/;
        push @{$self->{downloading}{sources}}, {
            url => "$self->{root}/solutions/$name?file=$name&action=view&ccid=$self->{ccid}&session=$self->{session}",
            type => 'solution',
            dir => 'solutions',
            name => $name,
            content => undef,
            is_main => $name eq $main_solution_name,
        }
    }

    $mech->get("/files\?ccid=$self->{ccid}&session=$self->{session}?");
    $tree = HTML::TreeBuilder->new_from_content($mech->content);
    for my $type (qw[source resource]) {
        for ($tree->look_down(_tag => 'a', href => qr/files\/(.*?)\?type=$type&file=\1&action=view&ccid=$self->{ccid}/)) {
            my ($name) = $_->{href} =~ m/files\/(.*?)\?type=$type&file=\1&action=view&ccid=$self->{ccid}/;
            push @{$self->{downloading}{sources}}, {
                url => "$self->{root}/files/$name?type=$type&file=$name&action=view&ccid=$self->{ccid}&session=$self->{session}",
                type => $type,
                dir => 'files',
                name => $name,
                content => undef,
            }
        }
    }

    $mech->get("/checker\?ccid=$self->{ccid}&session=$self->{session}");
    $mech->content =~ m/value="$_->{name}"\s+selected/ and $_->{type} = 'checker' for @{$self->{downloading}{sources}};
    $mech->get("/validation\?ccid=$self->{ccid}&session=$self->{session}");
    $mech->content =~ m/value="$_->{name}"\s*selected/ and $_->{type} = 'validator' for @{$self->{downloading}{sources}};
    for (@{$self->{downloading}{sources}}) {
        $mech->get($_->{url});
        $_->{content} = $mech->content;
    }
}

sub set_tests {
    my $self = shift;
    my $mech = $self->{mech};
    $mech->get("$self->{root}/tests\?ccid=$self->{ccid}&session=$self->{session}");
    # HTML::Element: Text under <script> or <style> elements is never included in what's returned
    for my $tr ($mech->content =~ m/(<tr id="test_\d*">[\s\S]*?ccid=$self->{ccid}.[\s\S]*?<\/tr>)/g) {
        my ($rank) = $tr =~ m/test_(\d*)/;
        my $method = $tr =~ m/text$rank/ ? 'manual' : 'generated';
        my $content;
        ($content) = $method eq 'manual'
            ? $tr =~ m/\$\("#text$rank"\)\.text\('([\s\S]*)'\);[\s\S]*?}\);/
            : $tr =~ m/<pre.*?>([\s\S]*)<\/pre>/;
        push @{$self->{downloading}{tests}}, {
            rank => $rank,
            method => $method,
            content => $content,
        }
    }
}

sub write_archive {
    my $self = shift;
    my $log = $self->{log};
    my $dir = tempdir(CLEANUP => 1);
    $self->write_dir($dir);
    my $zip = Archive::Zip->new;
    $zip->addTree({ root => $dir });
    $zip->writeToFileNamed($self->{path});
}

sub write_dir {
    my ($self, $path) = @_;
    my $log = $self->{log};
    my $fn;
    for (@{$self->{downloading}{sources}}) {
        mkdir File::Spec->catfile($path, $_->{dir});
        open my $fh, '>', $fn = File::Spec->catfile($path, $_->{dir}, $_->{name})
            or $log->error("Can't open file $fn");
        print $fh encode_utf8($_->{content});
    }

    mkdir File::Spec->catfile($path, 'tests');
    for (@{$self->{downloading}{tests}}) {
        $_->{method} eq 'manual' or next;
        open my $fh, '>', $fn = File::Spec->catfile($path, sprintf($self->{downloading}{pattern}, $_->{rank}))
            or $log->error("Can't open file $fn");
        print $fh encode_utf8($_->{content});
    }

    open my $fh, '>', $fn = File::Spec->catfile($path, 'problem.xml') or $log->error("Can't open file $fn");
    print $fh $self->{downloading}{xml};
}

sub dumper_atts {
    my ($self, $atts) = @_;
    my $ans = '';
    $ans .= " $_=\"$atts->{$_}\"" for keys %{$atts};
    $ans;
}

sub dumper {
    my ($self, $spaces, $xml) = @_;
    my $ans = '';
    for (@$xml) {
        $_->{name} or next; # FIXME
        $ans .=
            "$spaces<$_->{name}" . $self->dumper_atts($_->{atts}) . ">" .
            ($_->{value} || ($_->{tags} ? "\n" . $self->dumper("$spaces    ", $_->{tags}) . $spaces : '')) .
            "</$_->{name}>\n";
    }
    $ans;
}

sub generate_xml {
    my $self = shift;
    my $log = $self->{log};
    my $d = $self->{downloading};

    my @tests;
    for (@{$d->{tests}}) {
        $_->{method} eq 'manual'
            ? push @tests, { name => 'test', atts => { method => $_->{method} } }
            : push @tests, { name => 'test', atts => { cmd => $_->{content}, method => $_->{method} } };
    }

    my ($checker, @generators, @resources, @solutions, @validators);
    for (@{$d->{sources}}) {
        $_->{type} eq 'checker' and $checker = { name => 'checker', atts => { path => "$_->{dir}/$_->{name}" } };
        $_->{type} eq 'source' and push @generators, { name => 'executable', atts => { path => "$_->{dir}/$_->{name}" } };
        $_->{type} eq 'resource' and push @resources, { name => 'file', atts => { path => "$_->{dir}/$_->{name}" } };
        $_->{type} eq 'solution' and push @solutions, { name => 'solution', atts => { path => "$_->{dir}/$_->{name}" } };
        $_->{type} eq 'validator' and push @validators, { name => 'validator', atts => { path => "$_->{dir}/$_->{name}" } };
    }

    my $xml_structure = [{
        name => 'problem',
        atts => {
                'short-name' => $self->{name},
            },
        tags => [
            {
                name => 'judging',
                atts => {
                    'input-file' => $d->{input_file},
                    'output-file' => $d->{output_file},
                },
                tags => [
                    {
                        name => 'testset',
                        atts => {
                            name => 'tests',
                        },
                        tags => [
                            {
                                name => 'time-limit',
                                value => $d->{time_limit},
                            }, {
                                name => 'memory-limit',
                                value => $d->{memory_limit},
                            }, {
                                name => 'test-count',
                                value => scalar @{$d->{tests}},
                            }, {
                                name => 'input-path-pattern',
                                value => $d->{pattern},
                            }, {
                                name => 'output-path-pattern',
                                value => "$d->{pattern}.a",
                            }, {
                                name => 'tests',
                                tags => \@tests,
                            },
                        ],
                    },
                ],
            }, {
                name => 'files',
                tags => [
                    {
                        name => 'resources',
                        tags => \@resources,
                    }, {
                        name => 'executables',
                        tags => \@generators,
                    },
                ],
            }, {
                name => 'assets',
                tags => [
                    $checker,
                    {
                        name => 'validators',
                        tags => \@validators,
                    }, {
                        name => 'solutions',
                        tags => \@solutions,
                    },
                ],
            },
        ],
    }];
    $d->{xml} = '<?xml version="1.0" encoding="utf-8" standalone="no"?>' . "\n" . $self->dumper('', $xml_structure);
}

sub download_problem {
    my $self = shift;
    my $mech = $self->{mech};
    $self->download_statements;
    $self->set_download_links;
    $self->set_tests;
    $self->{downloading}{pattern} = 'tests/%0' . length(max(map($_->{rank}, @{$self->{downloading}{tests}}))) . 'd';
    $self->generate_xml;
    $self->{downloading}{writer} = -d $self->{path} ? \&write_dir : \&write_archive;
    $self->{downloading}{writer}->($self, $self->{path});
}

1;
