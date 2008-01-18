# $Id: MySQL.pm 1480 2007-12-04 19:29:23Z augie $
# Provides an interface to manipulate PowerDNS data in the MySQL Backend.

package PowerDNS::Backend::MySQL;

use DBI;
use strict;
use warnings;

=head1 NAME

PowerDNS::Backend::MySQL - Provides an interface to manipulate PowerDNS data in the MySQL Backend.

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';

=head1 SYNOPSIS

	use PowerDNS::Backend::MySQL;

	# Setting parameters and their default values.
	my $params = {	db_user			=>	'root',
			db_pass			=>	'',
			db_name			=>	'pdns',
			db_port			=>	'3306',
			db_host			=>	'localhost',
			mysql_print_error	=>	1,
			mysql_warn		=>	1,
			mysql_auto_commit	=>	1,
			mysql_auto_reconnect	=>	1,
	};

	my $pdns = PowerDNS::Backend::MySQL->new($params);

=head1 DESCRIPTION

	PowerDNS::Backend::MySQL provides a layer of abstraction 
	for manipulating the data stored in the PowerDNS MySQL backend.

=head1 METHODS

=head2 new(\%params)

	my $params = {	db_user			=>	'root',
			db_pass			=>	'',
			db_name			=>	'pdns',
			db_port			=>	'3306',
			db_host			=>	'localhost',
			mysql_print_error	=>	1,
			mysql_warn		=>	1,
			mysql_auto_commit	=>	1,
			mysql_auto_reconnect	=>	1,
	};

	my $pdns = PowerDNS::Backend::MySQL->new($params);

	Creates a PowerDNS::Backend::MySQL object.

=over 4 

=item db_user

The DB user to use when connecting to the MySQL Backend.

=item db_pass

The DB password to use when connecting to the MySQL Backend.

=item db_name

The DB name to use when connecting to the MySQL Backend.

=item db_port

The DB port to use when connecting to the MySQL Backend.

=item db_host

The DB host to use when connecting to the MySQL Backend.

=item mysql_print_error

Used to set the DBI::PrintError value.

=item mysql_warn

Used to set the DBI::Warn value.

=item mysql_auto_commit

Used to set the DBI::AutoCommit value.

=item mysql_auto_reconnect

Used to set the DBD::mysql::mysql_auto_reconnect value.

=back

=cut

sub new
{
	my $class = shift;
	my $params= shift;
	my $self  = {};

	bless $self , ref $class || $class;
	
	my $db_user = defined $params->{db_user} ? $params->{db_user} : 'root';
	my $db_pass = defined $params->{db_pass} ? $params->{db_pass} : '';
	my $db_name = defined $params->{db_name} ? $params->{db_name} : 'pdns';
	my $db_port = defined $params->{db_port} ? $params->{db_port} : '3306';
	my $db_host = defined $params->{db_host} ? $params->{db_host} : 'localhost';

	my $mysql_print_error = $params->{mysql_print_error} ? defined $params->{mysql_print_error} : 1;
	my $mysql_warn = $params->{mysql_warn} ? defined $params->{mysql_warn} : 1;
	my $mysql_auto_commit = $params->{mysql_auto_commit} ? defined $params->{mysql_auto_commit} : 1;

	my $mysql_auto_reconnect = $params->{mysql_auto_reconnect} ? defined $params->{mysql_auto_reconnect} : 1;

	my $db_DSN  = "DBI:mysql:database=$db_name;host=$db_host;port=$db_port";

	$self->{'dbh'} = DBI->connect($db_DSN, $db_user, $db_pass, 
		{
			'PrintError' => $mysql_print_error,
			'Warn' => $mysql_warn, 
			'AutoCommit' => $mysql_auto_commit,
		});
	$self->{'dbh'}->{'mysql_auto_reconnect'} = $mysql_auto_reconnect;
	
	$self->{'error_msg'} = undef;

	return $self;
}

sub DESTROY
{
	my $self = shift;
	$self->{'dbh'}->disconnect or warn $self->{'dbh'}->errstr;
}

=head2 add_domain(\$domain)

Expects a scalar reference domain name to add to the DB.
Returns 1 on success and 0 on failure.

=cut

sub add_domain($) 
{
	my $self = shift;
	my $domain = shift;
	
	my $sth = $self->{'dbh'}->prepare("INSERT INTO domains (name,type) VALUES (?,'NATIVE')");
	$sth->execute($$domain) or return 0;

	return 1;
}

