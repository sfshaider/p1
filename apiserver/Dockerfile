FROM pay1-base:latest

COPY httpd/global/* /etc/httpd/conf/
COPY httpd/pay1/* /etc/httpd/conf/

COPY pay1_home/tools /home/pay1/tools

COPY pay1_home/perlpr_lib /home/pay1/perlpr_lib
COPY pay1_home/perl_lib /home/pay1/perl_lib
COPY pay1_home/api-web /home/pay1/web

COPY pay1_home/httpd-bin /home/pay1/httpd-bin
RUN chown -R pay1:pay1 /home/pay1
RUN chmod 755 /home/pay1 /home/pay1/httpd-bin
RUN chmod 755 /home/pay1/httpd-bin/modify_startuppl.sh
RUN /home/pay1/httpd-bin/modify_startuppl.sh

COPY bin/insert-hash.sh /home/pay1/insert-hash.sh
RUN chmod 755 /home/pay1/insert-hash.sh
RUN /home/pay1/insert-hash.sh
RUN rm -f /home/pay1/insert-hash.sh

COPY pay1_home/web_common/healthcheck /home/pay1/web/healthcheck

# use proxies by default in container
RUN touch /home/pay1/etc/s3_proxy
RUN touch /home/pay1/etc/lambda_proxy
RUN touch /home/pay1/etc/parameterstore_proxy

# Copy and setup testing scripts.
COPY pay1_home/tests/ /home/pay1/tests/

VOLUME ["/home/pay1/perl_lib"]
VOLUME ["/home/pay1/perlpr_lib"]
VOLUME ["/home/pay1/tests"]

USER pay1

WORKDIR /home/pay1

USER root

ENV PNP_PERL_LIB=/home/pay1/perl_lib
ENV PERL5LIB=/home/pay1/perl_lib
HEALTHCHECK --interval=30s --timeout=20s --start-period=10s --retries=3 CMD [ "/home/pay1/bin/pluggy", "healthcheck" ]
CMD /home/pay1/httpd-bin/start.sh