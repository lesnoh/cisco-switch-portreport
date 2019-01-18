# Switch portreport about offline Ports with Downtime

testet on Cisco Catalyst and Aruba / HP ProCurve switches

Ansible sends you an email with all offline ports and their description

Combine it with a cron to automate the process

## Installation 

CentOS

	yum install perl-Net-SNMP
	yum install ansible

## Usage

add switch with name and ip to _switchlist_

change SNMP community in _report.pl_

	chmod u+x report.pl

change "offline_ports" in portreport.yml to the path where the file should be created

add the ip address of your mailserver

	ansible-playbook /path/to/portreport.yml
	
## Cron

For example: Every 1st of a month at 7:30

	30 07 1 * * ansible-playbook /path/to/portreport.yml
