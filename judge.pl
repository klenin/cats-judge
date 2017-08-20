#!perl -w
use v5.10;
use strict;

use Carp;
use Cwd;
use File::Spec;
use constant FS => 'File::Spec';
use Fcntl qw(:flock);
use List::Util qw(max);
use sigtrap qw(die INT);

use lib FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1], 'lib');
use lib FS->catdir((FS->splitpath(FS->rel2abs($0)))[0,1], 'lib', 'cats-problem');

use CATS::Config;
use CATS::Constants;
use CATS::SourceManager;
use CATS::FileUtil;
use CATS::Utils qw(split_fname);

use CATS::Backend;
use CATS::Judge::Config;
use CATS::Judge::CommandLine;
use CATS::Judge::Log;
use CATS::Judge::Local;
use CATS::Judge::ProblemCache;

use CATS::Spawner::Default;
use CATS::Spawner::Program;
use CATS::Spawner::Const ':all';

use CATS::TestPlan;

use open IN => ':crlf', OUT => ':raw';

my $lh;
my $lock_file;

INIT {
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
my $problem_cache;
my $sp;
my %judge_de_idx;

my $problem_sources;

sub log_msg { $log->msg(@_); }

sub get_cmd {
    my ($action, $de_id) = @_;
    exists $judge_de_idx{$de_id} or die "undefined de_id: $de_id";
    $judge_de_idx{$de_id}->{$action};
}

sub get_run_cmd {
    my ($de_id, $opts) = @_;
    my $run_cmd = get_cmd('run', $de_id) or return log_msg("No run cmd for DE: $de_id");
    return apply_params($run_cmd, $opts);
}

sub set_name_parts {
    my ($r) = @_;
    (undef, undef, $_->{full_name}, $_->{name}, undef) = split_fname($r->{fname})
        for $r->{name_parts};
}

sub get_run_params {
    my ($problem, $rs, $run_cmd_opts) = @_;
    my $run_info = $problem->{run_info};

    my $is_interactive = $run_info->{method} == $cats::rm_interactive;
    my $is_competititve = $run_info->{method} == $cats::rm_competitive;

    die if !$is_competititve && @$rs != 1;

    my @programs;

    my $time_limit_sum = 0;
    for my $r (@$rs) {
        my %limits = get_limits_hash($r, $problem);
        $time_limit_sum += $limits{time_limit};

        my $solution_opts;
        if ($is_interactive || $is_competititve) {
            delete $limits{deadline};
            $solution_opts = { %limits, stdin => '*0.stdout', stdout => '*0.stdin' };
        } else {
            $solution_opts = {
                %limits, input_output_redir($problem->{input_file}, $problem->{output_file}) };
        }
        my $names = $r->{name_parts} or return log_msg("No name parts\n");
        my $run_cmd = get_run_cmd($r->{de_id}, {
            %$names, %$run_cmd_opts, output_file => output_or_default($problem->{output_file}),
        }) or return;
        push @programs, CATS::Spawner::Program->new($run_cmd, [], $solution_opts);
    }

    my $deadline = $is_competititve ? max($time_limit_sum + 2, 30) : $time_limit_sum + 2;

    my $global_opts = {
        deadline => $deadline,
        idle_time_limit => 1,
        stdout => '*null',
    };

    if ($is_interactive || $is_competititve) {
        my $i = $run_info->{interactor}
            or return log_msg("No interactor specified in get_run_params\n");
        my %limits = get_limits_hash($run_info->{interactor}, $problem);
        delete $limits{deadline};
        $global_opts->{idle_time_limit} = $limits{time_limit} + 1 if $limits{time_limit};

        my $run_cmd = get_run_cmd($i->{de_id}, $i->{name_parts}) or return;

        unshift @programs, CATS::Spawner::Program->new($run_cmd,
            $is_competititve ? [ scalar @programs ] : [],
            { controller => $is_competititve, idle_time_limit => $deadline - 1, %limits }
        );
    }

    ($global_opts, @programs);
}

sub my_safe_copy {
    my ($src, $dest, $pid) = @_;
    $fu->copy($src, $dest) and return 1;
    log_msg "Trying to reinitialize\n";
    # Either problem cache was damaged or imported module has been changed.
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

sub get_limits_hash {
    my ($ps, $problem) = @_;
    $problem //= {};
    my %res = map { $_ => $ps->{"req_$_"} || $ps->{"cp_$_"} || $ps->{$_} || $problem->{$_} } @cats::limits_fields;
    $res{deadline} = $res{time_limit}
        if $res{time_limit} && (!defined $ENV{SP_DEADLINE} || $res{time_limit} > $ENV{SP_DEADLINE});
    my $memory_handicap = $judge_de_idx{$ps->{de_id}}->{memory_handicap} if $ps->{de_id};
    $res{memory_limit} += $memory_handicap // 0 if $res{memory_limit};
    $res{write_limit} = $res{write_limit} . 'B' if $res{write_limit};
    %res;
}

sub generate_test {
    my ($problem, $test, $input_fname) = @_;
    my $pid = $problem->{id};
    die 'generated' if $test->{generated};

    my ($ps) = grep $_->{id} eq $test->{generator_id}, @$problem_sources or die;

    clear_rundir or return undef;

    $fu->copy($problem_cache->source_path($pid, $test->{generator_id}, '*'), $cfg->rundir)
        or return;

    my $generate_cmd = get_cmd('generate', $ps->{de_id})
        or do { print "No generate cmd for: $ps->{de_id}\n"; return undef; };

    my $redir;
    my $out = $ps->{output_file} // $input_fname;
    if ($out =~ /^\*STD(IN|OUT)$/) {
        $test->{gen_group} and return undef;
        $out = 'stdout1.txt';
        $redir = $out;
    }
    my $applied_cmd = apply_params(
        $generate_cmd, { %{$ps->{name_parts}}, args => $test->{param} // ''});
    my $sp_report = $sp->run_single({ ($redir ? (stdout => '*null') : ()) },
        $applied_cmd,
        [],
        { get_limits_hash($ps, $problem), stdout => $redir }
    ) or return undef;

    $sp_report->ok ? $out : undef;
}

sub generate_test_group {
    my ($problem, $test, $tests) = @_;
    my $pid = $problem->{id};
    $test->{gen_group} or die 'gen_group';
    return 1 if $test->{generated};
    my $out = generate_test($problem, $test, 'in')
        or return log_msg("failed to generate test group $test->{gen_group}\n");
    $out =~ s/%n/%d/g;
    $out =~ s/%0n/%02d/g;
    #$out =~ s/%(0*)n/length($1) ? '%0' . length($1) . 'd' : '%d'/eg;
    for (@$tests) {
        next unless ($_->{gen_group} || 0) == $test->{gen_group};
        $_->{generated} = 1;
        my $tf = $problem_cache->test_file($pid, $_);
        $fu->copy_glob([ $cfg->rundir, sprintf($out, $_->{rank}) ], $tf) or return;
        if ($problem->{save_input_prefix} && !defined $test->{in_file}) {
            my @input_data = $fu->load_file($tf, $problem->{save_input_prefix}) or return;
            $judge->save_input_test_data($pid, $_->{rank}, @input_data);
        }
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

    if ($run_info->{method} == $cats::rm_interactive || $run_info->{method} == $cats::rm_competitive) {
        my $interactor = $run_info->{interactor} or return;
        if (!$interactor->{legacy}) {
            $copy_func->($problem_cache->source_path($pid, $interactor->{id}, '*'), $run_dir)
                or return;
        }
    }

    1;
}

sub get_run_info {
    my ($run_method) = @_;

    my %p = $run_method == $cats::rm_interactive || $run_method == $cats::rm_competitive ?
        ( interactor => get_interactor() ) : ();

    { method => $run_method, %p, }
}

sub validate_test {
    my ($problem, $test, $path_to_test) = @_;
    my $pid = $problem->{id};
    my $in_v_id = $test->{input_validator_id} or return 1;
    clear_rundir or return;
    my ($validator) = grep $_->{id} eq $in_v_id, @$problem_sources or die;
    $fu->copy($path_to_test, $cfg->rundir) or return;
    $fu->copy($problem_cache->source_path($pid, $in_v_id, '*'), $cfg->rundir) or return;

    my $validate_cmd = get_cmd('validate', $validator->{de_id})
        or return log_msg("No validate cmd for: $validator->{de_id}\n");
    my (undef, undef, $t_fname, $t_name, undef) = split_fname(FS->catfile(@$path_to_test));

    my $sp_report = $sp->run_single({},
        apply_params($validate_cmd, { %{$validator->{name_parts}}, test_input => $t_fname }),
        [],
        { get_limits_hash($validator, $problem) }
    ) or return;

    $sp_report->ok;
}

sub prepare_tests {
    my ($problem) = @_;
    my $pid = $problem->{id};
    my $tests = $judge->get_problem_tests($pid);

    if (!@$tests) {
        log_msg("no tests defined\n");
        return undef;
    }

    $problem->{run_info} = get_run_info($problem->{run_method});

    for my $t (@$tests) {
        log_msg("[prepare $t->{rank}]\n");
        # Create test input file.
        my $tf = $problem_cache->test_file($pid, $t);
        if (defined $t->{in_file} && !defined $t->{in_file_size}) {
            $fu->write_to_file($tf, $t->{in_file}) or return;
        }
        elsif (defined $t->{generator_id}) {
            if ($t->{gen_group}) {
                generate_test_group($problem, $t, $tests) or return undef;
            }
            else {
                my $out = generate_test($problem, $t, $problem->{input_file})
                    or return undef;
                $fu->copy([ $cfg->rundir, $out ], $tf) or return;

                if ($problem->{save_input_prefix} && !defined $t->{in_file}) {
                    my @input_data = $fu->load_file($tf, $problem->{save_input_prefix}) or return;
                    $judge->save_input_test_data($pid, $t->{rank}, @input_data);
                }
            }
        }
        else {
            log_msg("no input defined for test #$t->{rank}\n");
            return undef;
        }

        validate_test($problem, $t, $tf) or
            return log_msg("input validation failed: #$t->{rank}\n");

        # Create test output file.
        my $af = $problem_cache->answer_file($pid, $t);
        if (defined $t->{out_file} && !defined $t->{out_file_size}) {
            $fu->write_to_file($af, $t->{out_file}) or return;
        }
        elsif (defined $t->{std_solution_id}) {
            if ($problem->{run_method} == $cats::rm_competitive) {
                return log_msg("run solution in competitive problem not implemented");
            }

            my ($ps) = grep $_->{id} eq $t->{std_solution_id}, @$problem_sources;

            clear_rundir or return undef;

            prepare_solution_environment(
                $pid, $problem_cache->source_path($pid, $t->{std_solution_id}),
                $cfg->rundir, $problem->{run_info}) or return;

            $fu->copy($tf, input_or_default($problem->{input_file})) or return;

            my @run_params = get_run_params($problem, [ $ps ], {}) or return;
            my $sp_report = $sp->run(@run_params) or return;

            return if grep !$_->ok, @{$sp_report->items};

            $fu->copy(output_or_default($problem->{output_file}), $af)
                or return;

            $judge->save_answer_test_data(
                $pid, $t->{rank}, $fu->load_file($af, $problem->{save_answer_prefix})
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
        my $fname = $m->{name_parts}->{full_name};
        log_msg("module: $fname\n");
        $fu->write_to_file([ $cfg->rundir, $fname ], $m->{src}) or return;

        # If compile_cmd is absent, module does not need compilation (de_code=1).
        my $compile_cmd = get_cmd('compile', $m->{de_id})
            or next;
        $sp->run_single({}, apply_params($compile_cmd, $m->{name_parts}))
            or return undef;
    }
    1;
}

sub initialize_problem {
    my $pid = shift;

    my $p = $judge->get_problem($pid);

    $problem_cache->save_description($pid, $p->{title}, $p->{upload_date}, 'not ready')
        or return undef;

    # Compile all source files in package (solutions, generators, checkers etc).

    $problem_cache->clear_dir($pid) or return;

    my %main_source_types;
    $main_source_types{$_} = 1 for keys %cats::source_modules;

    for my $ps (grep $main_source_types{$_->{stype}}, @$problem_sources) {
        clear_rundir or return undef;

        prepare_modules($cats::source_modules{$ps->{stype}} || 0)
            or return undef;

        $fu->write_to_file([ $cfg->rundir, $ps->{name_parts}->{full_name} ], $ps->{src}) or return;

        if (my $compile_cmd = get_cmd('compile', $ps->{de_id})) {
            my $sp_report = $sp->run_single({}, apply_params($compile_cmd, $ps->{name_parts}))
                or return undef;
            if (!$sp_report->ok) {
                log_msg("*** compilation error ***\n");
                return undef;
            }
        }

        if ($ps->{stype} == $cats::generator && $p->{formal_input}) {
           $fu->write_to_file([ $cfg->rundir, $cfg->formal_input_fname ], $p->{formal_input}) or return;
        }

        my $tmp = $problem_cache->source_path($pid, $ps->{id});
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
    prepare_tests($p) or return undef;

    $problem_cache->save_description($pid, $p->{title}, $p->{upload_date}, 'ready')
        or return undef;

    1;
}

my %inserted_details;

sub insert_test_run_details {
    my %p = @_;
    for ($inserted_details{$p{req_id}}->{$p{test_rank}}) {
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
    if (defined $problem->{std_checker}) {
        $checker_cmd = $cfg->checkers->{$problem->{std_checker}}
            or return log_msg("unknown std checker: $problem->{std_checker}\n");
        %limits = get_limits_hash({}, $problem);
    }
    else {
        my ($ps) = grep $_->{id} eq $problem->{checker_id}, @$problem_sources;

        my_safe_copy(
            $problem_cache->source_path($problem->{id}, $problem->{checker_id}, '*'),
            $cfg->rundir, $problem->{id}) or return;

        $checker_params->{$_} = $ps->{name_parts}->{$_} for qw(name full_name);
        $cats::source_modules{$ps->{stype}} || 0 == $cats::checker_module
            or die "Bad checker type $ps->{stype}";
        $checker_params->{checker_args} =
            $ps->{stype} == $cats::checker ? qq~"$a" "$o" "$i"~ : qq~"$i" "$o" "$a"~;

        %limits = get_limits_hash($ps, $problem);

        $checker_cmd = get_cmd('check', $ps->{de_id})
            or return log_msg("No 'check' action for DE: $ps->{code}\n");
    }

    my $sp_report = $sp->run_single({ duplicate_output => \my $output },
        apply_params($checker_cmd, $checker_params), [], { %limits }) or return;

    @{$sp_report->{errors}} == 0 && $sp_report->{terminate_reason} == $TR_OK or return;

    [ $sp_report, $output ];
}

sub save_output_prefix {
    my ($dest, $problem, $req) = @_;
    my $len =
        $req->{req_save_output_prefix} //
        $req->{cp_save_output_prefix} //
        $problem->{save_output_prefix} or return;
    my $out = output_or_default($problem->{output_file});
    ($dest->{output}, $dest->{output_size}) = $fu->load_file($out, $len);
}

sub run_single_test {
    my %p = @_;
    my $problem = $p{problem};
    my $r = $p{requests};

    log_msg("[test $p{rank}]\n");

    clear_rundir or return;

    my $test_run_details = [];

    for my $req (@$r) {
        push @$test_run_details, { req_id => $req->{id}, test_rank => $p{rank}, checker_comment => '' };
        prepare_solution_environment($problem->{id},
            [ $cfg->solutionsdir, $req->{id} ], $cfg->rundir, $problem->{run_info}, 1) or return;
    }

    my $tf = $problem_cache->test_file($problem->{id}, \%p);
    my_safe_copy($tf, input_or_default($problem->{input_file}), $problem->{id}) or return;

    my $competitive_test_output;
    {

        my @run_params = get_run_params($problem, $r, { test_rank => sprintf('%02d', $p{rank}) })
            or return;

        my $get_tr_status = sub {
            return {
                $TR_ABORT          => $cats::st_runtime_error,
                $TR_TIME_LIMIT     => $cats::st_time_limit_exceeded,
                $TR_MEMORY_LIMIT   => $cats::st_memory_limit_exceeded,
                $TR_WRITE_LIMIT    => $cats::st_write_limit_exceeded,
                $TR_IDLENESS_LIMIT => $cats::st_idleness_limit_exceeded
            }->{$_[0]} // log_msg("unknown terminate reason: $_[0]\n");
        };

        my $sp_report = $sp->run(@run_params) or return;
        my @report_items = @{$sp_report->items};
        if ($problem->{run_method} == $cats::rm_interactive || $problem->{run_method} == $cats::rm_competitive) {
            my $interactor_report = shift @report_items;
            if (!$interactor_report->ok) {
                return;
            }
        }
        my $result = $cats::st_accepted;
        for my $i (0 .. $#report_items) {
            my $solution_report = $report_items[$i];
            return if @{$solution_report->{errors}};

            $test_run_details->[$i]->{time_used} = $solution_report->{consumed}->{user_time};
            $test_run_details->[$i]->{memory_used} = $solution_report->{consumed}->{memory};
            $test_run_details->[$i]->{disk_used} = $solution_report->{consumed}->{write};

            my $tr = $solution_report->{terminate_reason};
            if ($tr == $TR_OK || ($problem->{run_method} == $cats::rm_competitive && $tr == $TR_CONTROLLER)) {
                if ($solution_report->{exit_code} != 0) {
                    $test_run_details->[$i]->{checker_comment} = $solution_report->{exit_code};
                    $result = $test_run_details->[$i]->{result} = $cats::st_runtime_error;
                }
            } else {
                $result = $test_run_details->[$i]->{result} = $get_tr_status->($tr) or return;
            }

            save_output_prefix($test_run_details->[$i], $problem, $r->[$i])
                if $problem->{run_method} != $cats::rm_competitive;
        }

        save_output_prefix($competitive_test_output, $problem, $r->[0]) # Controller is always first.
            if $problem->{run_method} == $cats::rm_competitive;

        return $test_run_details
            if $problem->{run_method} != $cats::rm_competitive && $result != $cats::st_accepted;
    }

    my_safe_copy($tf, input_or_default($problem->{input_file}), $problem->{id}) or return;
    my_safe_copy(
        $problem_cache->answer_file($problem->{id}, \%p),
        [ $cfg->rundir, "$p{rank}.ans" ], $problem->{id}) or return;

    {
        my $checker_result = run_checker(problem => $problem, rank => $p{rank}) or return;
        my ($sp_report, $checker_output) = @$checker_result;

        my $save_comment = sub {
            #Encode::from_to($$c, 'cp866', 'utf8');
            # Cut to make sure comment fits in database field.
            $test_run_details->[$_[0]]->{checker_comment} = substr($_[1], 0, 199);
        };

        my $get_verdict = sub {
            return {
                0 => $cats::st_accepted,
                1 => $cats::st_wrong_answer,
                2 => $cats::st_presentation_error
            }->{$_[0]} // log_msg("checker error (exit code '$_[0]')\n");
        };

        my $result = $cats::st_accepted;
        if ($problem->{run_method} == $cats::rm_competitive) {
            return log_msg("competitive checker exit code is not zero (exit code '$sp_report->{exit_code}')\n")
                if $sp_report->{exit_code} != 0;
            $checker_output or return log_msg("competitive checker stdout is empty\n");
            for my $line (split(/[\r\n]+/, $checker_output)) {
                my @agent_result = split(/\t/, $line);
                return log_msg("competitive checker stdout bad format\n") if @agent_result < 3;

                my $agent = int $agent_result[0] - 1;
                return log_msg("competitive checker stdout error\n")
                    if $agent < 0 || $agent > @$test_run_details;

                my $agent_verdict = $get_verdict->($agent_result[1]) // return;
                $result = $agent_verdict if $agent_verdict != $cats::st_accepted;
                $test_run_details->[$agent]->{result} = $agent_verdict;
                $test_run_details->[$agent]->{points} = int $agent_result[2];
                $save_comment->($agent, $agent_result[3]) if $agent_result[3];
            }
            0 == grep !defined $_->{result}, @$test_run_details
                or return log_msg("competitive checker missing agent\n");
        } else {
            $save_comment->(0, $checker_output) if $checker_output;
            $result = $test_run_details->[0]->{result} = $get_verdict->($sp_report->{exit_code}) // return;
        }

        log_msg("OK\n") if $result == $cats::st_accepted;
    }
    ($test_run_details, $competitive_test_output);
}

sub compile {
    my ($r, $problem) = @_;
    clear_rundir or return (0, undef);

    prepare_modules($cats::solution_module) or return (0, undef);
    $fu->write_to_file([ $cfg->rundir, $r->{name_parts}->{full_name} ], $r->{src}) or return (0, undef);

    my $compile_cmd = get_cmd('compile', $r->{de_id});
    defined $compile_cmd or return (0, undef);

    if ($compile_cmd ne '') {
        my $sp_report = $sp->run_single(
            { section => $cats::log_section_compile, encoding => $judge_de_idx{$r->{de_id}}->{encoding} },
            apply_params($compile_cmd, $r->{name_parts})
        ) or return (0, undef);
        my $ok = $sp_report->ok;
        if ($ok) {
            my $runfile = get_cmd('runfile', $r->{de_id});
            $runfile = apply_params($runfile, $r->{name_parts}) if $runfile;
            if ($runfile && !(-f $cfg->rundir . "/$runfile")) {
                $ok = 0;
                log_msg("Runfile '$runfile' not created\n");
            }
        }
        if (!$ok) {
            insert_test_run_details(req_id => $r->{id}, test_rank => 1, result => $cats::st_compilation_error);
            log_msg("compilation error\n");
            return (0, $cats::st_compilation_error);
        }
    }

    if ($r->{status} == $cats::problem_st_compile) {
        log_msg("accept compiled solution\n");
        return (0, $cats::st_accepted);
    }

    my $sd = [ $cfg->solutionsdir, $r->{id} ];
    $fu->mkdir_clean($sd) or return (0, undef);
    $fu->copy([ $cfg->rundir, '*' ], $sd) or return (0, undef);
    (1, undef);
}

sub run_testplan {
    my ($tp, $problem, $requests) = @_;
    $inserted_details{$_->{id}} = {} for @$requests;
    my $run_verdict = $cats::st_accepted;
    my $competitive_outputs = {};
    for ($tp->start; $tp->current; ) {
        (my $test_run_details, $competitive_outputs->{$tp->current}) =
            run_single_test(problem => $problem, requests => $requests, rank => $tp->current)
                or return;
        # In case run_single_test returns a list of single undef via log_msg.
        $test_run_details or return;
        my $test_verdict = $cats::st_accepted;
        for my $i (0 .. $#$test_run_details) {
            my $details = $test_run_details->[$i];
            # For a test, set verdict to the first non-accepted of agent verdicts.
            $test_verdict = $details->{result} if $test_verdict == $cats::st_accepted;
            insert_test_run_details(%$details);
            $inserted_details{$details->{req_id}}->{$tp->current} = $details->{result};
            $judge->set_request_state($requests->[$i], $details->{result}, %{$requests->[$i]})
                if $problem->{run_method} == $cats::rm_competitive;
        }

        my $ok = $test_verdict == $cats::st_accepted ? 1 : 0;
        # For a run, set verdict to the lowest ranked non-accepted test verdict.
        $run_verdict = $test_verdict if !$ok && $tp->current < ($tp->first_failed || 1e10);
        $tp->set_test_result($ok);
    }
    ($run_verdict, $competitive_outputs);
}

sub test_solution {
    my ($r) = @_;

    log_msg("Testing solution: $r->{id} for problem: $r->{problem_id}\n");
    my $problem = $judge->get_problem($r->{problem_id});

    $problem->{run_info} = get_run_info($problem->{run_method});

    my @run_requests;
    my $is_group_req = 0;
    if ($r->{elements_count} && $r->{elements_count} > 0) {
        if ($r->{elements_count} == 1) {
            if ($r->{elements}->[0]->{elements_count} > 0) {
                $is_group_req = 1;
                push @run_requests, $r->{elements}->[0];
            } else {
                push @run_requests, $r;
            }
        } else {
            $is_group_req = 1;
            push @run_requests, @{$r->{elements}};
        }
    } else {
        push @run_requests, $r;
    }

    ($problem->{checker_id}) = map $_->{id}, grep
        { ($cats::source_modules{$_->{stype}} || -1) == $cats::checker_module }
        @$problem_sources;

    if (!defined $problem->{checker_id} && !defined $problem->{std_checker}) {
        log_msg("no checker defined!\n");
        return undef;
    }

    for my $run_req (@run_requests) {
        $judge->delete_req_details($run_req->{id});
        set_name_parts($run_req);
    }
    $judge->delete_req_details($r->{id}) if $is_group_req;

    my $solution_status = $cats::st_accepted;

    my $try = sub {
        for my $run_req (@run_requests) {
            my ($ret, $st) = compile($run_req, $problem);
            return $st unless $ret;
        }

        my %tests = $judge->get_testset($r->{id}, 1) or do {
            log_msg("no tests found\n");
            return $cats::st_ignore_submit;
        };
        my %tp_params = (tests => \%tests);

        if ($problem->{run_method} == $cats::rm_competitive) {
            my $tp = CATS::TestPlan::All->new(%tp_params);
            ($solution_status, my $test_outputs) = run_testplan($tp, $problem, \@run_requests) or return;
            if (my $failed_test = $tp->first_failed) {
                $r->{failed_test} = $failed_test;
            }
            $inserted_details{$r->{id}} = {};
            for my $test_rank (keys %$test_outputs) {
                my $outputs = $test_outputs->{$test_rank} or next;
                insert_test_run_details(req_id => $r->{id}, test_rank => $test_rank,
                    result => $solution_status, %$outputs);
                $inserted_details{$r->{id}}->{$test_rank} = $solution_status;
            }
        } else {
            for my $run_req (@run_requests) {
                my $tp = $r->{run_all_tests} ?
                    CATS::TestPlan::ScoringGroups->new(%tp_params) :
                    CATS::TestPlan::ACM->new(%tp_params);
                my ($run_verdict, undef) = run_testplan($tp, $problem, [ $run_req ]) or return;
                if (my $failed_test = $tp->first_failed) {
                    $run_req->{failed_test} = $r->{failed_test} = $failed_test;
                }
                # For a group request, set group verdict to the first non-accepted run verdict.
                $solution_status = $run_verdict if $solution_status == $cats::st_accepted;
                $judge->set_request_state($run_req, $run_verdict, %$run_req);
            }
        }
        'FALL';
    };

    # We throw 'REINIT' on possibly fixable errors, so try again after first catch.
    my $result = eval { $try->(); };
    if (my $e = $@) {
        $e =~ /^REINIT/ or die $e;
    }
    else {
        return ($result // '') eq 'FALL' ? $solution_status : $result;
    }
    # If the error persists, give up.
    $result = $try->();
    return ($result // '') eq 'FALL' ? $solution_status : $result;
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
    set_name_parts($_) for @$problem_sources;
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
    my $is_ready = $problem_cache->is_ready($r->{problem_id});
    if (!$is_ready || $cli->opts->{'force-install'}) {
        log_msg("installing problem $r->{problem_id}%s\n", $is_ready ? ' - forced' : '');
        eval {
            initialize_problem($r->{problem_id});
        } or do {
            $state = $cats::st_unhandled_error;
            log_msg("error: $@\n") if $@;
        };
        log_msg(
            "problem '$r->{problem_id}' " .
            ($state != $cats::st_unhandled_error ? "installed\n" : "failed to install\n"));
    }
    else {
        log_msg("problem $r->{problem_id} cached\n");
    }
    $judge->save_log_dump($r, $log->{dump});
    $judge->set_request_state($r, $state, %$r);
    ($r, $state);
}

sub test_problem {
    my ($r) = @_;

    log_msg("test log:\n");
    if ($r->{fname} && $r->{fname} =~ /[^_a-zA-Z0-9\.\\\:\$]/) {
        log_msg("renamed from '$r->{fname}'\n");
        $r->{fname} =~ tr/_a-zA-Z0-9\.\\:$/x/c;
    }

    my $state;
    eval {
        $state = test_solution($r); 1;
    } or do {
        log_msg("error: $@\n");
    };
    $state //= $cats::st_unhandled_error;

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
        if (($r->{src} // '') eq '' && @{$r->{elements}} <= 1) { # TODO: Add link -> link -> problem checking
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
    require SQL::Abstract;
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

$problem_cache = CATS::Judge::ProblemCache->new(
    cfg => $cfg, fu => $fu, log => $log, judge => $judge);

$judge->auth;
$judge->set_DEs($cfg->DEs);
$judge_de_idx{$_->{id}} = $_ for values %{$cfg->DEs};

{
    my $cfg_dirs = {};
    $cfg_dirs->{$_} = $cfg->{$_} for $cfg->dir_fields;

    my $sp_define = $cfg->defines->{'#spawner'} or die 'No #spawner define in config';
    $sp = CATS::Spawner::Default->new({
        %$cfg,
        logger => $log,
        path => apply_params($sp_define, $cfg_dirs),
        run_dir => $cfg->rundir,
        json => 1,
    });
}

if ($cli->command =~ /^(download|upload)$/) {
    CATS::Backend->new(
        log => $log,
        cfg => $cfg,
        system => $judge->{system},
        problem => $judge->{problem},
        parser => $judge->{parser},
        verbose => $judge->{verbose},
        url => $judge->{url},
        judge => $judge,
    )->sync_problem($cli->command);
}
elsif ($cli->command =~ /^(clear-cache)$/) {
    $problem_cache->remove_current;
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
