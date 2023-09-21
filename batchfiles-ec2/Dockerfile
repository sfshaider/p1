FROM pay1-base:latest

COPY httpd/global/* /etc/httpd/conf/
COPY httpd/pay1/* /etc/httpd/conf/

COPY pay1_home/tools /home/pay1/tools


COPY pay1_home/batchfiles/ec2 /home/pay1/batchfiles
COPY pay1_home/bin/responselink /home/pay1/batchfiles/bin/responselink
COPY pay1_home/perlpr_lib /home/pay1/batchfiles/perlpr_lib
COPY pay1_home/perl_lib /home/pay1/batchfiles/perl_lib

RUN chown -R pay1:pay1 /home/pay1
RUN mkdir -p /home/pay1/log/batchfiles
RUN touch /home/pay1/log/batchfiles/common.log

# use proxies by default in container
RUN touch /home/pay1/etc/s3_proxy
RUN touch /home/pay1/etc/lambda_proxy
RUN touch /home/pay1/etc/parameterstore_proxy
RUN mkdir /home/pay1/etc/transid
RUN touch /home/pay1/etc/transid/all_processors

# Copy and setup testing scripts.
COPY pay1_home/tests/ /home/pay1/tests/


USER pay1

WORKDIR /home/pay1

USER root

ENV PNP_PERL_LIB="/home/pay1/perl_lib"
ENV PERL5LIB="/home/pay1/perl_lib:/home/pay1/perlpr_lib"
# healthcheck to be added later
CMD tail -f /dev/null
