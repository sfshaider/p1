FROM 301209068216.dkr.ecr.us-east-1.amazonaws.com/cacerts:latest as certs

FROM golang:1.20.3 AS pluggy-builder
COPY pluggy /build
WORKDIR /build
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o pluggy .

FROM golang:1.20.3 AS loggy-builder
COPY loggy /build
WORKDIR /build
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o loggy .

FROM golang:1.20.3 AS responselink-builder
COPY responselink /build
WORKDIR /build
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o responselink .

FROM amazonlinux:2 as amazonlinux-2-with-patches

RUN yum update -y

# amazonlinux:2 doesn't include groupadd by default
RUN yum install -y shadow-utils gzip tar

# epel is installed diferently on amazonlinux:2
RUN amazon-linux-extras install epel -y

COPY pay1_home/etc/packages.txt /root/packages.txt
RUN cat /root/packages.txt | xargs yum install -y

RUN yum install -y gcc

COPY pay1_home/tests/setup-testing.sh /root/setup-testing.sh
RUN /root/setup-testing.sh

RUN yum remove -y gcc

FROM amazonlinux-2-with-patches

USER root

COPY --from=certs /etc/ssl/certs/* /etc/ssl/certs/

RUN mkdir -p /home/pay1/etc
RUN mkdir -p /home/p

RUN mkdir -p /home/pay1/logs
RUN chmod a+rwx /home/pay1/logs

RUN mkdir -p /home/pay1/log/datalog
RUN chmod a+rwx /home/pay1/log/datalog
RUN mkdir -p /home/pay1/log/local
RUN mkdir -p /home/pay1/log/loggy
RUN touch /home/pay1/log/local/datalog_skip_proxy
RUN mkdir -p /home/pay1/etc/datalog
RUN touch /home/pay1/etc/is_container
VOLUME ["/home/pay1/log/datalog"]

RUN ln -s /home/pay1 /home/p/pay1
RUN groupadd -g 10000 pay1
RUN useradd -g pay1 -u 10000 -d /home/pay1 -s /bin/bash pay1

ENV PATH $PATH:/home/pay1/tests/bin

COPY pay1_home/bin /home/pay1/bin
COPY --from=pluggy-builder /build/pluggy /home/pay1/bin/pluggy
COPY --from=loggy-builder /build/loggy /home/pay1/bin/loggy
COPY --from=responselink-builder /build/responselink /home/pay1/bin/responselink
COPY /pay1_home/etc/loggy.conf /home/pay1/etc/loggy.conf