=head2 add_slave(\$slave_domain , \$master_ip)

Expects two scalar references; first the domain to slave, then the IP address to 
slave from.
Returns 1 on success and 0 on failure.
Updates the existing record if there is one, otherwise inserts a new record.

=cut

sub add_slave($$)
{
	my $self   = shift;
	my $domain = shift;
	my $master = shift;
	my $sth;

	if ( $self->domain_exists($domain) )
	{
		$sth = $self->{'dbh'}->prepare("UPDATE domains set master = ? , type = 'SLAVE' WHERE name = ?");
	        if ( $sth->execute($$master,$$domain) != 1 ) { return 0; }
	}
	else
	{
		$sth = $self->{'dbh'}->prepare("INSERT INTO domains (name,master,type) VALUES(?,?,'SLAVE')");
	        if ( $sth->execute($$domain,$$master) != 1 ) { return 0; }
	}

	return 1;
}

=head2 delete_domain(\$domain)

Expects a scalar reference domain name to delete from the DB.
Returns 1 on success and 0 on failure.

=cut

sub delete_domain($) 
{
	my $self = shift;
	my $domain = shift;
		
	# Remove domain.
	my $sth = $self->{'dbh'}->prepare("DELETE FROM domains WHERE name = ?");
	if ( $sth->execute($$domain) != 1 ) { return 0; }
	
	return 1;
}

=head2 list_domain_names

Does not expect anything.
Returns a reference to an array which contains all the domain names 
listed in the PowerDNS backend.

=cut

sub list_domain_names
{
	my $self = shift;
	my @domains;

	# Grab the domain names.
	my $sth = $self->{'dbh'}->prepare("SELECT name FROM domains");
	$sth->execute;

	while ( my ($domain) = $sth->fetchrow_array )
	{ push @domains , $domain; }

	return \@domains;
}

=head2 list_slave_domain_names(\$master_ip)

Expects a scalar reference to an IP address which is the master IP.
Returns a reference to an array which contains all the slave domain names 
with $master as their 'master'.

=cut

sub list_slave_domain_names($)
{
	my $self = shift;
	my $master = shift;
	my @domains;

	# Grab the domain names.
	my $sth = $self->{'dbh'}->prepare("SELECT name FROM domains WHERE TYPE = 'SLAVE' AND master = ?");
	$sth->execute($$master);

	while ( my ($domain) = $sth->fetchrow_array )
	{ push @domains , $domain; }

	return \@domains;
}

=head2 domain_exists(\$domain)

Expects a scalar reference to a domain name to be found in the "domains" table.
Returns 1 if the domain name is found, and 0 if it is not found.

=cut

sub domain_exists($)
{
	my $self = shift;
	my $domain = shift;
	
	my $sth = $self->{'dbh'}->prepare("SELECT id FROM domains WHERE name = ?");
	$sth->execute($$domain) or return 0;
	
	my @record = $sth->fetchrow_array;
	
	$sth->finish;
	
	scalar(@record) ? return 1 : return 0;
}

=head2 list_records(\$rr , \$domain)

Expects two scalar references; the first to a resource record and the second to a domain name.
Returns a reference to a two-dimensional array which contains the resource record name and content if any.

=cut

sub list_records($$)
{
	my $self = shift;
	my $rr = shift;
	my $domain = shift;
	my @records;
	
	my $sth = $self->{'dbh'}->prepare("SELECT name,content FROM records WHERE type = ? and domain_id = (SELECT id FROM domains WHERE name = ?)");
	$sth->execute($$rr,$$domain);
	
	while ( my ($name,$content) = $sth->fetchrow_array )
	{ push @records , [ ($name,$content) ]; } # push anonymous array on to end.
	
	return \@records;
}

=head2 add_record(\$rr , \$domain)

Adds a single record to the backend.
Expects two scalar references; one to an array that contains the information for the
resource record (name, type, content, ttl, prio); name, type and content are required values.
The other scalar reference is the zone you want to add the RR to.
Returns 1 if the record was successfully added, and 0 if not.

=cut

