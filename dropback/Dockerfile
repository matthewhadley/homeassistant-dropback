ARG BUILD_FROM
FROM $BUILD_FROM

RUN apk add --no-cache openssl

COPY run.sh /
RUN chmod a+x /run.sh

RUN curl "https://raw.githubusercontent.com/andreafabrizi/Dropbox-Uploader/master/dropbox_uploader.sh" -o /dropbox_uploader.sh
RUN chmod a+x /dropbox_uploader.sh

CMD [ "/run.sh" ]