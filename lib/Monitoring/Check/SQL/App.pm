package Monitoring::Check::SQL::App;

use strict;
use warnings;
use Config::Any;
use Getopt::Lucid ();
use Pod::Usage;
use Text::TabularDisplay;
use DBI;

sub OK       { return 0 };
sub WARNING  { return 1 };
sub CRITICAL { return 2 };
sub UNKNOWN  { return 3 };

sub id_to_name {
    my ($self,$name) = @_;
    my %map = (
        0 => 'OK',
        1 => 'WARNING',
        2 => 'CRITICAL',
        3 => 'UNKNOWN',
    );
    return ( defined $map{$name} ) ? $map{$name} : 'UNKNOWN';
}

sub name_to_id {
    my ($self,$name) = @_;
    my %map = (
        'OK'       => 0,
        'WARNING'  => 1,
        'CRITICAL' => 2,
        'UNKNOWN'  => 3,
    );
    return ( defined $map{$name} ) ? $map{$name} : 3;
}

sub new {
    my $class = shift;
    if ( ref $class ){ return $class; }; # don't rebless...
    my $self  = {};
    bless $self, $class;
    return $self;
}

sub new_with_options {
    my $self = new(@_);

    my @specs = (
        Getopt::Lucid::Switch("help|h"),
        Getopt::Lucid::Counter("verbose|v"),
        Getopt::Lucid::List("config_path"),
        Getopt::Lucid::Param("config_name")->default('check_sql'),
        Getopt::Lucid::Param("connection|C"),

        # --mode [row_count|row_status]
        Getopt::Lucid::Param("mode|m"),
        #     
        # # range (format: start:end). Alert if outside this range
        # Getopt::Lucid::Param("critical|c"),
        # Getopt::Lucid::Param("warning|w"),
    );
    $self->{_getopt} = Getopt::Lucid->getopt( \@specs );

    return $self;
}

sub getopt { return shift->{_getopt} };

sub msg_verbose {
    my $self = shift;
    my $level = shift;
    my $format = shift;
    return if $self->getopt->get_verbose() == 0;

    if ( $self->getopt->get_verbose() >= $level ){
        printf '[check_sql:VERBOSE:%2s] ' . $format . "\n" ,$level,@_;
    }
    return;
}

sub run {
    my $self = shift;

    if ( $self->getopt->get_help ){
        pod2usage(
            -input => __FILE__,
            -verbose => 99,
            -exitval => 0,
            -sections => ['NAME','VERSION','SYNOPSIS','OPTIONS']
        );
    }

    unless ( $self->getopt->get_connection ) {
        die "Please set --connection / -C <connection_name>";
    }

    unless ( $self->getopt->get_mode ) {
        die "Please set --mode / -m [row_count|row_status]";
    }

    unless ( defined $self->{_object} or $self->{_object} = shift @ARGV ){
        die "No object given.";
    }

    return $self->_check_sql();
}

sub run_exit {
    my $self = shift;
    my ($exit_code, $msg) = $self->run();
    printf("%s - %s\n",$self->id_to_name($exit_code),$msg);
    exit $exit_code;
}

#
# Check
#
##########################################################################

sub object { return shift->{_object} };

sub _build_sql {
    my $self = shift;
    my $sql = '';
    if ( -f $self->object ){
        $self->msg_verbose(5,"Read sql file: %s", $self->object);
        # Slurp file...
        # TODO: Bettering error handling / Nagios output!
        open( my $fh, $self->object ) or die "Can't open " . $self->object;
        $sql = do { local( $/ ) ; <$fh> } ;
        close $fh;
    }else{
        $sql = sprintf("SELECT * FROM %s",$self->object);
        $self->msg_verbose(5,"SQL: %s", $sql);
    }
    return $sql;
}


sub _exec_sql {
    my $self = shift;
    my $sth = $self->dbh->prepare($self->_build_sql());
    $sth->execute();
    my $check_result = $sth->fetchall_arrayref({});
    my $check_result_fields = [ map { lc($_) } @{$sth->{NAME}}];

    return wantarray ? ( $check_result, $check_result_fields) : $check_result;
}

sub dbh {
    my $self = shift;
    return $self->{_dbh} if ( defined $self->{_dbh} );
    $self->msg_verbose(5,
        "Connect to: %s as %s",
        $self->connection->{connect_info}->[0],
        $self->connection->{connect_info}->[1]
    );
    $self->{_dbh} = DBI->connect( @{ $self->connection->{connect_info} } );
    $self->{_dbh}->{FetchHashKeyName} = 'NAME_lc'; # lowercase all column names
    return $self->{_dbh};
}

sub _check_sql {
    my $self = shift;
    if ( $self->getopt->get_mode() eq 'row_count' ){
        return $self->_check_sql_row_count();
    }elsif ( $self->getopt->get_mode() eq 'row_status' ){
        return $self->_check_sql_row_status();
    }
    return (UNKNOWN,sprintf("Unknown mode: %s",$self->getopt->get_mode()));
}

sub _check_sql_row_status {
    my $self = shift;
    my ($data,$fields) = $self->_exec_sql();
    my $max_status = 0;
    my $table = Text::TabularDisplay->new(@$fields);

    foreach my $row (@{$data}){
        unless ( defined $row->{check_sql_status} ){
            return (UNKNOWN,"Can't found check_sql_status column");
        }
        $table->add(map {$row->{$_}} @$fields);
        if ( $self->name_to_id( $row->{check_sql_status} ) > $max_status ){
            $max_status = $self->name_to_id( $row->{check_sql_status} );
        }
    }
    return ($max_status,sprintf("Checked: %s\n\n%s\n",$self->object,$table->render));
}