sub add_record($$)
{
	my $self = shift;
	my $rr = shift;
	my $domain = shift;
	my ($name , $type , $content , $ttl , $prio) = @$rr;
	
	# Default values.
	if ( ! defined $ttl or $ttl eq '' ) { $ttl = 7200; }
	if ( ! defined $prio or $prio eq '' ) { $prio = 0; }
	
	my $sth = $self->{'dbh'}->prepare("INSERT INTO records (domain_id,name,type,content,ttl,prio) SELECT id,?,?,?,?,? FROM domains WHERE name = ?");
	$sth->execute($name,$type,$content,$ttl,$prio,$$domain) or return 0;
	
	return 1;
}

=head2 delete_record(\$rr , \$domain)

Deletes a single record from the backend.
Expects two scalar references; one to an array that contains the information for the
resource record (name, type, content); these are all required values.
The other scalar reference is the zone you want to delete the RR from.
Returns 1 if the record was successfully deleted, and 0 if not.

=cut

sub delete_record($$)
{
	my $self = shift;
	my $rr = shift;
	my $domain = shift;
	my ($name , $type , $content) = @$rr;
	
	my $sth = $self->{'dbh'}->prepare("DELETE FROM records WHERE name=? and type=? and content=? and domain_id = (SELECT id FROM domains WHERE name = ?) LIMIT 1");
	
	$sth->execute($name,$type,$content,$$domain) == 1 ? return 1 : return 0;
}

=head2 update_record(\$rr1 , \$rr2 , \$domain)

Updates a single record in the backend.
Expects three scalar references:
1) A reference to an array that contains the Resource Record to be updated;
   ($name , $type , $content) - all required.
2) A reference to an array that contains the updated values;
   ($name , $type , $content , $ttl , $prio) - only $name , $type , $content are required.
   Defaults for $ttl and $prio will be used if none are given.
3) The domain to be updated.
Returns 1 on a successful update, and 0 when un-successful.

=cut

sub update_record($$$)
{
	my $self = shift;
	my $rr1 = shift;
	my $rr2 = shift;
	my $domain = shift;
	my ($name1 , $type1 , $content1) = @$rr1;
	my ($name2 , $type2 , $content2 , $ttl , $prio) = @$rr2;
	
	# Default values.
	if ( ! defined $ttl or $ttl eq '' ) { $ttl = 7200; }
	if ( ! defined $prio or $prio eq '' ) { $prio = 0; }
	
	my $sth = $self->{'dbh'}->prepare("UPDATE records SET name=? , type=? , content=? , ttl=? , prio=? WHERE name=? and type=? and content=? and domain_id = (SELECT id FROM domains WHERE name = ?) LIMIT 1");
	
	# $rv is number of rows affected; it's OK for no rows to be affected; when duplicate data is being updated for example.
	my $rv = $sth->execute($name2,$type2,$content2,$ttl,$prio,$name1,$type1,$content1,$$domain);
	
	$rv ? return 1 : return 0;
}

=head2 find_record_by_content($$)

Finds a specific (single) record in the backend.
Expects two scalar references; the first is the content we are looking for, and the second is the domain to be checked.
Returns a reference to an array that contains the name and type from the found record, if any.

=cut

sub find_record_by_content($$)
{
	my $self = shift;
	my $content = shift;
	my $domain = shift;
	
	my $sth = $self->{'dbh'}->prepare("SELECT name,type FROM records WHERE content = ? and domain_id = (SELECT id FROM domains WHERE name = ?) limit 1");
	$sth->execute($$content,$$domain);
	
	 my @records = $sth->fetchrow_array;
	
	return \@records;
}

=head2 make_domain_native(\$domain)

Makes the specified domain a 'NATIVE' domain.
Expects one scalar reference which is the domain name to be updated.
Returns 1 upon succes and 0 otherwise.

=cut

sub make_domain_native($)
{
	my $self = shift;
	my $domain = shift;

	my $sth = $self->{'dbh'}->prepare("UPDATE domains set type='NATIVE' , master='' WHERE name=?");
	if ( $sth->execute($$domain) != 1 ) { return 0; }

	return 1;
}

=head2 get_domain_type(\$domain)

Expects one scalar reference which is the domain name to query for.
Returns a string containing the PowerDNS 'type' of the domain given or
an empty string if the domain does not exist in the PowerDNS backend.

=cut

sub get_domain_type($)
{
	my $self = shift;
	my $domain = shift;
	my $type = '';

	my $sth = $self->{'dbh'}->prepare("SELECT type FROM domains WHERE name = ?");
	$sth->execute($$domain);

	($type) = $sth->fetchrow_array;
	return $type;
}

