# (c) 2023 Martin Frederic

use strict;
use warnings;

use v5.18;

use File::Spec::Functions qw{catdir catfile};
use IPC::Open3 qw{open3};
use Symbol qw{gensym};

sub system_read(@) {
  my @cmd = @_;

  my $stdin  = gensym;
  my $stdout = gensym;
  my $stderr = gensym;

  my $pid = open3($stdin, $stdout, $stderr, @cmd);
  waitpid($pid, 0);

  my $status = $? >> 8;

  return ($status, $stdout);
}

sub read_config($) {
  my $fn = shift;

  my %conf;

  open(my $fh, '<:encoding(UTF-8)', $fn) or die "could not open $fn: $!";
  while (my $line = <$fh>) {
    chomp $line;

    my ($k, $v) = split /\s*?=\s*/, $line, 2;
    $conf{$k} = $v;
  }
  close $fh or die "could not close $fn: $!";

  my @required = qw{local_repo
                    github_repo
                    mock_repo
                    readme_template
                    git_name
                    git_email};

  for my $r (@required) {
    if (!exists($conf{$r})) {
      die "$fn: missing required key: $r\n";
    }

    if ($conf{$r} =~ /^\s*$/) {
      die "$fn: key empty: $r\n";
    }
  }

  return \%conf;
}

sub init_mock_repo($$$) {
  my $dn        = shift;
  my $git_name  = shift;
  my $git_email = shift;

  my $git_dir = catdir($dn, '.git');
  print "init mock repo: $dn ($git_dir)\n";

  if (-e -d $git_dir) {
    # This repo has already been initialized.
    print "repo already exists\n";
    return;
  }

  if (!(-e -d $dn)) {
    mkdir($dn) or die $!;
  }

  # This repo has not been initialized, so do that now.
  system(git => '-C', $dn,
                'init')
      == 0 or die $!;

  # Set up credentials
  system(git => '-C', $dn,
                'config', 'user.name',
                $git_name);
  system(git => '-C', $dn,
                'config', 'user.email',
                $git_email);
}

sub read_commits($;$) {
  my $repo_dn   = shift;
  my $read_last = shift;

  my @log_args = (
    # abbreviated hash, iso date and subject
    '--format=format:%h %aI %s'
  );

  if (defined $read_last) {
    push @log_args, '-1';
  }

  my ($status, $stdout_fh) = system_read(
    git => '-C', $repo_dn,
           '--no-pager',
           'log', @log_args);

  my @commits;

  if ($status != 0) {
    return @commits;
  }

  while (my $line = <$stdout_fh>) {
    chomp $line;
    my ($hash, $timestamp, $message) = split / /, $line, 3;
    push @commits, [$hash, $timestamp, $message];
  }

  return @commits;
}

sub read_last_commit($) {
  my $repo_dn = shift;

  my @results = read_commits($repo_dn, 1);
  if (@results) {
    return $results[0];
  } else {
    return '';
  }
}

sub make_readme($$) {
  my $template_fn = shift;
  my $commit      = shift;

  open(my $template_fh, '<:encoding(UTF-8)', $template_fn)
      or die "could not open $template_fn: $!";
  my $template = do {
    local $/ = undef;
    <$template_fh>;
  };
  close($template_fh) or die "could not close $template_fn: $!";

  $template =~ s/%COMMIT_HASH%/$commit->[0]/;
  $template =~ s/%COMMIT_SUBJECT%/$commit->[2]/;
  return $template;
}

sub mock_commit($$$) {
  my $repo_dn     = shift;
  my $template_fn = shift;
  my $commit      = shift;

  print "creating mock commit for [$commit->[0]] $commit->[2]\n";

  # generate readme text
  my $readme_txt = make_readme($template_fn, $commit);

  # write readme
  my $readme_fn = catfile($repo_dn, 'README.md');
  open(my $readme_fh, '>:encoding(UTF-8)', $readme_fn)
      or die "could not open $readme_fn: $!";
  print $readme_fh $readme_txt;
  close($readme_fh) or die "could not close $readme_fn: $!";

  # add file to commit
  system(git => '-C', $repo_dn,
                'add', 'README.md') == 0 or die "could not add README.md to commit";

  # prepare the commit message
  my $commit_message = "a boring commit message [$commit->[0]]";

  # do that commit!
  system(git => '-C', $repo_dn,
                'commit',
                '-m', $commit_message,
                '--date', $commit->[1]) == 0 or die "could not do commit";
}

# "last_mock_commit" indicates the commit in the mock repo.
# "local_commits" contain all commits of the original repo.
# We want to return the commits that have not been mocked yet.
sub find_pending_commits($$) {
  my $local_commits    = shift;
  my $last_mock_commit = shift;

  # The mock commit's message includes the matching commit's
  # hash in square brackets.
  my $mock_hash;
  my $mock_message = $last_mock_commit->[2];
  if ($mock_message =~ / \[ ([a-z0-9]+) \] /x) {
    $mock_hash = $1;
    print "found mock hash: $mock_hash\n";
  } else {
    die "could not find mock hash in commit message: $mock_message\n";
  }

  my $sync_point = undef;
  while (my ($i, $commit) = each @$local_commits) {
    if ($commit->[0] eq $mock_hash) {
      $sync_point = $i;
      last;
    }
  }
  if (!defined($sync_point)) {
    die "could not find mock hash in local commits :(\n";
  }

  my @pending = @$local_commits;
  splice(@pending, $sync_point);

  return @pending;
}

sub main {
  if (!@ARGV) {
    die "Needs path to repo config.\n";
  }

  my $conf_fn = $ARGV[0];
  my $conf = read_config($conf_fn);

  my $ok;

  init_mock_repo($conf->{mock_repo},
                  $conf->{git_name}, $conf->{git_email});

  # Fetch local commits
  my @local_commits = read_commits($conf->{local_repo});

  # Fetch mock commits
  my $last_mock_commit = read_last_commit($conf->{mock_repo});

    use DDP;

  my @pending_commits;
  if ($last_mock_commit) {
    @pending_commits = find_pending_commits(\@local_commits,
                                            $last_mock_commit);
  } else {
    @pending_commits = @local_commits;
  }

  print "creating " . scalar(@pending_commits) . " mock commits ";
  print "(" . scalar(@local_commits) . " total)\n";

  # We need to create commits from oldest-to-newest
  @pending_commits = reverse @pending_commits;

  # Create mock commits
  for my $commit (@pending_commits) {
    mock_commit($conf->{mock_repo}, $conf->{readme_template}, $commit);
  }

  # TODO: maybe use random phrases
}

main;
