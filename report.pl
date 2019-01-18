
#!/usr/bin/perl
# Basierend auf: http://www.gossamer-threads.com/lists/cisco/nsp/120759
# erweitert durch Michael Honsel (lesnoh@gmx.de)
# 12/2013
# Ausgabe angepasst und reduziert auf nur "offline Ports mit Portbeschreibung" durch Domenic Baumeister
# 01/2019

use warnings;
use Net::SNMP;

# Parameter prüfen:
$ARGC = $#ARGV +1;
if ($ARGC != 1) {
        $pulldays       = 2;
} else {
        $pulldays       = $ARGV[0];
}

$community              = 'public';
$switchliste            = "~/switchlist";
#$gesamtports           = 0;
#$gesamtfreieports      = 0;

# Ergenisse im Hash %result speichern. Key ist der Switchname
#%ergebnis;

# OID
$sysUpTime              = '1.3.6.1.2.1.1.3.0';
$sysName                = '1.3.6.1.2.1.1.5.0';
$oid_ifIndex            = '1.3.6.1.2.1.2.2.1.1';
$oid_ifdescr            = '1.3.6.1.2.1.2.2.1.2.';
$oid_ifoperstatus       = '1.3.6.1.2.1.2.2.1.8.';
$oid_iflastchange       = '1.3.6.1.2.1.2.2.1.9.';
$oid_ifadminstatus      = '1.3.6.1.2.1.2.2.1.7.';
$oid_ifxAlias           = '1.3.6.1.2.1.31.1.1.1.18.';

open ( LISTE,   "<", $switchliste )     or die "Konnte Datei $switchliste nicht öffnen: $!";

while ( <LISTE> ){
  unless ( $_ =~ "^#"){
        my ($hostname, $ip, $rest) = split (/\s+/,$_);
        &auswertung($ip);
        }
}

foreach $key ( sort {$a cmp $b } keys %ergebnis ) {
        print     "$key\t\t$ergebnis{$key}\n";
        print LOG "$key\t\t$ergebnis{$key}\n";
}

close LISTE;
close LOG;
exit 0;

#############################################################################
sub auswertung() {
        my ($hostname) = @_;
        print "\nPortauswertung für $hostname während der letzten $pulldays Tage.";

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
                print "Der Switch $sysname ist noch keine $pulldays Tage gestartet!.\n";
                exit 1;
        }

        my @ifindexes = &get_ifindex;
        ##
        # for each interface returned by get_ifindex, gather detail data
        # and print out the status if it's a candidate to be pulled
        ##

        foreach $ifindex (@ifindexes) {
                @args = ($oid_ifdescr.$ifindex, $oid_ifoperstatus.$ifindex, $oid_ifadminstatus.$ifindex, $oid_iflastchange.$ifindex, $oid_ifxAlias.$ifindex);
#               print "@args\n";
                my $result = $session->get_request(-varbindlist => \@args);

                my $desc                = $result->{$oid_ifdescr.$ifindex};
                my $operstatus          = $result->{$oid_ifoperstatus.$ifindex};
                my $lastchange          = $result->{$oid_iflastchange.$ifindex};
                my $adminstatus         = $result->{$oid_ifadminstatus.$ifindex};
                my $name                = $result->{$oid_ifxAlias.$ifindex};
                my $status_time_days    = ($uptime - $lastchange) / 8640000;

                if ( $desc =~ /VLAN|Null|Port-Channel|Loopback|EOBC|FastEthernet[01]$/i ){
                        print "";
                }  else {
                        $tot_ports++;
                        ## are we a pull candidate? if ifoperstatus 2 == down we are
                        if ($operstatus == '2' && $status_time_days >= $pulldays) {
                                $pull_ports++;
                                $rounded_days = sprintf("%.2f", $status_time_days);
                                if ($adminstatus == '1' && $name ne '' ) {
                                        print "Port: $desc | Description: $name | Days offline: $rounded_days\n";
                                }
                        }
                }
        }

print "-" x 80;
print "\n"
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
