FROM quay.io/ukhomeofficedigital/docker-centos-base:master

MAINTAINER Lewis Marshall <lewis@technoplusit.co.uk>

WORKDIR /root
RUN yum install -y wget && \
    yum clean all
RUN wget -O ./mockingjay-server \
    https://github.com/quii/mockingjay-server/releases/download/pre-release/linux_amd64_mockingjay-server
RUN chmod +x ./mockingjay-server

ADD test-servers.yaml ./
ENTRYPOINT ["/root/mockingjay-server", "-config=./test-servers.yaml", "-port=8080"]

EXPOSE 8080
