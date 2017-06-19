package CATS::Judge::ProblemCache;

use strict;
use warnings;

use Encode;

use CATS::FileUtil;
use CATS::SourceManager;

my $ext = 'des';

sub new {
    my ($class) = shift;
    my $self = { @_ };
    bless $self, $class;
    $self->cfg && $self->fu && $self->log && $self->judge or die;
    $self;
}

sub cfg { $_[0]->{cfg} }
sub fu { $_[0]->{fu} }
sub log { $_[0]->{log} }
sub judge { $_[0]->{judge} }

sub save_description {
    my ($self, $pid, $title, $date, $state) = @_;
    $self->fu->write_to_file([ $self->cfg->cachedir,  "$pid.$ext" ],
        join "\n", 'title:' . Encode::encode_utf8($title), "date:$date", "state:$state");
}

sub is_ready {
    my ($self, $pid) = @_;

    open my $pdesc, '<', CATS::FileUtil::fn([ $self->cfg->cachedir, "$pid.$ext" ]) or return 0;

    my $title = <$pdesc>;
    my $date = <$pdesc>;
    my $state = <$pdesc>;

    $state eq 'state:ready' or return 0;

    # Emulate old CATS_TO_EXACT_DATE format.
    $date =~ m/^date:(\d+)-(\d+)-(\d+)\s(.+)$/ or return 0;
    $date = "$3-$2-$1 $4";
    $self->judge->is_problem_uptodate($pid, $date);
}

sub clear_current {
    my ($self) = @_;

    my $path = CATS::FileUtil::fn([ $self->cfg->cachedir, $self->judge->{problem} ]);
    my $problem_id = -f "$path.$ext" || -d $path ?
        $self->judge->{problem} : $self->judge->select_request->{problem_id} or return;

    for (CATS::SourceManager::get_guids_by_regexp('*', $self->cfg->modulesdir)) {
        my $m = eval { CATS::SourceManager::load($_, $self->cfg->modulesdir); } or next;
        $self->log->warning("Orphaned module: $_")
            if $m->{path} =~ m~[\/\\]\Q$problem_id\E[\/\\]~;
    }
    $self->log->clear_dump;
    # Remove both description file and directory.
    $self->fu->remove([ $self->cfg->cachedir, "$problem_id*" ]) or return;
    $self->log->msg("problem '$problem_id' cache removed\n");
}

1;
