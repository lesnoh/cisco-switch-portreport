#!/usr/bin/perl

# Basierend auf: http://www.gossamer-threads.com/lists/cisco/nsp/120759
# erweitert durch Michael Honsel (lesnoh@gmx.de)
# 12/2013

use warnings;
use Net::SNMP;

# Parameter prüfen:
$ARGC = $#ARGV +1;
if ($ARGC != 1) {
	print "\nAlternativ: portreport.pl Anzahl_Tage\n\n";
	$pulldays 	= 2;	
} else { 
	$pulldays 	= $ARGV[0];
}

$community 		= 'public';
$switchliste 		= "switchlist";
$log 			= "summary.txt";
$gesamtports 		= 0;
$gesamtfreieports 	= 0;

# Ergenisse im Hash %result speichern. Key ist der Switchname
%ergebnis;

# OID
$sysUpTime 		= '1.3.6.1.2.1.1.3.0';
$sysName 		= '1.3.6.1.2.1.1.5.0';
$oid_ifTable 		= '1.3.6.1.2.1.2.2';
$oid_ifIndex 		= '1.3.6.1.2.1.2.2.1.1';
$oid_ifdescr 		= '1.3.6.1.2.1.2.2.1.2.';
$oid_ifoperstatus 	= '1.3.6.1.2.1.2.2.1.8.';
$oid_iflastchange 	= '1.3.6.1.2.1.2.2.1.9.';
$oid_ifadminstatus 	= '1.3.6.1.2.1.2.2.1.7.';

open ( LISTE,	"<", $switchliste ) 	or die "Konnte Datei $switchliste nicht öffnen: $!";
open ( LOG,	">", $log ) 		or die "Konnte Datei $log nicht öffnen: $!";

while ( <LISTE> ){
  unless ( $_ =~ "^#"){
	my ($hostname, $ip, $rest) = split (/\s+/,$_);
	&auswertung($ip);
	}
}

print "=" x 80;

print 	  "\nSwitch\t\t\t\tIP\t\tGesamt\tGenutzt\tUngenutzt\n";
print LOG "\nSwitch\t\t\t\tIP\t\tGesamt\tGenutzt\tUngenutzt\n";

foreach $key ( sort {$a cmp $b } keys %ergebnis ) {
	print 	  "$key\t\t$ergebnis{$key}\n";
	print LOG "$key\t\t$ergebnis{$key}\n";
}

print 	  "=" x 80;
print LOG "=" x 80;
print 	  "\n\nGesamtports:\t\t$gesamtports\nGesamte freie Ports:\t$gesamtfreieports\n\n";
print LOG "\n\nGesamtports:\t\t$gesamtports\nGesamte freie Ports:\t$gesamtfreieports\n\n";

close LISTE;
close LOG;
exit 0;

#############################################################################
sub auswertung() {
	my ($hostname) = @_;
	print "\n\nPortauswertung für $hostname während der letzten $pulldays Tage.\n";

	## Globale SNMP Session pro Switch aufbauen
	($session, $error) = Net::SNMP->session(
			-version => 'snmpv2c',
			-translate => '0',
			-hostname => $hostname,
			-community => $community,
			-port => 161
			);
	if (!defined($session)) {
		printf("ERROR: %s.\n", $error);
		exit 1;
	}

	## Counters
	my $tot_ports = 0;
	my $pull_ports = 0;
	##
	# these subs go gather the data basic.
	# get_sysuptime has a print at the end as well.
	##

	my ($sysname, $uptime) = &get_sysuptime;
	
	## can't run a report for more days that we have uptime
	if (($uptime/8640000) < $pulldays) {
		print "Der Switch $sysname ist noch keine $pulldays Tage gestartet!.\n\n";
		exit 1;
	}

	my @ifindexes = &get_ifindex;
	##
	# for each interface returned by get_ifindex, gather detail data
	# and print out the status if it's a candidate to be pulled
	##

	foreach $ifindex (@ifindexes) {
		@args = ($oid_ifdescr.$ifindex, $oid_ifoperstatus.$ifindex, $oid_ifadminstatus.$ifindex, $oid_iflastchange.$ifindex);
#		print "@args\n";
		my $result = $session->get_request(-varbindlist => \@args);

		my $desc 		= $result->{$oid_ifdescr.$ifindex};
		my $operstatus 		= $result->{$oid_ifoperstatus.$ifindex};
		my $lastchange 		= $result->{$oid_iflastchange.$ifindex};
		my $adminstatus 	= $result->{$oid_ifadminstatus.$ifindex};
		my $status_time_days 	= ($uptime - $lastchange) / 8640000;
		
		if ( $desc =~ /VLAN|Null|Port-Channel|Loopback|EOBC|FastEthernet[01]$/i ){ 
			print " ----- $desc Filter\n";
		} else {
			$tot_ports++;
			## are we a pull candidate? if ifoperstatus 2 == down we are
			if ($operstatus == '2' && $status_time_days >= $pulldays) {
				$pull_ports++;
				$rounded_days = sprintf("%.2f", $status_time_days);
				if ($adminstatus == '1' ) {
					print "$desc has been down for $rounded_days days \n";
				}
				if ($adminstatus == '2' ) {
					print "$desc is ADMINDOWN and has been down for $rounded_days days \n";
				}
				## die if we see a negative number
				if ($rounded_days < '0' ) {
					die "\nUh-oh...Looks like we've actually been up more than 498
						days.\nThat rocks, but is unfortunate for our purposes.\nReboot this
						gear and try again later.\n";
				}
			} else {
				print "$desc is up\n";
			}
		}
	}

	# Ergebnis ausgeben
	my $genutzt = $tot_ports - $pull_ports;

	print "\nSwitch\t\t\t\tIP\t\tGesamt\tGenutzt\tUngenutzt\n";
	print "$sysname\t\t$hostname\t$tot_ports\t$genutzt\t$pull_ports\n";

		
	$ergebnis{$sysname} = "$hostname\t$tot_ports\t$genutzt\t$pull_ports";

	$gesamtports 		+= $tot_ports;
	$gesamtfreieports 	+= $pull_ports;

	$session->close;
}

sub get_ifindex {
	my @ifindexes;
	my $tbl_ifIndex = $session->get_table(
			-baseoid => $oid_ifIndex
			);

	if (!defined($tbl_ifIndex)) {
		printf("ERROR: %s.\n", $session->error);
		$session->close;
		exit 1;
	}

	foreach $key (keys %$tbl_ifIndex) {
#	print "$key => $$tbl_ifIndex{$key}\n";
		push (@ifindexes, $$tbl_ifIndex{$key});
	}
	
	@ifindexes = sort(@ifindexes);
	return (@ifindexes);
}


sub get_sysuptime {
	my $rsysuptime = $session->get_request(-varbindlist => [$sysUpTime]);
	$uptime = $rsysuptime->{$sysUpTime};

	my $rsysname = $session->get_request(-varbindlist => [$sysName]);
	$sysname = $rsysname->{$sysName};

	printf("\nSwitch '%s' ist seit %.2f Tagen gestartet\n\n", $sysname, $uptime/8640000);

	return ($sysname, $uptime);
} 
