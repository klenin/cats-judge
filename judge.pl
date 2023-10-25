#!perl -w
use v5.10;
use strict;

use Carp qw(longmess shortmess confess);
use Cwd;
use Fcntl;
use File::Spec;
use FindBin;
use List::Util qw(max min);
use Time::HiRes;

sub terminate($) {
    print "\n$_[0]\n";
    exit 99;
}

use sigtrap handler => sub { terminate 'Ctrl+C pressed'; }, 'INT';

use lib File::Spec->catdir($FindBin::Bin, 'lib');
use lib File::Spec->catdir($FindBin::Bin, 'lib', 'cats-problem');

use CATS::BinaryFile;
use CATS::Config;
use CATS::Constants;
use CATS::FileUtil;
use CATS::Problem::TestsParser;
use CATS::SourceManager;
use CATS::Testset;
use CATS::Utils qw(sanitize_file_name split_fname);

use CATS::Backend;
use CATS::Judge::Config;
use CATS::Judge::ConfigFile;
use CATS::Judge::CommandLine;
use CATS::Judge::Log;
use CATS::Judge::Local;
use CATS::Judge::ProblemCache;
use CATS::Judge::SourceProcessor;

use CATS::Spawner::Default;
use CATS::Spawner::Program;
use CATS::Spawner::Const ':all';

use CATS::TestPlan;

use Digest::MD5 qw(md5_hex);
use Digest::SHA qw(sha1_hex);

use JSON::XS;

use open IN => ':crlf', OUT => ':raw';

my %lock;

INIT {
    $lock{file_name} = File::Spec->catfile(cats_dir, 'judge.lock');
    open $lock{handle}, '>', $lock{file_name}
        or terminate "Can not open $lock{file_name}: $!";
    flock $lock{handle}, Fcntl::LOCK_EX | Fcntl::LOCK_NB
        or terminate "Can not lock $lock{file_name}: $!";
    $lock{is_locked} = 1;
}

END {
    if ($lock{is_locked}) {
        flock $lock{handle}, Fcntl::LOCK_UN
            or terminate "Can not unlock $lock{file_name}: $!";
        close $lock{handle};
        unlink $lock{file_name} or terminate $!;
    }
}

my $cfg = CATS::Judge::Config->new(root => cats_dir);
my $log = CATS::Judge::Log->new;
my $cli = CATS::Judge::CommandLine->new;
my $fu = CATS::FileUtil->new({ logger => $log });
my $src_proc;

my $judge;
my $problem_cache;
my $sp;

my $problem_sources;
my $current_job_id;

sub log_msg { $log->msg(@_); }

sub update_self {
    log_msg("Updating myself\n");
    my @commands = ([ qw(git pull) ], [ qw(git submodule update --init) ]);
    for my $cmd (@commands) {
        log_msg(join(' ', @$cmd) . "\n");
        my $rr = $fu->run($cmd);
        log_msg("git> $_") for @{$rr->stdout}, @{$rr->stderr};
        return log_msg("failure: %s\n", $rr->exit_code) if $rr->exit_code;
    }
    log_msg("success\n");
    1;
}

