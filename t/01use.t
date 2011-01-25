
use strict;
use warnings;
use Test::More tests => 9;

use_ok('Monitoring::Check::SQL');
use_ok('Monitoring::Check::SQL::App');


{
    no warnings;
    *Monitoring::Check::SQL::App::msg_verbose = sub  {
        my $self = shift;
        my $level = shift;
        my $format = shift;
        return if $self->getopt->get_verbose() == 0;

        if ( $self->getopt->get_verbose() >= $level ){
            note sprintf '[check_sql:VERBOSE:%2s] ' . $format . "\n" ,$level,@_;
        }
        return;
    }
}

# Check config merge
{
    local @ARGV = (
        '--config_path' => 't/data/config_merge/a',
        '--config_path' => 't/data/config_merge/b',
        '--config_name' => 'test_config',
    );
    # push @ARGV, '-vvvvv' if defined $ENV{TEST_VERBOSE} && $ENV{TEST_VERBOSE};

    my $app = Monitoring::Check::SQL::App->new_with_options();
    is($app->config()->{filename},'b/test_config.ini','Check config merge')
}

{
    my @default_argv = (
        '--config_path' => 't/data/',
        '--connection'  => 'sqlite',
        't1',
    );
    push @default_argv, '-vvvvv' if defined $ENV{TEST_VERBOSE} && $ENV{TEST_VERBOSE};

# row count mode
    local @ARGV = @default_argv;
    push @ARGV, '--mode' => 'row_count';
    my $app = Monitoring::Check::SQL::App->new_with_options();
    $app->dbh->do(q{CREATE TABLE t1( name TEXT, check_sql_status TEXT )});
    my ($exit,$msg) = $app->run();
    is($exit,0,'Exit code 0 for Ok - ' . $msg);

    local @ARGV = @default_argv;
    push @ARGV, '--mode' => 'row_count';
    $app->new_with_options();
    $app->dbh->do(q{INSERT INTO t1 VALUES ("Row1","OK")});
    ($exit,$msg) = $app->run();
    is($exit,2,'Exit code 2 for CRITICAL - ' . $msg);

# row count mode with range...
    # local @ARGV = @default_argv;
    # push @ARGV, '--mode' => 'row_count';
    # push @ARGV, '--critical' => '2:3';
    # push @ARGV, '--warning'  => '4:5';
    # 
    # $app->new_with_options();
    # ($exit,$msg) = $app->run();
    # is($exit,0,'Exit code 0 for OK - ' . $msg);
    # 
    # $app->dbh->do(q{INSERT INTO t1 VALUES ("Row2","OK")});
    # ($exit,$msg) = $app->run();
    # is($exit,2,'Exit code 2 for CRITICAL - ' . $msg);
    # 
    # $app->dbh->do(q{INSERT INTO t1 VALUES ("Row3","OK")});
    # ($exit,$msg) = $app->run();
    # is($exit,2,'Exit code 2 for CRITICAL - ' . $msg);
    # 
    # $app->dbh->do(q{INSERT INTO t1 VALUES ("Row4","OK")});
    # ($exit,$msg) = $app->run();
    # is($exit,1,'Exit code 1 for WARNING - ' . $msg);
    # 
    # $app->dbh->do(q{INSERT INTO t1 VALUES ("Row5","OK")});
    # ($exit,$msg) = $app->run();
    # is($exit,1,'Exit code 1 for WARNING - ' . $msg);
    # 
    # $app->dbh->do(q{INSERT INTO t1 VALUES ("Row6","OK")});
    # ($exit,$msg) = $app->run();
    # is($exit,0,'Exit code 0 for OK - ' . $msg);

# row status
    local @ARGV = @default_argv;
    push @ARGV, '--mode' => 'row_status';
    $app->new_with_options();
    $app->dbh->do(q{INSERT INTO t1 VALUES ("Row1","OK")});
    ($exit,$msg) = $app->run();
    is($exit,0,'Exit code 0 for OK - ' . $msg);

    $app->dbh->do(q{INSERT INTO t1 VALUES ("Row2","WARNING")});
    ($exit,$msg) = $app->run();
    is($exit,1,'Exit code 1 for WARNING - ' . $msg);

    $app->dbh->do(q{INSERT INTO t1 VALUES ("Row3","CRITICAL")});
    ($exit,$msg) = $app->run();
    is($exit,2,'Exit code 2 for CRITICAL - ' . $msg);

    $app->dbh->do(q{INSERT INTO t1 VALUES ("Row3","UNKNOWN")});
    ($exit,$msg) = $app->run();
    is($exit,3,'Exit code 3 for UNKNOWN - ' . $msg);

}

