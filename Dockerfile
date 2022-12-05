FROM ruby:2.7-slim

RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git && \
    apt-get clean

WORKDIR /app

ADD ./Gemfile /app
ADD ./Gemfile.lock /app

ARG RACK_ENV=production
ENV RACK_ENV=$RACK_ENV

RUN bundle config --global jobs `cat /proc/cpuinfo | grep processor | wc -l | xargs -I % expr % - 1` && \
    if echo "development test" | grep -w "$RACK_ENV"; then \
    bundle install; \
    else \
    # switch to new config syntax for non dev/test gem group installs
    bundle config set --local without 'development test'; \
    bundle install; \
    fi

ADD ./ /app

RUN (git log --format="%H" -n 1 > public/commit_id.txt)

EXPOSE 80
CMD ["/app/docker/start.sh"]