sub run_command {
    my ($r) = @_;
    my $job_src = $r->{job_src} // '';
    my @commands = split "\n", $job_src;
    for my $cmd (@commands) {
        log_msg("Running:\n$cmd\n");
        my $rr = $fu->run([ split /\s+/, $cmd ]);
        log_msg("O> $_") for @{$rr->stdout};
        log_msg("E> $_") for @{$rr->stderr};
        return log_msg("failure: %s\n", $rr->exit_code) if !$rr->ok || $rr->exit_code;
    }
    log_msg("success\n");
    1;
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
    my $is_comp_modules = $run_info->{method} == $cats::rm_competitive_modules;

    die if !($is_competititve || $is_comp_modules) && @$rs != 1;

    my @programs;

    my $time_limit_sum = 0;
    my $safe = 1;

    for my $r (@$rs) {
        my %limits = $src_proc->get_limits($r, $problem);
        $time_limit_sum += $limits{time_limit};
        next if $is_comp_modules;

        my $solution_opts;
        if ($is_interactive || $is_competititve) {
            delete $limits{deadline};
            $solution_opts = { %limits, stdin => '*0.stdout', stdout => '*0.stdin' };
        } else {
            $solution_opts = {
                %limits, input_output_redir($problem->{input_file}, $problem->{output_file}) };
        }
        $r->{cfg_exit_code} = $src_proc->property(run_exit_code => $r->{de_id});
        $safe &&= $src_proc->property(safe => $r->{de_id});
        my $run_cmd = $src_proc->require_property(run => $r, {
            %$run_cmd_opts,
            input_file => input_or_default($problem->{input_file}),
            output_file => output_or_default($problem->{output_file}),
            output_noext => ($problem->{output_file} =~ /^(\w+)\.(?:\w+)$/ ? $1 : 'output'),
            original_output => $problem->{output_file},
        }) or return;
        push @programs, CATS::Spawner::Program->new($run_cmd, [], $solution_opts);
    }

    my $deadline_min = $cfg->default_limits->{deadline_min} // 30;
    my $sd = $time_limit_sum + ($cfg->default_limits->{deadline_add} // 5);
    my $deadline = $is_competititve || $is_comp_modules ? max($sd, $deadline_min) : $sd;

    my $global_opts = {
        deadline => $deadline,
        idle_time_limit => $cfg->default_limits->{idle_time} // 1,
        stdout => '*null',
        active_connections => 0,
        active_processes => 2,
        ($cfg->sp_user && !$safe ?
            (user => { name => $cfg->sp_user, password => $cfg->sp_password, }) : ()),
    };

    if ($is_interactive || $is_competititve || $is_comp_modules) {
        my $i = $run_info->{interactor}
            or return log_msg("No interactor specified in get_run_params\n");
        my %limits = $src_proc->get_limits($run_info->{interactor}, $problem);
        delete $limits{deadline};
        $global_opts->{idle_time_limit} = $limits{time_limit} + 1 if $limits{time_limit};

        my $run_cmd = $src_proc->require_property(run => $i, {}) or return;

        unshift @programs, CATS::Spawner::Program->new($run_cmd,
            $is_competititve ? [ scalar @programs ] :
            $is_comp_modules ? [ map $_->{name_parts}->{full_name}, @$rs ] : [],
            { controller => $is_competititve, idle_time_limit => $deadline - 1, %limits }
        );
    }

    ($global_opts, @programs);
}

sub determine_job_state {
    my ($req_state) = @_;
    $req_state == $cats::st_unhandled_error ? $cats::job_st_failed : $cats::job_st_finished;
}

sub my_safe_copy {
    my ($src, $dest, $pid) = @_;
    $fu->copy($src, $dest) and return 1;
    log_msg "Trying to reinitialize\n";
    # Either problem cache was damaged or imported module has been changed.
    # Try reinilializing the problem. If that does not help, fail the run.
    initialize_problem_wrapper($pid) or return log_msg("...failed");
    $fu->copy($src, $dest) or return;
    die 'REINIT';
}

sub clear_rundir { $fu->remove_all($cfg->rundir); }

sub generate_test {
    my ($problem, $test, $input_fname) = @_;
    my $pid = $problem->{id};
    die 'generated' if $test->{generated};

    my ($ps) = grep $_->{id} eq $test->{generator_id}, @$problem_sources or die;

    clear_rundir or return undef;

    $fu->copy($problem_cache->source_path($pid, $test->{generator_id}, '*'), $cfg->rundir)
        or return;

    my $redir;
    my $out = $ps->{output_file} // $input_fname;
    if ($out =~ /^\*STD(IN|OUT)$/) {
        $test->{gen_group} and return;
        $out = 'stdout1.txt';
        $redir = $out;
    }

    my ($args, @pipe) = split /\s*\|\s*/, $test->{param} // '';
    return log_msg("Pipe reqiures stdout for test #%d", $test->{rank}) if @pipe && !$redir;

    my $generate_cmd = $src_proc->require_property(generate => $ps, { args => $args }) or return;
    my %limits = $src_proc->get_limits($ps, $problem);
    {
        my $sp_report = $sp->run_single(
            { ($redir ? (stdout => '*null') : ()) }, $generate_cmd, [], { %limits, stdout => $redir }
        ) or return;
        $sp_report->ok or return;
    }

    my @modules = grep $_->{stype} == $cats::generator_module, @$problem_sources;
    my $i = 1;
    for my $pipe_el (@pipe) {
        my ($cmd, $args1) = $pipe_el =~ /^(\w+)\s*(.*)$/ or return;
        my ($ps1) = grep $_->{name_parts}->{name} eq $cmd, @modules
            or return log_msg("Unknown pipe element '%s' for test #%d\n", $cmd, $test->{rank});
        my $pipe_cmd = $src_proc->require_property(generate => $ps1, { args => $args1 }) or return;
        #TODO: my %pipe_limits = $src_proc->get_limits($ps1, $problem);
        my $prev = $out;
        $out = sprintf('stdout%d.txt', ++$i);
        my $sp_report = $sp->run_single(
            {}, $pipe_cmd, [], { %limits, stdin => $prev, stdout => $out }) or return;
        $sp_report->ok or return;
    }

    $out;
}

sub generate_test_group {
    my ($problem, $test, $tests) = @_;
    my $pid = $problem->{id};
    $test->{gen_group} or die 'gen_group';
    return 1 if $test->{generated};
    my $out = generate_test($problem, $test, 'in')
        or return log_msg("failed to generate test group $test->{gen_group}\n");
    for (@$tests) {
        next unless ($_->{gen_group} || 0) == $test->{gen_group};
        $_->{generated} = 1;
        my $tf = $problem_cache->test_file($pid, $_);
        my $applied_out = CATS::Problem::Parser::apply_test_rank($out, $_->{rank});
        $fu->copy_glob([ $cfg->rundir, $applied_out ], $tf) or return;
        my $hash = check_input_hash($pid, $_, $tf);
        my @input_data =  (undef, 0);
        if ($problem->{save_input_prefix} && !defined $test->{in_file}) {
            @input_data = $fu->load_file($tf, $problem->{save_input_prefix}) or return;
        }
        $judge->save_input_test_data($pid, $_->{rank}, @input_data, $hash);
    }
    1;
}

sub input_or { $_[0] =~ /^\*(?:STDIN|NONE)$/ ? 'input.txt' : $_[1] }
sub output_or { $_[0] =~ /^\*(?:STDOUT|NONE)$/ ? 'output.txt' : $_[1] }

sub input_or_default { File::Spec->catfile($cfg->rundir, input_or($_[0], $_[0])) }
sub output_or_default { File::Spec->catfile($cfg->rundir, output_or($_[0], $_[0])) }

sub input_output_redir {
    stdin => input_or($_[0], undef), stdout => output_or($_[1], undef),
}

sub get_interactor {
    my @interactors = grep $_->{stype} == $cats::interactor, @$problem_sources;

    if (!@interactors) {
        log_msg("Interactor is not defined, try search in solution modules (legacy)\n");
        # Suppose that interactor is the sole compilable solution module.
        @interactors = grep
            $_->{stype} == $cats::solution_module &&
            $src_proc->property('compile', $_->{de_id}), @$problem_sources;
        $interactors[0]->{legacy} = 1 if @interactors;
    }

    @interactors == 0 ? log_msg("Unable to find interactor\n") :
    @interactors > 1 ? log_msg('Ambiguous interactors: ' . join(',', map $_->{fname}, @interactors) . "\n") :
    $interactors[0];
}

sub _is_group_run {
    grep $_ == $_[0],
        ($cats::rm_interactive, $cats::rm_competitive, $cats::rm_competitive_modules)
}

sub _is_competitive_run { grep $_ == $_[0], ($cats::rm_competitive, $cats::rm_competitive_modules) }

sub prepare_solution_environment {
    my ($pid, $solution_dir, $run_dir, $run_info, $safe) = @_;

    my $copy_func = $safe ? sub { my_safe_copy(@_, $pid) } : sub { $fu->copy(@_) };

    $copy_func->([ @$solution_dir, '*' ], $run_dir) or return;

    if (_is_group_run($run_info->{method})) {
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
    my %p = _is_group_run($run_method) ? ( interactor => get_interactor() ) : ();
    { method => $run_method, %p }
}

sub validate_test {
    my ($problem, $test, $path_to_test) = @_;
    my $pid = $problem->{id};
    my $in_v_id = $test->{input_validator_id} or return 1;
    clear_rundir or return;
    my ($validator) = grep $_->{id} eq $in_v_id, @$problem_sources or die;
    $fu->copy($path_to_test, $cfg->rundir) or return;
    $fu->copy($problem_cache->source_path($pid, $in_v_id, '*'), $cfg->rundir) or return;

    my (undef, undef, $t_fname, $t_name, undef) = split_fname(File::Spec->catfile(@$path_to_test));
    my $validate_cmd = $src_proc->require_property(
        validate => $validator,
        { test_input => $t_fname, args => $test->{input_validator_param} // '' }) or return;

    my $sp_report = $sp->run_single({ stdin => $t_fname },
        $validate_cmd,
        [],
        { $src_proc->get_limits($validator, $problem) }
    ) or return;

    $sp_report->ok;
}

sub read_lines_for_hash {
    my ($filename) = @_;
    my $data = $fu->read_lines($filename, io => ':crlf');
    join '\n', @$data;
}

sub check_input_hash {
    my ($pid, $test, $filename) = @_;

    my $input = read_lines_for_hash($filename);

    my $hash = $test->{in_file_hash};

    if (defined $hash) {
        my ($alg, $old_hash_val) = $hash =~ /^\$(.*?)\$(.*)$/;
        $alg or die 'No hash algorithm';
        my $hash_fn = { md5 => \&md5_hex, sha => \&sha1_hex }->{$alg}
            or die "Unsupported hash algorithm $alg";
        my $new_hash_val = $hash_fn->($input);
        $old_hash_val eq $new_hash_val
            or die "Invalid hash for test $test->{rank}: old=$old_hash_val new=$new_hash_val";
        return undef;
    }
    else {
        $hash = '$sha$' . sha1_hex($input);
    }
    $hash;
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

        my @input_data = (undef, 0);
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
                    @input_data = $fu->load_file($tf, $problem->{save_input_prefix}) or return;
                }
            }
        }
        else {
            log_msg("no input defined for test #$t->{rank}\n");
            return undef;
        }

        my $hash = check_input_hash($pid, $t, $tf);
        $judge->save_input_test_data($pid, $t->{rank}, @input_data, $hash);

        validate_test($problem, $t, $tf) or
            return log_msg("input validation failed: #$t->{rank}\n");

        # Create test output file.
        my $af = $problem_cache->answer_file($pid, $t);
        if (defined $t->{out_file} && !defined $t->{out_file_size}) {
            $fu->write_to_file($af, $t->{out_file}) or return;
        }
        elsif (defined $t->{std_solution_id}) {
            if (_is_competitive_run($problem->{run_method})) {
                return log_msg("run solution in competitive problem not implemented");
            }

            my ($ps) = grep $_->{id} eq $t->{std_solution_id}, @$problem_sources;
            my ($main) = grep $ps->{fname} eq ($_->{main} // ''), @$problem_sources;

            clear_rundir or return undef;

            prepare_solution_environment(
                $pid, $problem_cache->source_path($pid, $t->{std_solution_id}),
                $cfg->rundir, $problem->{run_info}) or return;

            $fu->copy($tf, input_or_default($problem->{input_file})) or return;

            my @run_params = get_run_params($problem, [ $main // $ps ], {}) or return;
            my $sp_report = $sp->run(@run_params) or return;

            return if grep !$_->ok, @{$sp_report->items};

            $fu->copy(output_or_default($problem->{output_file}), $af)
                or return;

            $judge->save_answer_test_data(
                $pid, $t->{rank}, $fu->load_file($af, $problem->{save_answer_prefix})
            ) if $problem->{save_answer_prefix} && !defined $t->{out_file};
        }
        elsif (!defined $t->{snippet_name}) {
            return log_msg("no output file defined for test #$t->{rank}\n");
        }
    }

    1;
}

sub prepare_modules {
    my ($stype) = @_;
    # Select modules in order they are listed in problem definition xml.
    # FIXME: It is currently all local modules after all imports.
    for my $m (grep $_->{stype} == $stype, @$problem_sources) {
        my $fname = $m->{name_parts}->{full_name};
        log_msg("module: $fname\n");
        $fu->write_to_file([ $cfg->rundir, $fname ], $m->{src}) or return;

        $m->{main} // (grep $m->{fname} eq ($_->{main} // ''), @$problem_sources) and next;
        my $r = $src_proc->compile($m);
        defined $r && $r == $cats::st_testing or return $r;
    }
    $cats::st_testing;
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
        clear_rundir or return;

        (prepare_modules($cats::source_modules{$ps->{stype}} || 0) // -1) == $cats::st_testing or return;

        $fu->write_to_file([ $cfg->rundir, $ps->{name_parts}->{full_name} ], $ps->{src}) or return;

        my ($main) = grep $ps->{fname} eq ($_->{main} // ''), @$problem_sources;
        ($src_proc->compile($main // $ps) // -1) == $cats::st_testing or return;

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
                CATS::SourceManager::save(
                    $guided_source, $cfg->modulesdir, File::Spec->rel2abs($path));
                log_msg("save source $guided_source->{guid}\n");
            }
        }
    }
    prepare_tests($p) or return undef;

    $problem_cache->save_description($pid, $p->{title}, $p->{upload_date}, 'ready')
        or return undef;

    1;
}

sub initialize_problem_wrapper {
    my $pid = shift;

    my $prev_dump = $log->get_dump;
    $log->clear_dump;

    my $job_id = $judge->create_job($cats::job_type_initialize_problem, {
        problem_id => $pid,
        state => $cats::job_st_in_progress,
        parent_id => $current_job_id,
    });

    log_msg("Created job $job_id\n");
    my $res;
    eval {
        $res = initialize_problem($pid);
    } or do {
        log_msg("error during initialization: $@\n") if $@;
    };

    $judge->finish_job($job_id, $res ? $cats::job_st_finished : $cats::job_st_failed) or
        log_msg("Job canceled\n");

    $judge->save_logs($job_id, $log->get_dump);

    $log->clear_dump;
    $log->dump_write($prev_dump);

    $res;
}

my %inserted_details;

sub insert_test_run_details {
    my %p = @_;
    for ($inserted_details{$p{req_id}}->{$p{test_rank}}) {
        return 1 if $_;
        $_ = $p{result};
    }
    $judge->insert_req_details($current_job_id, \%p);
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

    my ($checker_cmd, %limits, $checker_type);
    if (defined $problem->{std_checker}) {
        $checker_cmd = $cfg->checkers->{$problem->{std_checker}}
            or return log_msg("unknown std checker: $problem->{std_checker}\n");
        $checker_cmd = CATS::Judge::Config::apply_params($checker_cmd, $checker_params);
        %limits = $src_proc->get_limits({}, $problem);
    }
    elsif ($problem->{checker_id}) {
        my ($ps) = grep $_->{id} eq $problem->{checker_id}, @$problem_sources;

        my_safe_copy(
            $problem_cache->source_path($problem->{id}, $problem->{checker_id}, '*'),
            $cfg->rundir, $problem->{id}) or return;

        $checker_params->{$_} = $ps->{name_parts}->{$_} for qw(name full_name);
        $cats::source_modules{$ps->{stype}} || 0 == $cats::checker_module
            or die "Bad checker type $ps->{stype}";
        $checker_type = $ps->{stype};
        $checker_params->{checker_args} =
            $ps->{stype} == $cats::checker ? qq~"$a" "$o" "$i"~ : qq~"$i" "$o" "$a"~;

        %limits = $src_proc->get_limits($ps, $problem);

        $checker_cmd = $src_proc->require_property(check => $ps, $checker_params) or return;
    }
    else { # No checker defined, assume 'OK'.
        return [ { exit_code => 0 } ];
    }

    my $sp_report = $sp->run_single({ duplicate_output => \my $output },
        $checker_cmd, [], { %limits }) or return;
    $sp_report->tr_ok or return;
    my $checker_points;
    if (($checker_type // -1) == $cats::partial_checker) {
        if (defined($output) && $output =~ /^(-?\d+)/) {
            $checker_points = int($1);
        }
        else {
            return log_msg("Partial checker did not output points\n") if $sp_report->{exit_code} == 0;
        }
    }

    [ $sp_report, $output, $checker_points ];
}

sub save_output_prefix {
    my ($dest, $problem, $req) = @_;
    return if $dest->{output_size}; # Runtime error message
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
        # TODO: Copy interactor once after loop.
        prepare_solution_environment($problem->{id},
            [ $cfg->solutionsdir, $req->{id} ], $cfg->rundir, $problem->{run_info}, 1) or return;
    }

    my $tf = $problem_cache->test_file($problem->{id}, \%p);
    my_safe_copy($tf, input_or_default($problem->{input_file}), $problem->{id}) or return;

    my $competitive_test_output = {};
    {

        my @run_params = get_run_params($problem, $r, { test_rank => sprintf('%02d', $p{rank}) })
            or return;

        my $get_tr_status = sub {
            return {
                $TR_ABORT          => $cats::st_runtime_error,
                $TR_TIME_LIMIT     => $cats::st_time_limit_exceeded,
                $TR_MEMORY_LIMIT   => $cats::st_memory_limit_exceeded,
                $TR_WRITE_LIMIT    => $cats::st_write_limit_exceeded,
                $TR_IDLENESS_LIMIT => $cats::st_idleness_limit_exceeded,
                # $TR_SECURITY       => log_msg("security problem, setting UH\n"),
            }->{$_[0]} // log_msg("unknown terminate reason: $_[0]\n");
        };

        my $sp_report = $sp->run(@run_params) or return;
        my @report_items = @{$sp_report->items};
        if (_is_group_run($problem->{run_method} )) {
            my $interactor_report = shift @report_items;
            if (!$interactor_report->ok && $interactor_report->{terminate_reason} != $TR_IDLENESS_LIMIT) {
                return;
            }
        }
        my $result = $cats::st_accepted;
        for my $i (0 .. $#report_items) {
            my $solution_report = $report_items[$i];
            return if @{$solution_report->{errors}};
            my $d = $test_run_details->[$i];

            $d->{time_used} = $solution_report->{consumed}->{user_time};
            $d->{memory_used} = $solution_report->{consumed}->{memory};
            $d->{disk_used} = $solution_report->{consumed}->{write};

            my $tr = $solution_report->{terminate_reason};
            if ($tr == $TR_OK || ($problem->{run_method} == $cats::rm_competitive && $tr == $TR_CONTROLLER)) {
                if (($r->[$i]->{cfg_exit_code} // '') ne 'ignore' && $solution_report->{exit_code} != 0) {
                    $result = $d->{result} = $cats::st_runtime_error;
                }
            } else {
                $result = $d->{result} = $get_tr_status->($tr) or return;
            }
            if ($result == $cats::st_runtime_error) {
                $d->{checker_comment} = $solution_report->{exit_code};
                my $stderr_file = File::Spec->catfile($cfg->rundir, $cfg->stderr_file);
                ($d->{output}, $d->{output_size}) = $fu->load_file($stderr_file, $cfg->runtime_stderr_size);
            }

            save_output_prefix($test_run_details->[$i], $problem, $r->[$i])
                if !_is_competitive_run($problem->{run_method});
        }

        save_output_prefix($competitive_test_output, $problem, $r->[0]) # Controller is always first.
            if _is_competitive_run($problem->{run_method});

        return $test_run_details
            if !_is_competitive_run($problem->{run_method}) && $result != $cats::st_accepted;
    }

    my_safe_copy($tf, input_or_default($problem->{input_file}), $problem->{id}) or return;

    if (defined $p{snippet_name}) {
        # @$r[0]
        my $snippet_answer = $judge->get_snippet_text(
            $problem->{id}, $r->[0]->{contest_id}, $r->[0]->{account_id}, [ $p{snippet_name} ])->[0];
        defined $snippet_answer or return log_msg("Answer snippet '%s' not found\n", $p{snippet_name});
        $fu->write_to_file([ $cfg->rundir, "$p{rank}.ans" ], $snippet_answer) or return;
    }
    else {
        my_safe_copy(
            $problem_cache->answer_file($problem->{id}, \%p),
            [ $cfg->rundir, "$p{rank}.ans" ], $problem->{id}) or return;
    }

    {
        my $checker_result = run_checker(problem => $problem, rank => $p{rank}) or return;
        my ($sp_checker_report, $checker_output, $checker_points) = @$checker_result;
        my $checker_exit_code = $sp_checker_report->{exit_code};

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
        if (_is_competitive_run($problem->{run_method})) {
            return log_msg("competitive checker exit code is not zero (exit code '$checker_exit_code')\n")
                if $checker_exit_code != 0;
            $checker_output or return log_msg("competitive checker stdout is empty\n");
            $checker_points = '';
            for my $line (split(/[\r\n]+/, $checker_output)) {
                my @agent_result = split(/\t/, $line);
                return log_msg("competitive checker stdout bad format\n") if @agent_result < 3;

                my $agent = int $agent_result[0] - 1;
                return log_msg("competitive checker stdout error\n")
                    if $agent < 0 || $agent > @$test_run_details;

                my $agent_verdict = $get_verdict->($agent_result[1]) // return;
                #$result = $agent_verdict if $agent_verdict != $cats::st_accepted;
                $test_run_details->[$agent]->{result} = $agent_verdict;
                $test_run_details->[$agent]->{points} = int $agent_result[2];
                $checker_points .= " $agent_result[2]";
                $save_comment->($agent, $agent_result[3]) if $agent_result[3];
            }
            0 == grep !defined $_->{result}, @$test_run_details
                or return log_msg("competitive checker missing agent\n");
        } else {
            $save_comment->(0, $checker_output) if defined $checker_output;
            $result = $test_run_details->[0]->{result} =
                $get_verdict->($checker_exit_code) // return;
            if ($result == $cats::st_accepted && defined $checker_points) {
                $test_run_details->[0]->{points} = $checker_points;
            }
        }

        log_msg("OK%s\n", defined $checker_points ? " pt=$checker_points" : '')
            if $result == $cats::st_accepted;
    }
    ($test_run_details, $competitive_test_output);
}

sub lint {
    my ($r, $problem, $stage) = @_;

    my @linters = grep $_->{stype} == $stage, @$problem_sources or return $cats::st_testing;

    my $lint_dir = $cfg->rundir; # /_lint
    #$fu->mkdir_clean($lint_dir);

    for my $linter (@linters) {
        log_msg("lint: $linter->{fname}\n");
        my_safe_copy(
            $problem_cache->source_path($problem->{id}, $linter->{id}, '*'),
            $lint_dir, $problem->{id}) or return;
        my $run_cmd = $src_proc->require_property(run => $linter, {}) or return;

        my $sp_report = $sp->run_single(
            { section => $cats::log_section_lint },
            $run_cmd,
            [ $r->{main} // $r->{name_parts}->{full_name} ],
            { $src_proc->get_limits($linter, $problem) }
        ) or return;
        $sp_report->ok or return $cats::st_lint_error;
    }
    $cats::st_testing;
}

sub compile {
    my ($r, $problem) = @_;

    clear_rundir or return;

    my $modules_result = prepare_modules($cats::solution_module) or return;
    $modules_result == $cats::st_testing or return $modules_result;

    if (my ($main) = grep $_->{main}, @$problem_sources) {
        log_msg("Substituting main: %s -> %s\n", $main->{fname}, $main->{main});
        $fu->write_to_file([ $cfg->rundir, $main->{fname} ], $main->{src}) or return;
        $fu->write_to_file([ $cfg->rundir, $main->{main} ], $r->{src}) or return;
        $r->{main} = $main->{main};
        $r->{fname} = $main->{fname};
        set_name_parts($r);
    } else {
        # TODO: Prevent name conflicts in competitive runs!!
        $fu->write_to_file([ $cfg->rundir, $r->{name_parts}->{full_name} ], $r->{src}) or return;
    }

    {
        my $lint_result = lint($r, $problem, $cats::linter_before) or return;
        $lint_result == $cats::st_testing or return $lint_result;
    }
    my $result = $src_proc->compile($r, { section => 1 }) or return;
    if ($result == $cats::st_compilation_error) {
        return $result;
    }
    $result == $cats::st_testing or die;
    {
        my $lint_result = lint($r, $problem, $cats::linter_after) or return;
        $lint_result == $cats::st_testing or return $lint_result;
    }

    if ($r->{status} == $cats::problem_st_compile) {
        log_msg("accept compiled solution\n");
        return $cats::st_accepted;
    }

    my $sd = [ $cfg->solutionsdir, $r->{id} ];
    $fu->mkdir_clean($sd) or return;
    $fu->copy([ $cfg->rundir, '*' ], $sd) or return;
    $cats::st_testing;
}

sub run_testplan {
    my ($tp, $problem, $requests, $tests_snippet_names) = @_;
    $inserted_details{$_->{id}} = {} for @$requests;
    my $run_verdict = $cats::st_accepted;
    my $is_competitive = _is_competitive_run($problem->{run_method});
    my $competitive_outputs = {};
    for ($tp->start; $tp->current; ) {
        (my $test_run_details, $competitive_outputs->{$tp->current}) =
            run_single_test(problem => $problem, requests => $requests, rank => $tp->current,
                snippet_name => $tests_snippet_names->{$tp->current}) or return;
        # In case run_single_test returns a list of single undef via log_msg.
        $test_run_details or return;
        my $test_verdict = $cats::st_accepted;
        for my $i (0 .. $#$test_run_details) {
            my $details = $test_run_details->[$i];
            # For a test, set verdict to the first non-accepted of agent verdicts.
            $test_verdict = $details->{result} if $test_verdict == $cats::st_accepted;
            insert_test_run_details(%$details) or return;
            $inserted_details{$details->{req_id}}->{$tp->current} = $details->{result};
            if ($is_competitive) {
                $judge->set_request_state(
                    $requests->[$i], $details->{result}, $current_job_id, %{$requests->[$i]}) or return;
            }
        }

        my $ok = $test_verdict == $cats::st_accepted ? 1 : 0;
        # For a run, set verdict to the lowest ranked non-accepted test verdict.
        $run_verdict = $test_verdict
            if !$ok && $tp->current < ($tp->first_failed || 1e10) && !$is_competitive;
        $tp->set_test_result($ok);
    }
    ($run_verdict, $competitive_outputs);
}

sub get_run_reqs {
    my ($r) = @_;
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
    ($is_group_req, @run_requests);
}

sub delete_req_details {
    my ($r, $is_group_req, @run_requests) = @_;

    for (@run_requests) {
        $judge->delete_req_details($_->{id}, $current_job_id) or return;
        $judge->set_request_state($_, $cats::st_testing, $current_job_id) or return;
    }
    $judge->delete_req_details($r->{id}, $current_job_id) or return if $is_group_req;
    1;
}

sub _number_or {
    if (!$_[0] || $_[0] !~ /^[0-9]+$/) {
        log_msg("Invalid param %s\n", $_[0]) if $_[0];
        $_[0] = $_[1];
    }
}

sub get_split_strategy {
    my ($r) = @_;
    my $strategy = $r->{req_job_split_strategy} // $r->{cp_job_split_strategy};
    my $res = { method => $cats::split_default };
    if ($strategy) {
        eval {
            $res = decode_json($strategy);
            1;
        } or log_msg("Invalid json: %s (%s)\n", $strategy, $@);
    }

    _number_or($res->{min_tests_per_job}, $CATS::Config::split->{min_tests_per_job});
    _number_or($res->{split_cnt}, $r->{judges_alive} // $CATS::Config::split->{default_cnt});
    $res;
}

sub split_solution {
    my ($r) = @_;
    log_msg("Splitting solution $r->{id} for problem $r->{problem_id} into parts\n");
    log_msg("Split strategy: %s\n", $r->{split_strategy}->{method});

    my ($is_group_req, @run_requests) = get_run_reqs($r);
    delete_req_details($r, $is_group_req, @run_requests) or return $cats::st_unhandled_error;

    my %tests = $judge->get_testset('reqs', $r->{id}, 1) or do {
        log_msg("no tests found\n");
        $judge->save_logs($r->{job_id}, $log->get_dump);
        return $cats::st_ignore_submit;
    };

    my $testsets;
    if ($r->{split_strategy}->{method} eq $cats::split_subtasks) {
        my (@other, %subtasks);
        for (keys %tests) {
            if (CATS::Testset::is_scoring_group($tests{$_})) {
                $subtasks{$tests{$_}->{name}} = 1;
            }
            else {
                push @other, $_;
            }
        }
        $testsets = [ keys %subtasks, @other ? CATS::Testset::pack_rank_spec(@other) : () ];
    }
    elsif ($r->{split_strategy}->{method} eq $cats::split_explicit) {
        $testsets = $r->{split_strategy}->{testsets} // [];
        if (ref $testsets ne 'ARRAY') {
            log_msg("Invalid testsets: %s\n", $testsets);
            return $cats::st_ignore_submit;
        }
    }
    else {
        my $strategy = $r->{split_strategy};
        my $parts_cnt = $strategy->{split_cnt};
        my $tests_count = keys %tests;

        my $subtasks_amount = min($parts_cnt, max(1, $tests_count / $strategy->{min_tests_per_job}));

        my @tests;
        push @{$tests[$_ % $subtasks_amount]}, $_ for keys %tests;

        $testsets = [ map CATS::Testset::pack_rank_spec(@$_), @tests ];
    }

    @$testsets > 1 or return log_msg("Too few solution parts: no need to split solution\n");

    $judge->create_splitted_jobs($cats::job_type_submission_part,
        $testsets, {
        problem_id => $r->{problem_id},
        contest_id => $r->{contest_id},
        state => $cats::job_st_waiting,
        parent_id => $r->{job_id},
        req_id => $r->{id},
    });

    $judge->save_logs($r->{job_id}, $log->get_dump);
    $cats::st_testing;
}

sub test_solution {
    my ($r, $problem) = @_;

    $log->colored($cfg->color->{testing_start})->
        msg("Testing solution part: $r->{id} for problem: $r->{problem_id}\n");

    $problem->{run_info} = get_run_info($problem->{run_method});

    ($problem->{checker_id}) = map $_->{id}, grep
        { ($cats::source_modules{$_->{stype}} || -1) == $cats::checker_module }
        @$problem_sources;

    if (
        $problem->{run_method} != $cats::rm_none &&
        !defined $problem->{checker_id} && !defined $problem->{std_checker}
    ) {
        return log_msg("no checker defined!\n");
    }

    my ($is_group_req, @run_requests) = get_run_reqs($r);
    set_name_parts($_) for @run_requests;
    delete_req_details($r, $is_group_req, @run_requests) or return
        if $r->{type} == $cats::job_type_submission;

    my $solution_status = $cats::st_accepted;
    my $try = sub {
        for my $run_req (@run_requests) {
            my $st = compile($run_req, $problem);
            $run_req->{pre_run_error} = $st
                if $st && ($st == $cats::st_compilation_error || $st == $cats::st_lint_error);
            return $st if !$st || $st != $cats::st_testing;
        }
        my %tests =
            _is_competitive_run($problem->{run_method}) || $r->{type} == $cats::job_type_submission ?
            $judge->get_testset('reqs', $r->{id}, 1) : $judge->get_testset('jobs', $r->{job_id});

        %tests or do {
            log_msg("no tests found\n");
            return $cats::st_ignore_submit;
        };
        my $problem_tests = $judge->get_problem_tests($problem->{id});
        my %tests_snippet_names = map { $_->{rank} => $_->{snippet_name} } @$problem_tests;
        my %tp_params = (tests => \%tests);

        if (_is_competitive_run($problem->{run_method})) {
            my $tp = CATS::TestPlan::All->new(%tp_params);
            ($solution_status, my $test_outputs) =
                run_testplan($tp, $problem, \@run_requests, \%tests_snippet_names) or return;
            if (my $failed_test = $tp->first_failed) {
                $r->{failed_test} = $failed_test;
            }
            $inserted_details{$r->{id}} = {};
            for my $test_rank (keys %$test_outputs) {
                my $outputs = $test_outputs->{$test_rank} or next;
                insert_test_run_details(req_id => $r->{id}, test_rank => $test_rank,
                    result => $solution_status, %$outputs) or return;
                $inserted_details{$r->{id}}->{$test_rank} = $solution_status;
            }
        } else {
            for my $run_req (@run_requests) {
                my $tp = $r->{run_all_tests} ?
                    CATS::TestPlan::ScoringGroups->new(%tp_params) :
                    CATS::TestPlan::ACM->new(%tp_params);
                my ($run_verdict, undef) =
                    run_testplan($tp, $problem, [ $run_req ], \%tests_snippet_names) or return;
                if (my $failed_test = $tp->first_failed) {
                    $run_req->{failed_test} = $r->{failed_test} = $failed_test;
                }
                # For a group request, set group verdict to the first non-accepted run verdict.
                $solution_status = $run_verdict if $solution_status == $cats::st_accepted;
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
    my ($r) = @_;
    $r or return $cats::st_unhandled_error;

    if (defined $r->{id} && !defined $r->{status}) {
        log_msg("security: problem $r->{problem_id} is not included in contest $r->{contest_id}\n");
        $judge->set_request_state($r, $cats::st_unhandled_error, $current_job_id);
        return $cats::st_unhandled_error;
    }

    $problem_sources = $judge->get_problem_sources($r->{problem_id});
    set_name_parts($_) for @$problem_sources;
    # Ignore unsupported DEs for requests, but demand every problem to be installable on every judge.
    my %unsupported_DEs = $src_proc->unsupported_DEs($problem_sources);
    if (%unsupported_DEs) {
        log_msg("unsupported DEs for problem %s: %s\n",
            $r->{problem_id}, join ', ', sort keys %unsupported_DEs);
        $judge->set_request_state($r, $cats::st_unhandled_error, $current_job_id, %$r);
        return $cats::st_unhandled_error;
    }

    my $state = $cats::st_testing;
    my $is_ready = $problem_cache->is_ready($r->{problem_id});
    if (!$is_ready || $cli->opts->{'force-install'}) {
        $log->colored($cfg->color->{install_start})->
            msg("installing problem $r->{problem_id}%s\n", $is_ready ? ' - forced' : '');
        eval {
            $r->{type} == $cats::job_type_initialize_problem ? 
            initialize_problem($r->{problem_id}) : initialize_problem_wrapper($r->{problem_id});
        } or do {
            $state = $cats::st_unhandled_error;
            log_msg("error: $@\n") if $@;
        };
        $log->colored(
            $cfg->color->{$state != $cats::st_unhandled_error ? 'install_ok' : 'install_fail'})->
            msg("problem '%s' %s\n", $r->{problem_id},
                ($state != $cats::st_unhandled_error ? 'installed' : 'failed to install'));
    }
    else {
        $log->colored($cfg->color->{problem_cached})->msg("problem '$r->{problem_id}' cached\n");
    }

    $judge->set_request_state($r, $state, $current_job_id, %$r) if $state == $cats::st_unhandled_error;

    $state;
}

sub log_state_text {
    my ($state, $failed_test) = @_;

    my $state_text = { map {; /^st_(.+)$/ ? (eval('$cats::' . $_) => $1) : (); } keys %cats:: }->{$state};
    $state_text =~ s/_/ /g;
    $state_text .= " on test $failed_test" if $failed_test;
    log_msg("==> $state_text\n");
}

sub is_UH_or_CE {
    my ($state) = @_;
    $state == $cats::st_compilation_error ||
    $state == $cats::st_lint_error ||
    $state == $cats::st_unhandled_error;
}

sub set_verdict {
    my ($r, $parent_id, $state) = @_;

    $state = $cats::st_accepted if !is_UH_or_CE($state);

    my ($is_group_req, @run_requests) = get_run_reqs($r);

    for my $req (@run_requests) {
        if ($state == $cats::st_unhandled_error) {
            $judge->set_request_state($req, $state, $parent_id, %$req) or return;
            next;
        }

        if ($req->{pre_run_error}) {
            $judge->set_request_state($req, $req->{pre_run_error}, $parent_id, %$req) or return;
            next;
        }

        my $req_details = $judge->get_tests_req_details($req->{id});
        my $tp = CATS::TestPlan->new;
        my $cur_req_state = $tp->get_state($req_details);
        $req->{failed_test} = $tp->first_failed;

        if ($state == $cats::st_accepted) {
            $state = $cur_req_state;
            $r->{failed_test} = $req->{failed_test};
        }

        if ($req->{status} == $cats::problem_st_manual && $cur_req_state == $cats::st_accepted) {
            $cur_req_state = $cats::st_awaiting_verification;
        }

        $judge->set_request_state($req, $cur_req_state, $parent_id, %$req) or return;
    }

    $judge->set_request_state($r, $state, $parent_id, %$r) or return if $is_group_req;

    $judge->finish_job($parent_id, determine_job_state($state)) or return log_msg("Job canceled\n");
    log_state_text($state, $r->{failed_test});
    $judge->cancel_all($r->{id}) if is_UH_or_CE($state);
}

sub test_problem {
    my ($r, $problem) = @_;

    my $orig_name = $r->{fname};
    sanitize_file_name($r->{fname}) and log_msg("renamed from '$orig_name'\n");

    my $state;
    eval {
        $state = test_solution($r, $problem); 1;
    } or do {
        log_msg("error: $@\n");
    };
    $state //= $cats::st_unhandled_error;

    if ($r->{type} == $cats::job_type_submission) {
        set_verdict($r, $r->{job_id}, $state);
        eval { $judge->save_logs($r->{job_id}, $log->get_dump); } or log_msg("$@\n");
        return;
    }

    my $stop_now = is_UH_or_CE($state);
    # In case of UH, prevent other judges from setting verdict,
    # otherwise make sure at least one judge will set verdict.
    my $job_finished;
    $job_finished = $judge->finish_job($r->{job_id}, $cats::job_st_finished) if !$stop_now;
    my ($parent_id, $is_set_req_state_allowed) = $judge->is_set_req_state_allowed($r->{job_id}, $stop_now);
    $job_finished = $judge->finish_job($r->{job_id}, determine_job_state($state)) if $stop_now;
    log_msg("Job canceled\n") if !$job_finished;

    # It is too late to report error, since set_request_state might have already been called.
    eval { $judge->save_logs($r->{job_id}, $log->get_dump); } or log_msg("$@\n");

    $job_finished or return;

    set_verdict($r, $parent_id, $state) if $is_set_req_state_allowed;
}

sub generate_snippets {
    my ($r) = @_;

    my $problem = $judge->get_problem($r->{problem_id});
    # TODO: move to select_request
    my $snippets = $judge->get_problem_snippets($r->{problem_id});
    my $tags = $judge->get_problem_tags($r->{problem_id}, $r->{contest_id}, $r->{account_id}) // '';
    $tags =~ s/\s+//g;

    my $generators = {};
    push @{$generators->{$_->{generator_id}} //= []}, $_->{name} for grep $_->{generator_id}, @$snippets;

    my $job_state = $cats::job_st_finished;
    my $results = {};
    eval {
        clear_rundir or die;

        my $old_snippets = $judge->get_snippet_text(
            $r->{problem_id}, $r->{contest_id}, $r->{account_id}, [ map $_->{name}, @$snippets ]);
        for (my $i = 0; $i < @$snippets; ++$i) {
            $fu->write_to_file([ $cfg->rundir, $snippets->[$i]->{name} ], $old_snippets->[$i] // '') or die;
        }

        for my $gen_id (sort keys %$generators) {
            my ($ps) = grep $_->{id} == $gen_id, @$problem_sources or die;

            $fu->copy($problem_cache->source_path($r->{problem_id}, $gen_id, '*'), $cfg->rundir) or die;

            my $generate_cmd = $src_proc->require_property(generate => $ps, { args => '' }) or die;
            my %limits = $src_proc->get_limits($ps, $problem);
            my $sp_report = $sp->run_single(
                { save_output => 1, show_output => 1 }, $generate_cmd, [ $tags ], \%limits) or die;
            $sp_report->ok or die;

            my @snippet_names = @{$generators->{$gen_id}};
            for my $sn (@snippet_names) {
                CATS::BinaryFile::load(CATS::FileUtil::fn([ $cfg->rundir, $sn ]), \my $data);
                $results->{$sn} = $data;
            }
            log_msg("Generated: %s\n", join ', ', sort @snippet_names);
        }
        $judge->save_problem_snippets(
            $r->{problem_id}, $r->{contest_id}, $r->{account_id}, $results) or die;
        1;
    } or do { log_msg($@); $job_state = $cats::job_st_failed; };

    $judge->finish_job($r->{job_id}, $job_state) or log_msg("Job canceled\n");
    $judge->save_logs($r->{job_id}, $log->get_dump);
}

sub timer_start { [ Time::HiRes::gettimeofday ] }
sub timer_since { Time::HiRes::tv_interval($_[0], [ Time::HiRes::gettimeofday ]) }

my ($total_timer, $timer_count) = (0, 0);

sub main_loop {
    chdir $cfg->workdir
        or return log_msg("change to workdir '%s' failed: $!\n", $cfg->workdir);

    -x $sp->{sp} or log_msg("Spawner not found at: %s\n", $sp->{sp});
    log_msg("judge: %s, api: %s, version: %s\n", $judge->name, $cfg->api, $judge->version);
    log_msg("supported DEs: %s\n", join ',', sort { $a <=> $b } keys %{$cfg->DEs});

    my $current_sleep = 0;
    for (my $i = 0; !$cfg->restart_count || $i < $cfg->restart_count; $i++) {
        sleep $current_sleep;
        $current_sleep =
            $current_sleep * 2 > $cfg->sleep_time ? $cfg->sleep_time :
            $current_sleep == 0 ? 1 :
            $current_sleep * 2;
        $log->rollover;
        syswrite STDOUT, "\b" . (qw(/ - \ |))[$i % 4];
        my $timer = timer_start;
        my $r = $judge->select_request;
        my $dt = timer_since($timer);
        $total_timer += $dt;
        $timer_count++;
        if ($judge->was_pinged) {
            log_msg("\naverage select_request time: %.3f\n", $total_timer / $timer_count);
            log_msg("pong\n");
        }
        $r or next;
        $current_sleep = 0;

        $current_job_id = $r->{job_id};
        $log->clear_dump;

        if ($r->{type} == $cats::job_type_update_self) {
            my $updated = update_self;
            $judge->finish_job($r->{job_id}, $updated ? $cats::job_st_finished : $cats::job_st_failed);
            $judge->save_logs($r->{job_id}, $log->get_dump);
            $updated ? exit : next;
        }

        if ($r->{type} == $cats::job_type_run_command) {
            $judge->finish_job($r->{job_id}, run_command($r) ? $cats::job_st_finished : $cats::job_st_failed);
            $judge->save_logs($r->{job_id}, $log->get_dump);
            next;
        }

        my $state = prepare_problem($r);
        if ($state == $cats::st_unhandled_error || $r->{type} == $cats::job_type_initialize_problem) {
            my ($parent_id, $is_set_req_state_allowed) =
                $judge->is_set_req_state_allowed($r->{job_id}, 1) if $state == $cats::st_unhandled_error;
            $judge->finish_job($r->{job_id}, determine_job_state($state)) or log_msg("Job canceled\n");
            $judge->save_logs($r->{job_id}, $log->get_dump);
            $judge->cancel_all($r->{id}) if $is_set_req_state_allowed;
            next;
        }

        if ($r->{type} == $cats::job_type_generate_snippets) {
            generate_snippets($r);
        }
        elsif ($r->{type} == $cats::job_type_submission || $r->{type} == $cats::job_type_submission_part) {
            if (($r->{src} // '') eq '' && @{$r->{elements}} <= 1) { # TODO: Add link -> link -> problem checking
                log_msg("Empty source for problem $r->{problem_id}\n");
                $judge->set_request_state($r, $cats::st_unhandled_error, $current_job_id);
                $judge->finish_job($r->{job_id}, $cats::job_st_failed);
            }
            else {
                $r->{split_strategy} = get_split_strategy($r);
                my $problem = $judge->get_problem($r->{problem_id});

                if (_is_competitive_run($problem->{run_method}) ||
                    $r->{type} == $cats::job_type_submission_part ||
                    $r->{split_strategy}->{method} eq $cats::split_none) {
                        test_problem($r, $problem);
                }
                elsif (!$judge->can_split) {
                    # TODO: move to JudgeDB
                    log_msg("Can't split solution. Queue limit reached or local judge\n");
                    test_problem($r, $problem);
                }
                else {
                    my $state = split_solution($r);
                    if ($state) {
                        $judge->set_request_state($r, $state, $current_job_id);
                        $judge->finish_job($r->{job_id}, determine_job_state($state))
                            if $state != $cats::st_testing;
                    }
                    else {
                        test_problem($r, $problem);
                    }
                }
            }
        }
    }
}

$cli->parse;

eval {
    $cfg->load(
        file => $cli->opts->{'config-file'} || $CATS::Judge::ConfigFile::main,
        override => $cli->opts->{'config-set'});

    my $cfg_confess = $cfg->confess // '';
    $SIG{__WARN__} = sub { log_msg($cfg_confess =~ /w/i ? longmess(@_) : shortmess(@_)) };
    $SIG{__DIE__} = \&confess if $cfg_confess =~ /d/i;
    1;
} or terminate $@;

if ($cli->command eq 'config') {
    if ($cli->opts->{print}) {
        $cfg->print_params($cli->opts->{print}, $cli->opts->{bare});
    }
    else {
        say $cfg->apply_defines($cli->opts->{apply});
    }
    exit;
}

$fu->ensure_dir($cfg->cachedir, 'cachedir');
$fu->ensure_dir($cfg->solutionsdir, 'solutions');
$fu->ensure_dir($cfg->logdir, 'logdir');
$fu->ensure_dir($cfg->rundir, 'rundir');

$log->init($cfg->logdir, max_dump_size => $cfg->log_dump_size);

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
    eval { require "CATS/Judge/$api.pm"; 1; } or terminate "Can't load $api module: $@";
    no strict 'refs';
    $judge = "CATS::Judge::$api"->new_from_cfg($cfg);
}
else {
    terminate "Unknown api '$api'";
}

$problem_cache = CATS::Judge::ProblemCache->new(
    cfg => $cfg, fu => $fu, log => $log, judge => $judge);

$judge->auth;
$judge->set_DEs($cfg->DEs);

{
    my $cfg_dirs = {};
    $cfg_dirs->{$_} = $cfg->{$_} for $cfg->dir_fields;

    my $sp_define = $cfg->defines->{'#spawner'}
        or terminate 'No #spawner define in config';
    $sp = CATS::Spawner::Default->new({
        %$cfg,
        logger => $log,
        path => CATS::Judge::Config::apply_params($sp_define, $cfg_dirs),
        run_dir => $cfg->rundir,
        json => 1,
    });
}

$src_proc = CATS::Judge::SourceProcessor->new(
    cfg => $cfg, fu => $fu, log => $log, sp => $sp);

sub make_backend() {
    CATS::Backend->new(
        log => $log,
        cfg => $cfg,
        system => $judge->{system},
        problem => $judge->{problem},
        parser => $judge->{parser},
        verbose => $judge->{verbose},
        url => $judge->{url},
        judge => $judge,
    )
}

if ($cli->command =~ /^(download|upload)$/) {
    make_backend->sync_problem($cli->command);
}
elsif ($cli->command =~ /^list$/) {
    make_backend->list;
}
elsif ($cli->command =~ /^(clear-cache)$/) {
    $problem_cache->remove_current;
}
elsif ($cli->command =~ /^(hash)$/) {
    print '$sha$' . sha1_hex(read_lines_for_hash($cli->opts->{file}));
}
elsif ($cli->command =~ /^(install|run)$/) {
    for my $rr (@{$cli->opts->{run} || [ '' ]}) {
        my $wd = Cwd::cwd();
        $judge->{run} = $rr;
        $judge->set_def_DEs($cfg->def_DEs);
        my $r = $judge->select_request;
        my $state = prepare_problem($r);
        my $problem = $judge->get_problem($r->{problem_id});
        test_problem($r, $problem) if $r && ($r->{src} // '') ne '' && $state != $cats::st_unhandled_error;
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
