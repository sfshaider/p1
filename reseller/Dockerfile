FROM pay1-base:latest

COPY httpd/global/* /etc/httpd/conf/
COPY httpd/reseller/* /etc/httpd/conf/

COPY pay1_home/tools /home/pay1/tools

COPY pay1_home/perlpr_lib /home/pay1/perlpr_lib
COPY pay1_home/perl_lib /home/pay1/perl_lib
COPY pay1_home/reseller_web /home/pay1/web
COPY pay1_home/web_common/lostpass.cgi /home/pay1/web/lostpass.cgi
COPY pay1_home/webtxt /home/pay1/webtxt
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
COPY pay1_home/web_common/login /home/pay1/web/login
COPY pay1_home/react/_js/r/* /home/pay1/web/_js/r/
COPY pay1_home/web_common/_css/ /home/pay1/web/_css/
COPY pay1_home/web_common/_js/ /home/pay1/web/_js/
COPY pay1_home/web_common/css/ /home/pay1/web/css/
COPY pay1_home/web_common/javascript/ /home/pay1/web/javascript/
COPY pay1_home/web/javascript/jquery.min.js /home/pay1/web/javascript/jquery.min.js
COPY pay1_home/web/javascript/page_lostpass.js /home/pay1/web/javascript/page_lostpass.js
COPY pay1_home/web_common/api/login/* /home/pay1/web/api/login/
RUN chown -R pay1:pay1 /home/pay1/web/login
RUN chown -R pay1:pay1 /home/pay1/web/_js
RUN chown -R pay1:pay1 /home/pay1/web/api/login

# use proxies by default in container
RUN touch /home/pay1/etc/s3_proxy
RUN touch /home/pay1/etc/lambda_proxy
RUN touch /home/pay1/etc/parameterstore_proxy

# Copy and setup testing scripts.
COPY pay1_home/tests/ /home/pay1/tests/

VOLUME ["/home/pay1/webtxt"]
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
