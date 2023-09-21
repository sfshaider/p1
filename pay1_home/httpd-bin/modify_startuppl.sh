#!/bin/sh

PACKAGES=`find /home/pay1/perl_lib -type f | xargs -L 1 grep '^package' | sed -e 's/^package //' | xargs -L 1 -I REPL echo use REPL | xargs echo`

sed -e "s/#<USEMODULESHERE>#/$PACKAGES/" < /home/pay1/httpd-bin/startup_template.pl > /home/pay1/httpd-bin/startup.pl
chmod +x /home/pay1/httpd-bin/startup.pl