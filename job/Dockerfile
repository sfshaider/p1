FROM pay1-base:latest

COPY pay1_home/job /home/pay1/job
COPY pay1_home/jobs /home/pay1/jobs
COPY pay1_home/keys /home/pay1/keys
COPY pay1_home/perlpr_lib /home/pay1/perlpr_lib
COPY pay1_home/perl_lib /home/pay1/perl_lib
RUN chown -R pay1:pay1 /home/pay1

USER pay1

WORKDIR /home/pay1

# use proxies by default in container
RUN touch /home/pay1/etc/s3_proxy
RUN touch /home/pay1/etc/lambda_proxy
RUN touch /home/pay1/etc/parameterstore_proxy
RUN mkdir /home/pay1/etc/transid
RUN touch /home/pay1/etc/transid/all_processors

USER root

ENV PNP_PERL_LIB=/home/pay1/perl_lib

USER pay1

CMD /home/pay1/job/run.pl
