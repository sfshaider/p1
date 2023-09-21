#!/bin/csh

sleep 6
echo aaaa
nohup /home/pay1/batchfiles/prod/fdms/fdms.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/maverick/maverick.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/paytechtampa/ptech.pl >& /dev/null &
#   nohup /home/pay1/batchfiles/prod/paytechtampa/ptechv34.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/global/global.pl >& /dev/null &
#   nohup /home/pay1/batchfiles/prod/paytechtampa/ptechtest.pl >& /dev/null &
#   sleep 3
nohup /home/pay1/batchfiles/prod/paytechsalem/ptech.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/nova/nova.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/buypass/buypass.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/fdmsomaha/fdmso.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/fdmsomaha/fdmsob.pl >& /dev/null &
sleep 3
nohup /home/pay1/batchfiles/prod/fdmsnorth/fdmsnorth.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/fdms/fdmsbatch.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/fdmsintl/fdmsintl.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/fifththird/fifth.pl >& /dev/null &
#   sleep 3
#   echo cccc
#   #nohup /home/pay1/batchfiles/prod/cayman/cayman.pl >& /dev/null &
#nohup /home/pay1/batchfiles/prod/ncb/ncb.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/fdmsrc/fdmsrc.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/ncb/ncbtest.pl >& /dev/null &
#   sleep 3
#nohup /home/pay1/batchfiles/prod/ncb/ncbtest2.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/ncb/ncbtest3.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/ncb/ncbtest4.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/ncb/ncbtest5.pl >& /dev/null &
#   nohup /home/pay1/batchfiles/prod/rbc/rbc1.pl >& /dev/null &
#   nohup /home/pay1/batchfiles/prod/rbc/rbc2.pl >& /dev/null &
#   nohup /home/pay1/batchfiles/prod/rbc/rbc3.pl >& /dev/null &
#   nohup /home/pay1/batchfiles/prod/rbc/rbc4.pl >& /dev/null &
sleep 3
#   nohup /home/pay1/batchfiles/prod/globalctf/globalctf.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/cccc/cccc.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/pago/pago.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/globalc/globalc.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/evertec/evertec.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/telecheckftf/telecheckftf.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/telecheckftf/telecheckftftest.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/telecheck/telecheck.pl >& /dev/null &
#   #nohup /home/pay1/batchfiles/prod/telecheck/telechecktst.pl >& /dev/null &
#   nohup /home/pay1/batchfiles/prod/fdmsemv/fdmsemvtest.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/fdmsdebit/fdmsdebit.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/fdmslcr/fdmslcr.pl >& /dev/null &
nohup /home/pay1/batchfiles/prod/fdmsrctok/fdmsrctok.pl >& /dev/null &
echo dddd


