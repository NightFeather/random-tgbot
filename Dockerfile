FROM ruby:slim-buster
RUN apt update && apt upgrade
RUN apt install -y build-essential ffmpeg curl jq python3
RUN ln -s /usr/bin/python3 /usr/bin/python
RUN curl -L https://yt-dl.org/downloads/latest/youtube-dl -o /usr/bin/youtube-dl
RUN chmod +x /usr/bin/youtube-dl
RUN mkdir /app
COPY . /app
WORKDIR /app
EXPOSE 4567
RUN bundle
CMD [ "ruby", "main.rb" ]