=head2 get_master(\$domain)

Expects one scalar reference which is the domain name to query for.
Returns a string containing the PowerDNS 'master' of the domain given or
an empty string if the domain does not exist in the PowerDNS backend or
has no master (i.e. a NATIVE domain).

=cut

sub get_master($)
{
	my $self   = shift;
	my $domain = shift;
	my $master = '';

	my $sth = $self->{'dbh'}->prepare("SELECT master FROM domains WHERE name = ?");
	$sth->execute($$domain);

	($master) = $sth->fetchrow_array;
	return $master;
}

1;

=head1 EXAMPLES

	my $params = {	db_user			=>	'root',
			db_pass			=>	'',
			db_name			=>	'pdns',
			db_port			=>	'3306',
			db_host			=>	'localhost',
			mysql_print_error	=>	1,
			mysql_warn		=>	1,
			mysql_auto_commit	=>	1,
			mysql_auto_reconnect	=>	1,
	};

	my $pdns = PowerDNS::Backend::MySQL->new($params);

	my $domain = 'example.com';
	my $master = '127.0.0.1';

	unless ( $pdns->add_domain(\$domain) )
        { print "Could not add domain : $domain \n"; }

	unless ( $pdns->add_slave(\$domain,\$master) )
        { print "Could not add slave domain : $domain \n"; }

	unless ( $pdns->delete_domain(\$domain) )
	{ print "Could not delete domain : $domain \n"; }

	my $domain_names = $pdns->list_domain_names;

	for my $domain (@$domain_names)
	{ print "$domain \n"; }

	my $master = '127.0.0.1';
	my $domain_names = $pdns->list_slave_domain_names(\$master);

	for my $domain (@$domain_names)
	{ print "$domain \n"; }
	
	if ( $pdns->domain_exists(\$domain) )
	{ print "The domain $domain does exist. \n"; }
	else
	{ print "The domain $domain does NOT exist. \n"; }
	
	my $rr = 'CNAME';
	my $records = $pdns->list_records(\$rr , \$domain);
	for my $record  (@$records)
	{ print "@$record\n"; }
	
	my @rr = ('www.example.com','CNAME','example.com');
	unless ( $pdns->add_record( \@rr , \$domain) )
	{ print "Could not add a RR for $domain \n"; }
	
	unless ( $pdns->delete_record(\@rr , \$domain) )
	{ print "Could not delete RR for $domain \n"; }
	
	my $domain = 'example.com';
	my @rr1 = ('localhost.example.com','A','127.0.0.1');
	my @rr2 = ('localhost.example.com','CNAME','example.com');
	
	unless ( $pdns->update_record(\@rr1 , \@rr2 , \$domain) )
	{ print "Update failed for $domain . \n"; }
	
	my $domain = 'example.com';
	my $content = 'localhost.example.com';
	my $records = $pdns->find_record_by_content(\$content , \$domain);
	my ($name , $type) = @$records;
	print "Name: $name\n";
	print "Type: $type\n";

	my $domain = 'example.com';
	$pdns->make_domain_native(\$domain);

	my $domain = 'example.com';
	my $type = $pdns->get_domain_type(\$domain);
	if ( $type )
	{ print "Type is '$type'\n"; }
	else
	{ print "Domain $domain does not exist.\n" }

	my $master = $pdns->get_master(\$domain);
	print "Master: $master\n";

=head1 AUTHOR

Augie Schwer, C<< <augie at cpan.org> >>

http://www.schwer.us

=head1 BUGS

Please report any bugs or feature requests to
C<bug-net-powerdns-backend-mysql at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=PowerDNS-Backend-MySQL>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc PowerDNS::Backend::MySQL

    You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/PowerDNS-Backend-MySQL>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/PowerDNS-Backend-MySQL>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=PowerDNS-Backend-MySQL>

=item * Search CPAN

L<http://search.cpan.org/dist/PowerDNS-Backend-MySQL>

=back

=head1 ACKNOWLEDGEMENTS

I would like to thank Sonic.net for allowing me to release this to the public.

=head1 COPYRIGHT & LICENSE

Copyright 2007 Augie Schwer, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 VERSION

	0.02
	$Id: MySQL.pm 1480 2007-12-04 19:29:23Z augie $

=cut
