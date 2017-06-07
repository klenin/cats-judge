#!perl -w
use v5.10;
use strict;

use Carp;
use Cwd;
use File::Spec;
use constant FS => 'File::Spec';
use Fcntl qw(:flock);
use sigtrap qw(die INT);

use lib FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1], 'lib');
use lib FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1], 'lib', 'cats-problem');

use CATS::Config;
use CATS::Constants;
use CATS::SourceManager;
use CATS::FileUtil;
use CATS::Utils qw(split_fname);
use CATS::Judge::Config;
use CATS::Judge::CommandLine;
use CATS::Judge::Log;
use CATS::Judge::Local;
use CATS::Problem::Backend;
use CATS::Problem::PolygonBackend;

use CATS::Spawner::Default;
use CATS::Spawner::Program;
use CATS::Spawner::Const ':all';

use CATS::TestPlan;

use open IN => ':crlf', OUT => ':raw';

my $lh;
my $lock_file;

BEGIN {
    $lock_file = FS->catfile(cats_dir, 'judge.lock');
    open $lh, '>', $lock_file or die "Can not open $lock_file: $!";
    flock $lh, LOCK_EX | LOCK_NB or die "Can not lock $lock_file: $!\n";
}

END {
    flock $lh, LOCK_UN or die "Can not unlock $lock_file: $!\n";
    close $lh;
    unlink $lock_file or die $!;
}

my $cfg = CATS::Judge::Config->new;
my $log = CATS::Judge::Log->new;
my $cli = CATS::Judge::CommandLine->new;
my $fu = CATS::FileUtil->new({ logger => $log });

my $judge;
my $sp;
my %judge_de_idx;

my $problem_sources;

sub log_msg { $log->msg(@_); }

sub get_cmd {
    my ($action, $de_id) = @_;
    exists $judge_de_idx{$de_id} or die "undefined de_id: $de_id";
    $judge_de_idx{$de_id}->{$action};
}

sub get_cfg_define {
    my $name = shift;
    my $value = $cfg->defines->{$name};
    if (!$value) {
        log_msg("unknown define name: $name\n");
    }
    $value;
}

sub get_run_cmd {
    my ($de_id, $opts) = @_;
    my $run_cmd = get_cmd('run', $de_id) or return log_msg("No run cmd for DE: $de_id");
    return apply_params($run_cmd, $opts);
}

sub get_run_params {
    my ($problem, $ps, $limits, $run_cmd_opts) = @_;
    my $run_info = $problem->{run_info};

    my $get_names = sub {
        my ($p) = @_;
        $p->{fname} || $p->{full_name} && $p->{name}
            or return log_msg("No file names specified in get_run_params\n");
        my (undef, undef, $fname, $name, undef) =
            $p->{fname} ? split_fname($p->{fname}) : (undef, undef, $p->{full_name}, $p->{name}, undef);
        { full_name => $fname, name => $name }
    };

    my $names = $get_names->($ps) or return;

    my $global_opts = {
        ($run_info->{method} == $cats::rm_interactive ? ( %$limits, idle_time_limit => 1 ) : ()),
        stdout => '*null'
    };
    my $solution_opts = $run_info->{method} == $cats::rm_interactive ?
        {} :
        { %$limits, input_output_redir($problem->{input_file}, $problem->{output_file}) };
    my @programs;

    my $run_cmd = get_run_cmd($ps->{de_id}, { %$names, %$run_cmd_opts }) or return;
    push @programs, CATS::Spawner::Program->new(
        $run_cmd,
        [],
        $solution_opts
    );

    if ($run_info->{method} == $cats::rm_interactive) {
        $run_info->{interactor} or return log_msg('No interactor specified in get_run_params\n');
        $names = $get_names->($run_info->{interactor}) or return;
        $run_cmd = get_run_cmd($run_info->{interactor}->{de_id}, $names) or return;

        push @programs, CATS::Spawner::Program->new(
            $run_cmd,
            [],
            { stdin => '*0.stdout', stdout => '*0.stdin' }
        );
    }

    ($global_opts, @programs);
}

sub get_std_checker_cmd {
    my $std_checker_name = shift;

    if (!defined $cfg->checkers->{$std_checker_name}) {
        log_msg("unknown std checker: $std_checker_name\n");
        return undef;
    }

     $cfg->checkers->{$std_checker_name};
}

sub get_problem_source_path {
    my ($sid, $pid, @rest) = @_;

    [ $cfg->cachedir, $pid, 'temp', $sid, @rest ]
}

sub get_solution_path {
    my ($sid, @rest) = @_;

    [ $cfg->solutionsdir, $sid, @rest ]
}

sub get_test_file_path {
    my ($pid, $test, $ext) = @_;
    [ $cfg->cachedir, $pid, "$test->{rank}.$ext" ]
}

