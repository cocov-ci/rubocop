FROM ruby:3.1-alpine
RUN apk add --no-cache git openssh

COPY plugin.rb /plugin.rb

RUN addgroup -g 1000 cocov && \
    adduser --shell /bin/ash --disabled-password \
   --uid 1000 --ingroup cocov cocov

USER cocov

env GEM_HOME=/home/cocov/.gem
env PATH=$GEM_HOME/bin:$PATH
RUN gem install cocov_plugin_kit -v 0.1.6

CMD ["cocov", "/plugin.rb"]