sub _check_sql_row_count {
    my $self = shift;
    # my ($cri_min,$cri_max) = split(':',shift || $self->getopt->get_critical());
    # my ($war_min,$war_max) = split(':',shift || $self->getopt->get_warning());
    my ($data,$fields) = $self->_exec_sql();

    my $table = Text::TabularDisplay->new(@$fields);
    foreach my $row (@{$data}){
        $table->add(map {$row->{$_}} @$fields);
    }

    my $row_count = scalar @{ $data };
    my $output = sprintf("Row count: %s - Checked: %s\n\n%s\n",$row_count,$self->object,$table->render);
    # {
    #     no warnings;
    #     $self->msg_verbose(5,
    #         "Row count: %s | Critical min:%d max:%d | Warning min:%d max:%d",
    #         $row_count,$cri_min,$cri_max,$war_min,$war_max
    #     )
    # }

    # No range given
    # if (    ! defined $cri_min 
    #     &&  ! defined $cri_max 
    #     &&  ! defined $war_min
    #     &&  ! defined $war_max
    # ){
        if ( $row_count > 0 ){
            return (CRITICAL,$output);
        }else{
            return (OK,$output);
        }
    # }
    # 
    # if ( $self->_in_range($row_count,$cri_min,$cri_max) == 1 ){
    #         return (CRITICAL,sprintf("Row count: %d in cirical range: %d:%d",$row_count,$cri_min,$cri_max || -1));
    # }else{
    #     if ( $self->_in_range($row_count,$war_min,$war_max) == 1 ){
    #         return (WARNING,sprintf("Row count: %d in warning range: %d:%d",$row_count,$war_min,$war_max || -1));
    #     }
    # }
    # 
    # return (OK,sprintf("range unknown for row count: %d",$row_count));
}

# sub _in_range {
#     my ($self,$count,$min,$max) = @_;
#     if ( $min && $max ){
#         if ( $count >= $min && $count <= $max  ){
#             return 1;
#         }else{
#             return 0;
#         }
#     }elsif( $min ){
#         if ( $count > $min ){
#             return 1;
#         }else{
#             return 0;
#         }
#     }
#     return 0;
# }
#
#  Config 
#
##########################################################################

sub connection {
    my $self = shift;
    my $connection = $self->config->{connections}->{ $self->getopt->get_connection };
    unless ( defined $connection ){
        # TODO: Bettering error handling / Nagios output!
        die "No connection config found for: " . $self->getopt->get_connection;
    }
    unless ( defined $connection->{connect_info}){
        # TODO: Bettering error handling / Nagios output!
        die "No connect_info for connection found : ". $self->getopt->get_connection;
    }
    return $connection;
}

sub config {
    my $self = shift;
    return $self->{_config} if defined $self->{_config};

    return $self->{_config} = $self->_read_config();
}


sub _read_config {
    my $self = shift;
    my $config_path = ['/etc/','.',$ENV{HOME}];
    if ( $self->getopt->get_config_path() ){
        $config_path = [$self->getopt->get_config_path()];
    }
    my $config_name = $self->getopt->get_config_name();
    $self->msg_verbose(3,
        "Read config from paths %s with name %s.*",
        join(', ',@$config_path),
        $config_name
    );

    my $config_any;
    {
        # Ignore warnings from any Config::.* modules
        local $SIG{__WARN__} = sub {};
        $config_any = Config::Any->load_stems({
            stems           => [map { $_ . '/' . $config_name } @$config_path],
            use_ext         => 1,
        });
    }

    my $config = {};
    foreach my $config_obj ( @$config_any ){
        foreach my $config_file ( keys %$config_obj ){
            $self->msg_verbose(5,"Process/Merge config file %s",$config_file);
            $config = $self->_merge_hashes($config,$config_obj->{$config_file});
        }
    }
    return $config;
}

sub _merge_hashes {
    my ( $self, $lefthash, $righthash ) = @_;

    return $lefthash unless defined $righthash;

    my %merged = %$lefthash;
    for my $key ( keys %$righthash ) {
        my $right_ref = ( ref $righthash->{ $key } || '' ) eq 'HASH';
        my $left_ref  = ( ( exists $lefthash->{ $key } && ref $lefthash->{ $key } ) || '' ) eq 'HASH';
        if( $right_ref and $left_ref ) {
            $merged{ $key } = $self->_merge_hashes(
                $lefthash->{ $key }, $righthash->{ $key }
            );
        }
        else {
            $merged{ $key } = $righthash->{ $key };
        }
    }

    return \%merged;
}

1;
__END__
=head1 NAME

Monitoring::Check::SQL::App - check_sql.pl

=head1 SYNOPSIS

    ./bin/check_sql.pl [options] [sql_object|sql_file]

=head1 OPTIONS

=head2 B<--help|-h>

Print a brief help message and exits.

=head2 B<-v>

Verbose mode, more v more output...

=head2 B<--config_name>

=over 4

=item Default: check_sql

=back

=head2 B<--config_path>

=over 4

=item Defaults: '/etc/', '.', $ENV{HOME}

=back


=head1 METHODS

=over 4

=item new_with_options

=item getopt

Returns the L<Getopt::Lucid> object.

=item msg_verbose

Print message at any time to STDERR.

=item run

=item merge_hashes($hashref, $hashref)

Base code to recursively merge two hashes together with right-hand precedence.

=back

=head1 COPYRIGHT & LICENSE

Copyright 2010 Robert Bohne.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.

=head1 AUTHOR

Robert Bohne, C<< <rbo at cpan.org> >>