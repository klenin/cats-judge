package CATS::Backend;

use strict;
use warnings;

use CATS::Backend::CATS;
use CATS::Backend::Polygon;

sub new {
    my ($class, %p) = @_;
    exists $p{$_} or die "$_ required" for qw(cfg log system parser problem verbose url judge);
    bless { %p }, $class;
}

sub log { $_[0]->{log} }
sub cfg { $_[0]->{cfg} }

sub interactive_login {
    my ($self) = @_;
    eval { require Term::ReadKey; 1; } or $self->log->error('Term::ReadKey is required for interactive login');
    print 'login: ';
    chomp(my $login = <>);
    print 'password: ';
    Term::ReadKey::ReadMode('noecho');
    chomp(my $password = <>);
    print "\n";
    Term::ReadKey::ReadMode('restore');
    ($login, $password);
}

sub get_system {
    my ($self) = @_;
    if ($self->{system}) {
        $self->{system} =~ m/^(cats|polygon)$/ or $self->log->error('bad option --system');
        return $self->{system};
    }
    for (qw(cats polygon)) {
        my $u = $self->cfg->{$_ . '_url'};
        return $_ if $self->{url} =~ /^\Q$u\E/;
    }
    die 'Unable to determine system from --system and --url options';
}

sub make_backend {
    my ($self, $problem_exists) = @_;
    my $system = $self->get_system;
    $problem_exists and $self->{judge}->select_request;
    my $root = $system eq 'cats' ? $self->cfg->cats_url : $self->cfg->polygon_url;
    ('CATS::Backend::' . ($system eq 'cats' ? 'CATS' : 'Polygon'))->new(
        $self->{parser}{problem}, $self->log, $self->{problem} // '', $self->{url},
        $problem_exists, $root, $self->cfg->{proxy}, $self->{verbose});
}

sub sync_problem {
    my ($self, $action) = @_;
    my $problem_exists = -d $self->{problem} || -f $self->{problem};
    my $backend = $self->make_backend($problem_exists);
    $backend->login($self->interactive_login) if $backend->needs_login;
    $backend->start;
    $self->log->msg('%s problem %s ... ',
        ($action eq 'upload' ? 'Uploading' : 'Downloading'), ($self->{problem} || 'by url'));
    $action eq 'upload' ? $backend->upload_problem : $backend->download_problem;
    $problem_exists or $self->{problem} .= '.zip';
    $self->log->note('ok');
}

sub list {
    my ($self) = @_;
    my $backend = $self->make_backend(0);
    $backend->login($self->interactive_login) if $backend->needs_login;
    $backend->start;
    $backend->list;
}

1;
