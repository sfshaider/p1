#!/bin/csh

cd /home/pay1/batchfiles

set mydate = `date '+%m'`

echo $mydate

foreach var (`ls /home/pay1/batchfiles/logs/*/serverlogmsg.txt`)
  echo $var
  mv $var $var$mydate'sav'
  touch $var
  chmod 666 $var
  gzip -f $var$mydate'sav'
  chmod 600 $var$mydate'sav'.gz
end

foreach var (`ls /home/pay1/batchfiles/logs/*/bserverlogmsg.txt`)
if ( ! -e $var$mydate'sav.gz' ) then
  echo $var
  mv $var $var$mydate'sav'
  touch $var
  chmod 666 $var
  gzip -f $var$mydate'sav'
  chmod 600 $var$mydate'sav'.gz
endif
end


