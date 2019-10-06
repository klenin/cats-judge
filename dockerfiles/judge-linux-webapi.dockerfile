FROM ubuntu:bionic

RUN apt-get update && \
    apt-get install -y cpanminus \
        build-essential \
        git \
        vim \
        libfile-copy-recursive-perl \
        libxml-parser-perl \
        fp-compiler \
        fp-units-base \
        fp-units-math \
        fp-units-rtl

RUN git clone https://github.com/klenin/cats-judge
WORKDIR /cats-judge
RUN cpanm --installdeps .

RUN useradd -ms /bin/bash judge

USER judge
WORKDIR /home/judge
RUN git clone https://github.com/klenin/cats-judge

WORKDIR /home/judge/cats-judge
RUN perl install.pl

ENTRYPOINT ["perl", "judge.pl", "serve"]