sub get_input_test_file_path {
    get_test_file_path(@_, 'tst')
}

sub get_answer_test_file_path {
    get_test_file_path(@_, 'ans')
}

sub my_safe_copy {
    my ($src, $dest, $pid) = @_;
    $fu->copy($src, $dest) and return 1;
    log_msg "Trying to reinitialize\n";
    # Either problem cache was damages or imported module has been changed.
    # Try reinilializing the problem. If that does not help, fail the run.
    initialize_problem($pid);
    $fu->copy($src, $dest);
    die 'REINIT';
}

sub clear_rundir { $fu->remove([ $cfg->rundir, '*' ]); }

sub apply_params {
    my ($str, $params) = @_;
    $str =~ s/%$_/$params->{$_}/g
        for sort { length $b <=> length $a } keys %$params;
    $str;
}

sub save_problem_description {
    my ($pid, $title, $date, $state) = @_;
    $fu->write_to_file([ $cfg->cachedir,  "$pid.des" ],
        join "\n", 'title:' . Encode::encode_utf8($title), "date:$date", "state:$state");
}

sub get_limits_hash {
    my ($ps) = @_;
    my %res;
    for (@cats::limits_fields) { $res{$_} = $ps->{$_} if defined $ps->{$_} };
    $res{memory_limit} += $ps->{memory_handicap} || 0 if $res{memory_limit};
    $res{write_limit} = $res{write_limit} . 'B' if $res{write_limit};
    %res;
}

sub get_special_limits_hash {
    my ($ps) = @_;
    my %res = get_limits_hash($ps);
    $res{deadline} = $ps->{time_limit};
    %res;
}

