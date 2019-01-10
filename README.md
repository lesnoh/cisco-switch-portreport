# Switch portreport about last interfaces use

testet on Cisco Catalyst and Aruba / HP ProCurve switches


## Installation 

CentOS

yum install perl-Net-SNMP


## Usage

add switch with name and ip to _switchlist_

change SNMP community in _portreport.pl_

chmod u+x _portreport.pl

./portreport.pl