sub generate_test {
    my ($pid, $test, $input_fname) = @_;
    die 'generated' if $test->{generated};

    my ($ps) = grep $_->{id} eq $test->{generator_id}, @$problem_sources or die;

    clear_rundir or return undef;

    $fu->copy(get_problem_source_path($test->{generator_id}, $pid, '*'), $cfg->rundir)
        or return;

    my $generate_cmd = get_cmd('generate', $ps->{de_id})
        or do { print "No generate cmd for: $ps->{de_id}\n"; return undef; };
    my (undef, undef, $fname, $name, undef) = split_fname($ps->{fname});

    my $redir;
    my $out = $ps->{output_file} // $input_fname;
    if ($out =~ /^\*STD(IN|OUT)$/) {
        $test->{gen_group} and return undef;
        $out = 'stdout1.txt';
        $redir = $out;
    }
    my $sp_report = $sp->run_single({ ($redir ? (stdout => '*null') : ()) },
        apply_params($generate_cmd, { full_name => $fname, name => $name, args => $test->{param} // ''}),
        [],
        { get_special_limits_hash($ps), write_limit => 999, stdout => $redir }
    ) or return undef;

    $sp_report->ok ? $out : undef;
}

sub generate_test_group
{
    my ($pid, $test, $tests, $save_input_prefix) = @_;
    $test->{gen_group} or die 'gen_group';
    return 1 if $test->{generated};
    my $out = generate_test($pid, $test, 'in');
    unless ($out)
    {
        log_msg("failed to generate test group $test->{gen_group}\n");
        return undef;
    }
    $out =~ s/%n/%d/g;
    $out =~ s/%0n/%02d/g;
    #$out =~ s/%(0*)n/length($1) ? '%0' . length($1) . 'd' : '%d'/eg;
    for (@$tests)
    {
        next unless ($_->{gen_group} || 0) == $test->{gen_group};
        $_->{generated} = 1;
        $fu->copy_glob(
            [ $cfg->rundir, sprintf($out, $_->{rank}) ],
            [ $cfg->cachedir, $pid, "$_->{rank}.tst" ]) or return;

        $judge->save_input_test_data(
            $pid, $test->{rank},
            $fu->load_file(get_input_test_file_path($pid, $test), $save_input_prefix)
        ) if $save_input_prefix && !defined $test->{in_file};
    }
    1;
}

sub input_or { $_[0] eq '*STDIN' ? 'input.txt' : $_[1] }
sub output_or { $_[0] eq '*STDOUT' ? 'output.txt' : $_[1] }

sub input_or_default { FS->catfile($cfg->rundir, input_or($_[0], $_[0])) }
sub output_or_default { FS->catfile($cfg->rundir, output_or($_[0], $_[0])) }

sub input_output_redir {
    stdin => input_or($_[0], undef), stdout => output_or($_[1], undef),
}

sub get_interactor {
    my @interactors = grep $_->{stype} == $cats::interactor, @$problem_sources;

    if (!@interactors) {
        log_msg("Interactor is not defined, try search in solution modules (legacy)\n");
        # Suppose that interactor is the sole compilable solution module.
        @interactors = grep $_->{stype} == $cats::solution_module && get_cmd('compile', $_->{de_id}), @$problem_sources;
        $interactors[0]->{legacy} = 1 if @interactors;
    }

    @interactors == 0 ? log_msg("Unable to find interactor\n") :
        @interactors > 1 ? log_msg('Ambiguous interactors: ' . join(',', map $_->{fname}, @interactors) . "\n") :
            $interactors[0];
}

sub prepare_solution_environment {
    my ($pid, $solution_dir, $run_dir, $run_info, $safe) = @_;

    my $copy_func = $safe ? sub { my_safe_copy(@_, $pid) } : sub { $fu->copy(@_) };

    $copy_func->([ @$solution_dir, '*' ], $run_dir) or return;

    $run_info->{method} == $cats::rm_interactive or return 1;

    if ($run_info->{method} == $cats::rm_interactive) {
        my $interactor = $run_info->{interactor} or return;
        if (!$interactor->{legacy}) {
            $copy_func->(get_problem_source_path($interactor->{id}, $pid, '*'), $run_dir)
                or return;
        }
    }

    1;
}

sub get_run_info {
    my ($run_method) = @_;

    my %p = $run_method == $cats::rm_interactive ?
        ( interactor => get_interactor() ) : ();

    { method => $run_method, %p, }
}

sub validate_test {
    my ($pid, $test, $path_to_test) = @_;
    my $in_v_id = $test->{input_validator_id} or return 1;
    clear_rundir or return;
    my ($validator) = grep $_->{id} eq $in_v_id, @$problem_sources or die;
    $fu->copy($path_to_test, $cfg->rundir) or return;
    $fu->copy(get_problem_source_path($in_v_id, $pid, '*'), $cfg->rundir) or return;

    my $validate_cmd = get_cmd('validate', $validator->{de_id})
        or return log_msg("No validate cmd for: $validator->{de_id}\n");
    my ($vol, $dir, $fname, $name, $ext) = split_fname($validator->{fname});
    my ($t_vol, $t_dir, $t_fname, $t_name, $t_ext) = split_fname(FS->catfile(@$path_to_test));

    my $sp_report = $sp->run_single({},
        apply_params($validate_cmd, { full_name => $fname, name => $name, test_input => $t_fname }),
        [],
        { get_special_limits_hash($validator) }
    ) or return;

    $sp_report->ok;
}

sub prepare_tests {
    my ($pid, $problem) = @_;
    my $tests = $judge->get_problem_tests($pid);

    if (!@$tests) {
        log_msg("no tests defined\n");
        return undef;
    }

    $problem->{run_info} = get_run_info($problem->{run_method});

    for my $t (@$tests) {
        log_msg("[prepare $t->{rank}]\n");
        # Create test input file.
        if (defined $t->{in_file} && !defined $t->{in_file_size}) {
            $fu->write_to_file(get_input_test_file_path($pid, $t), $t->{in_file}) or return;
        }
        elsif (defined $t->{generator_id}) {
            if ($t->{gen_group}) {
                generate_test_group($pid, $t, $tests, $problem->{save_input_prefix})
                    or return undef;
            }
            else {
                my $out = generate_test($pid, $t, $problem->{input_file})
                    or return undef;
                $fu->copy([ $cfg->rundir, $out ], get_input_test_file_path($pid, $t))
                    or return;

                $judge->save_input_test_data(
                    $pid, $t->{rank},
                    $fu->load_file(get_input_test_file_path($pid, $t), $problem->{save_input_prefix})
                ) if $problem->{save_input_prefix} && !defined $t->{in_file};
            }
        }
        else {
            log_msg("no input defined for test #$t->{rank}\n");
            return undef;
        }

        validate_test($pid, $t, get_input_test_file_path($pid, $t)) or
            return log_msg("input validation failed: #$t->{rank}\n");

        # Create test output file.
        if (defined $t->{out_file} && !defined $t->{out_file_size}) {
            $fu->write_to_file(get_answer_test_file_path($pid, $t), $t->{out_file}) or return;
        }
        elsif (defined $t->{std_solution_id}) {
            my ($ps) = grep $_->{id} eq $t->{std_solution_id}, @$problem_sources;

            clear_rundir or return undef;

            prepare_solution_environment($pid,
                get_problem_source_path($t->{std_solution_id}, $pid), $cfg->rundir, $problem->{run_info}) or return;

            $fu->copy(get_input_test_file_path($pid, $t), input_or_default($problem->{input_file}))
                or return;

            my @run_params = get_run_params(
                $problem,
                $ps,
                { get_limits_hash({ map { $_ => $ps->{$_} || $problem->{$_} } @cats::limits_fields }), deadline => $ps->{time_limit} },
                {},
            ) or return;
            my $sp_report = $sp->run(@run_params) or return;

            return if grep !$_->ok, @{$sp_report->items};

            $fu->copy(output_or_default($problem->{output_file}), get_answer_test_file_path($pid, $t))
                or return;

            $judge->save_answer_test_data(
                $pid, $t->{rank},
                $fu->load_file(get_answer_test_file_path($pid, $t), $problem->{save_answer_prefix})
            ) if $problem->{save_answer_prefix} && !defined $t->{out_file};
        }
        else {
            log_msg("no output file defined for test #$t->{rank}\n");
            return undef;
        }
    }

    1;
}

sub prepare_modules {
    my ($stype) = @_;
    # Select modules in order they are listed in problem definition xml.
    for my $m (grep $_->{stype} == $stype, @$problem_sources) {
        my (undef, undef, $fname, $name, undef) = split_fname($m->{fname});
        log_msg("module: $fname\n");
        $fu->write_to_file([ $cfg->rundir, $fname ], $m->{src}) or return;

        # If compile_cmd is absent, module does not need compilation (de_code=1).
        my $compile_cmd = get_cmd('compile', $m->{de_id})
            or next;
        $sp->run_single({}, apply_params($compile_cmd, { full_name => $fname, name => $name }))
            or return undef;
    }
    1;
}

sub initialize_problem {
    my $pid = shift;

    my $p = $judge->get_problem($pid);

    save_problem_description($pid, $p->{title}, $p->{upload_date}, 'not ready')
        or return undef;

    # Compile all source files in package (solutions, generators, checkers etc).
    $fu->mkdir_clean([ $cfg->cachedir, $pid ]) or return;
    $fu->mkdir_clean([ $cfg->cachedir, $pid, 'temp' ]) or return;

    my %main_source_types;
    $main_source_types{$_} = 1 for keys %cats::source_modules;

    for my $ps (grep $main_source_types{$_->{stype}}, @$problem_sources) {
        clear_rundir or return undef;

        prepare_modules($cats::source_modules{$ps->{stype}} || 0)
            or return undef;

        my ($vol, $dir, $fname, $name, $ext) = split_fname($ps->{fname});
        $fu->write_to_file([ $cfg->rundir, $fname ], $ps->{src}) or return;

        if (my $compile_cmd = get_cmd('compile', $ps->{de_id})) {
            my $sp_report = $sp->run_single({}, apply_params($compile_cmd, { full_name => $fname, name => $name }))
                or return undef;
            if (!$sp_report->ok) {
                log_msg("*** compilation error ***\n");
                return undef;
            }
        }

        if ($ps->{stype} == $cats::generator && $p->{formal_input}) {
           $fu->write_to_file([ $cfg->rundir, $cfg->formal_input_fname ], $p->{formal_input}) or return;
        }

        my $tmp = get_problem_source_path($ps->{id}, $pid);
        $fu->mkdir_clean($tmp) or return;
        $fu->copy([ $cfg->rundir, '*' ], $tmp) or return;

        for my $guided_source (@$problem_sources) {
            next if !$guided_source->{guid} || $guided_source->{is_imported};
            my $path = CATS::FileUtil::fn [ @$tmp, $guided_source->{fname} ];
            if (-e $path) {
                CATS::SourceManager::save($guided_source, $cfg->modulesdir, FS->rel2abs($path));
                log_msg("save source $guided_source->{guid}\n");
            }
        }
    }
    prepare_tests($pid, $p)
        or return undef;

    save_problem_description($pid, $p->{title}, $p->{upload_date}, 'ready')
        or return undef;

    1;
}

my %inserted_details;
my %test_run_details;

sub insert_test_run_details {
    my %p = (%test_run_details, @_);
    for ($inserted_details{ $p{test_rank} })
    {
        return if $_;
        $_ = $p{result};
    }
    $judge->insert_req_details(\%p);
}

sub run_checker {
    my %p = @_;

    my $problem = $p{problem};

    my $i = input_or_default($problem->{input_file});
    my $o = output_or_default($problem->{output_file});
    my $a = "$p{rank}.ans";

    my $checker_params = {
        test_input => $i,
        test_output => $o,
        test_answer => $a,
        checker_args => qq~"$a" "$o" "$i"~,
    };

    my $checker_cmd;
    my %limits;
    if (defined $problem->{std_checker})
    {
        $checker_cmd = get_std_checker_cmd($problem->{std_checker})
            or return undef;
    }
    else
    {
        my ($ps) = grep $_->{id} eq $problem->{checker_id}, @$problem_sources;

        my_safe_copy(
            get_problem_source_path($problem->{checker_id}, $problem->{id}, '*'),
            $cfg->rundir, $problem->{id}) or return;

        (undef, undef, undef, $checker_params->{name}, undef) =
            split_fname($checker_params->{full_name} = $ps->{fname});
        $cats::source_modules{$ps->{stype}} || 0 == $cats::checker_module
            or die "Bad checker type $ps->{stype}";
        $checker_params->{checker_args} =
            $ps->{stype} == $cats::checker ? qq~"$a" "$o" "$i"~ : qq~"$i" "$o" "$a"~;

        %limits = get_special_limits_hash($ps);

        $checker_cmd = get_cmd('check', $ps->{de_id})
            or return log_msg("No 'check' action for DE: $ps->{code}\n");
    }

    my $sp_report;
    for my $c (\$test_run_details{checker_comment})
    {
        $$c = undef;
        $sp_report = $sp->run_single({ duplicate_output => $c },
            apply_params($checker_cmd, $checker_params),
            [],
            { %limits }
        ) or return undef;
        #Encode::from_to($$c, 'cp866', 'utf8');
        # Cut to make sure comment fits in database field.
        $$c = substr($$c, 0, 199) if defined $$c;
    }

    # checked only once?
    @{$sp_report->{errors}} == 0 && $sp_report->{terminate_reason} == $TR_OK or return undef;

    $sp_report;
}

sub filter_hash {
    my $hash = shift;
    map { $_ => $hash->{$_} } @_;
}

sub run_single_test {
    my %p = @_;
    my $problem = $p{problem};

    log_msg("[test $p{rank}]\n");
    $test_run_details{test_rank} = $p{rank};
    $test_run_details{checker_comment} = '';

    clear_rundir or return undef;

    my $pid = $problem->{id};

    prepare_solution_environment($pid,
        get_solution_path($p{sid}), $cfg->rundir, $problem->{run_info}, 1) or return;

    my_safe_copy(
        [ $cfg->cachedir, $problem->{id}, "$p{rank}.tst" ],
        input_or_default($problem->{input_file}), $pid) or return;

    {
        my %limits = get_limits_hash({ %p, %$problem });
        my @run_params = get_run_params(
            $problem,
            { filter_hash($problem, qw/name full_name/), de_id => $p{de_id} },
            { %limits },
            { output_file => $problem->{output_file}, test_rank => sprintf('%02d', $p{rank}) }
        ) or return;

        my $sp_report = $sp->run(@run_params) or return;

        my $solution_report = $sp_report->items->[0];

        return if @{$solution_report->{errors}};

        $test_run_details{time_used} = $solution_report->{consumed}->{user_time};
        $test_run_details{memory_used} = $solution_report->{consumed}->{memory};
        $test_run_details{disk_used} = $solution_report->{consumed}->{write};

        if ($solution_report->{terminate_reason} == $TR_OK) {
            if ($solution_report->{exit_code} != 0) {
                $test_run_details{checker_comment} = $solution_report->{exit_code};
                return $cats::st_runtime_error;
            }
        } else {
            return {
                $TR_ABORT          => $cats::st_runtime_error,
                $TR_TIME_LIMIT     => $cats::st_time_limit_exceeded,
                $TR_MEMORY_LIMIT   => $cats::st_memory_limit_exceeded,
                $TR_WRITE_LIMIT    => $cats::st_write_limit_exceeded,
                $TR_IDLENESS_LIMIT => $cats::st_idleness_limit_exceeded
            }->{$solution_report->{terminate_reason}} //
                log_msg("unknown terminate reason: $solution_report->{terminate_reason}\n");
        }

        if ($problem->{run_info} == $cats::rm_interactive) {
            my $interactor_report = $sp_report->items->[1];
            if (!$interactor_report->ok) {
                return $cats::st_unhandled_error;
            }
        }
    }
    ($test_run_details{output}, $test_run_details{output_size}) =
        $fu->load_file([ $cfg->rundir, $problem->{output_file} ], $problem->{save_output_prefix})
            if $problem->{save_output_prefix};

    my_safe_copy(
        [ $cfg->cachedir, $problem->{id}, "$p{rank}.tst" ],
        input_or_default($problem->{input_file}), $problem->{id}) or return;
    my_safe_copy(
        [ $cfg->cachedir, $problem->{id}, "$p{rank}.ans" ],
        [ $cfg->rundir, "$p{rank}.ans" ], $problem->{id}) or return;
    {
        my $sp_report = run_checker(problem => $problem, rank => $p{rank})
            or return undef;

        my $result = {
            0 => $cats::st_accepted,
            1 => $cats::st_wrong_answer,
            2 => $cats::st_presentation_error
        }->{$sp_report->{exit_code}}
            // return log_msg("checker error (exit code '$sp_report->{exit_code}')\n");
        log_msg("OK\n") if $result == $cats::st_accepted;
        $result;
    }
}

sub compile {
    my ($r, $problem) = @_;
    clear_rundir or return (0, undef);

    prepare_modules($cats::solution_module) or return (0, undef);
    $fu->write_to_file([ $cfg->rundir, $problem->{full_name} ], $r->{src}) or return (0, undef);

    my $compile_cmd = get_cmd('compile', $r->{de_id});
    defined $compile_cmd or return (0, undef);

    if ($compile_cmd ne '') {
        my $sp_report = $sp->run_single({ section => $cats::log_section_compile },
            apply_params($compile_cmd, { filter_hash($problem, qw/full_name name/) })
        ) or return (0, undef);
        my $ok = $sp_report->ok;
        if ($ok) {
            my $runfile = get_cmd('runfile', $r->{de_id});
            $runfile = apply_params($runfile, $problem) if $runfile;
            if ($runfile && !(-f $cfg->rundir . "/$runfile")) {
                $ok = 0;
                log_msg("Runfile '$runfile' not created\n");
            }
        }
        if (!$ok) {
            insert_test_run_details(result => $cats::st_compilation_error);
            log_msg("compilation error\n");
            return (0, $cats::st_compilation_error);
        }
    }

    if ($r->{status} == $cats::problem_st_compile) {
        log_msg("accept compiled solution\n");
        return (0, $cats::st_accepted);
    }

    $fu->mkdir_clean([ $cfg->solutionsdir, $r->{id} ]) or return (0, undef);
    $fu->copy([ $cfg->rundir, '*' ], [ $cfg->solutionsdir, $r->{id} ]) or return (0, undef);
    (1, undef);
}

sub test_solution {
    my ($r) = @_;
    my ($sid, $de_id) = ($r->{id}, $r->{de_id});

    log_msg("Testing solution: $sid for problem: $r->{problem_id}\n");
    my $problem = $judge->get_problem($r->{problem_id});

    $problem->{run_info} = get_run_info($problem->{run_method});

    if ($r->{elements} && @{$r->{elements}} > 1) {
        log_msg("Group requests are not supported at this time.\n Pass solution...\n");
        return $cats::st_accepted;
    }

    # Override limits
    for my $l (@cats::limits_fields) {
        $problem->{$l} = $r->{"req_$l"} || $r->{"cp_$l"} || $problem->{$l};
    }

    my $memory_handicap = $judge_de_idx{$de_id}->{memory_handicap};

    ($problem->{checker_id}) = map $_->{id}, grep
        { ($cats::source_modules{$_->{stype}} || -1) == $cats::checker_module }
        @$problem_sources;

    if (!defined $problem->{checker_id} && !defined $problem->{std_checker}) {
        log_msg("no checker defined!\n");
        return undef;
    }

    $judge->delete_req_details($sid);
    %test_run_details = (req_id => $sid, test_rank => 1);
    %inserted_details = ();

    (undef, undef, $problem->{full_name}, $problem->{name}, undef) = split_fname($r->{fname});

    my $res = undef;
    my $failed_test = undef;

    for (0..1) {
        my $er = eval {
            my ($ret, $st) = compile($r, $problem);
            return $st unless $ret;

            my %tests = $judge->get_testset($sid, 1) or do {
                log_msg("no tests found\n");
                return $cats::st_ignore_submit;
            };
            my %tp_params = (tests => \%tests);
            my $tp = $r->{run_all_tests} ?
                CATS::TestPlan::ScoringGroups->new(%tp_params) :
                CATS::TestPlan::ACM->new(%tp_params);
            for ($tp->start; $tp->current; ) {
                $res = run_single_test(
                    problem => $problem, sid => $sid, rank => $tp->current,
                    de_id => $de_id, memory_handicap => $memory_handicap
                ) or return undef;
                insert_test_run_details(result => $res);
                $inserted_details{$tp->current} = $res;
                $tp->set_test_result($res == $cats::st_accepted ? 1 : 0);
                $failed_test = $tp->first_failed;
            }
            'FALL';
        };
        my $e = $@;
        if ($e) {
            die $e unless $e =~ /^REINIT/;
        }
        else {
            return $er unless ($er || '') eq 'FALL';
            last;
        }
    }
    if ($failed_test) {
        $res = $inserted_details{$failed_test};
    }
    $r->{failed_test} = $failed_test;
    return $res;
}

sub problem_ready {
    my ($pid) = @_;

    open my $pdesc, '<', CATS::FileUtil::fn([ $cfg->cachedir, "$pid.des" ]) or return 0;

    my $title = <$pdesc>;
    my $date = <$pdesc>;
    my $state = <$pdesc>;

    $state eq 'state:ready' or return 0;

    # Emulate old CATS_TO_EXACT_DATE format.
    $date =~ m/^date:(\d+)-(\d+)-(\d+)\s(.+)$/ or return 0;
    $date = "$3-$2-$1 $4";
    $judge->is_problem_uptodate($pid, $date);
}

sub clear_problem_cache {
    my ($problem_id) = @_;
    $problem_id or return;
    for (CATS::SourceManager::get_guids_by_regexp('*', $cfg->{modulesdir})) {
        my $m = eval { CATS::SourceManager::load($_, $cfg->{modulesdir}); } or next;
        $log->warning("Orphaned module: $_")
            if $m->{path} =~ m~[\/\\]\Q$problem_id\E[\/\\]~;
    }
    $log->clear_dump;
    $fu->remove([ $cfg->cachedir, "$problem_id*" ]) or return; # Both file and directory.
    log_msg("problem '$problem_id' cache removed\n");
}

sub prepare_problem {
    my $r = $judge->select_request or return;

    $log->clear_dump;

    if (!defined $r->{status}) {
        log_msg("security: problem $r->{problem_id} is not included in contest $r->{contest_id}\n");
        $judge->set_request_state($r, $cats::st_unhandled_error);
        return;
    }

    $problem_sources = $judge->get_problem_sources($r->{problem_id});
    # Ignore unsupported DEs for requests, but demand every problem to be installable on every judge.
    my %unsupported_DEs =
        map { $_->{code} => 1 } grep !exists $judge_de_idx{$_->{de_id}}, @$problem_sources;
    if (%unsupported_DEs) {
        log_msg("unsupported DEs for problem %s: %s\n",
            $r->{problem_id}, join ', ', sort keys %unsupported_DEs);
        $judge->set_request_state($r, $cats::st_unhandled_error, %$r);
        return;
    }

    my $state = $cats::st_testing;
    my $is_ready = problem_ready($r->{problem_id});
    if (!$is_ready || $cli->opts->{'force-install'}) {
        log_msg("installing problem $r->{problem_id}%s\n", $is_ready ? ' - forced' : '');
        eval {
            initialize_problem($r->{problem_id});
        } or do {
            $state = $cats::st_unhandled_error;
            log_msg("error: $@\n") if $@;
        };
        log_msg("problem '$r->{problem_id}' installed\n") if $state != $cats::st_unhandled_error;
    }
    else {
        log_msg("problem $r->{problem_id} cached\n");
    }
    $judge->save_log_dump($r, $log->{dump});
    $judge->set_request_state($r, $state, %$r);
    ($r, $state);
}

sub interactive_login {
    eval { require Term::ReadKey; 1; } or $log->error('Term::ReadKey is required for interactive login');
    print 'login: ';
    chomp(my $login = <>);
    print "password: ";
    Term::ReadKey::ReadMode('noecho');
    chomp(my $password = <>);
    print "\n";
    Term::ReadKey::ReadMode('restore');
    ($login, $password);
}

sub get_system {
    if ($judge->{system}) {
        $judge->{system} =~ m/^(cats|polygon)$/ or $log->error('bad option --system');
        return $judge->{system};
    }
    for (qw(cats polygon)) {
        my $u = $cfg->{$_ . '_url'};
        return $_ if $judge->{url} =~ /^\Q$u\E/;
    }
    die 'Unable to determine system from --system and --url options';
}

sub sync_problem {
    my ($action) = @_;
    my $system = get_system;
    my $problem_exist = -d $judge->{problem} || -f $judge->{problem};
    $problem_exist and $judge->select_request;
    my $root = $system eq 'cats' ? $cfg->cats_url : $cfg->polygon_url;
    my $backend = ($system eq 'cats' ? 'CATS::Problem::Backend' : 'CATS::Problem::PolygonBackend')->new(
        $judge->{parser}{problem}, $judge->{logger}, $judge->{problem}, $judge->{url},
        $problem_exist, $root, $cfg->{proxy}, $judge->{verbose});
    $backend->login(interactive_login) if $backend->needs_login;
    $backend->start;
    $log->msg('%s problem %s ... ', ($action eq 'upload' ? 'Uploading' : 'Downloading'), ($judge->{problem} || 'by url'));
    $action eq 'upload' ? $backend->upload_problem : $backend->download_problem;
    $problem_exist or $judge->{problem} .= '.zip';
    $log->note('ok');
}

sub test_problem {
    my ($r) = @_;
    my $state;

    log_msg("test log:\n");
    if ($r->{fname} =~ /[^_a-zA-Z0-9\.\\\:\$]/) {
        log_msg("renamed from '$r->{fname}'\n");
        $r->{fname} =~ tr/_a-zA-Z0-9\.\\:$/x/c;
    }

    eval {
        $state = test_solution($r); 1;
    } or do {
        $state = undef;
        log_msg("error: $@\n");
    };

    defined $state
        or insert_test_run_details(result => ($state = $cats::st_unhandled_error));

    $judge->save_log_dump($r, $log->{dump});
    if ($r->{status} == $cats::problem_st_manual && $state == $cats::st_accepted) {
        $state = $cats::st_awaiting_verification;
    }
    $judge->set_request_state($r, $state, %$r);

    my $state_text = { map {; /^st_(.+)$/ ? (eval('$cats::' . $_) => $1) : (); } keys %cats:: }->{$state};
    $state_text =~ s/_/ /g;
    $state_text .= " on test $r->{failed_test}" if $r->{failed_test};
    log_msg("==> $state_text\n");
}

sub main_loop {
    chdir $cfg->workdir
        or return log_msg("change to workdir '%s' failed: $!\n", $cfg->workdir);

    log_msg("judge: %s, using api: %s\n", $judge->name, $cfg->api);
    log_msg("supported DEs: %s\n", join ',', sort { $a <=> $b } keys %{$cfg->DEs});

    for (my $i = 0; ; $i++) {
        sleep $cfg->sleep_time;
        $log->rollover;
        syswrite STDOUT, "\b" . (qw(/ - \ |))[$i % 4];
        my ($r, $state) = prepare_problem();
        log_msg("pong\n") if $judge->was_pinged;
        $r && $state != $cats::st_unhandled_error or next;
        if (($r->{src} // '') eq '' && @{$r->{elements}} <= 1) {
            log_msg("Empty source for problem $r->{problem_id}\n");
            $judge->set_request_state($r, $cats::st_unhandled_error);
        }
        else {
            test_problem($r);
        }
    }
}

$cli->parse;

{
    my $judge_cfg = FS->catdir(cats_dir(), 'config.xml');
    open my $cfg_file, '<', $judge_cfg or die "Couldn't open $judge_cfg";
    $cfg->read_file($cfg_file, $cli->opts->{'config-set'});

    my $cfg_confess = $cfg->confess // '';
    $SIG{__WARN__} = \&confess if $cfg_confess =~ /w/i;
    $SIG{__DIE__} = \&confess if $cfg_confess =~ /d/i;
}

if ($cli->command eq 'config') {
    $cfg->print_params($cli->opts->{'print'});
    exit;
}

$fu->ensure_dir($cfg->cachedir, 'cachedir');
$fu->ensure_dir($cfg->solutionsdir, 'solutions');
$fu->ensure_dir($cfg->logdir, 'logdir');
$fu->ensure_dir($cfg->rundir, 'rundir');

$log->init($cfg->logdir);

my $api = $cfg->api;

if ($cli->command eq 'serve' && $api eq 'DirectDatabase' || defined $cli->opts->{db}) {
    require CATS::DB;
    CATS::DB::sql_connect({
        ib_timestampformat => $CATS::Judge::Base::timestamp_format,
        ib_dateformat => '%d-%m-%Y',
        ib_timeformat => '%H:%M',
    });
}

if ($cli->command ne 'serve') {
    $judge = CATS::Judge::Local->new(
        name => $cfg->name, modulesdir => $cfg->modulesdir,
        resultsdir => $cfg->resultsdir, columns => $cfg->columns, logger => $log, %{$cli->opts});
}
elsif ($api =~ /^(WebApi|DirectDatabase)$/) {
    eval { require "CATS/Judge/$api.pm"; 1; } or die "Can't load $api module: $@";
    no strict 'refs';
    $judge = "CATS::Judge::$api"->new_from_cfg($cfg);
}
else {
    die "Unknown api '$api'\n";
}

$judge->auth;
$judge->set_DEs($cfg->DEs);
$judge_de_idx{$_->{id}} = $_ for values %{$cfg->DEs};

{
    my $cfg_dirs = {};
    $cfg_dirs->{$_} = $cfg->{$_} for $cfg->dir_fields;
    $sp = CATS::Spawner::Default->new({
        %$cfg,
        logger => $log,
        path => apply_params(get_cfg_define('#spawner'), $cfg_dirs),
        run_dir => $cfg->rundir,
        json => 1,
    });
}

if ($cli->command =~ /^(download|upload)$/) {
    sync_problem($cli->command);
}
elsif ($cli->command =~ /^(clear-cache)$/) {
    my $pd = CATS::FileUtil::fn([ $cfg->{cachedir}, $judge->{problem} ]);
    clear_problem_cache(
        -f "$pd.des" || -d $pd ? $judge->{problem} : $judge->select_request->{problem_id});
}
elsif ($cli->command =~ /^(install|run)$/) {
    for my $rr (@{$cli->opts->{run} || [ '' ]}) {
        my $wd = Cwd::cwd();
        $judge->{run} = $rr;
        $judge->set_def_DEs($cfg->def_DEs);
        my ($r, $state) = prepare_problem();
        test_problem($r) if $r && ($r->{src} // '') ne '' && $state != $cats::st_unhandled_error;
        $judge->{rid_to_fname}->{$r->{id}} = $rr;
        chdir($wd);
    }
}
elsif ($cli->command eq 'serve') {
    main_loop;
}
else {
    die $cli->command;
}

$judge->finalize;

1;
