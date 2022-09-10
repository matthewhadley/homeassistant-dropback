ARG BUILD_FROM
FROM $BUILD_FROM

COPY config.yaml /
RUN grep version < config.yaml | grep -oe '[0-9\.]*' > VERSION && rm config.yaml

COPY run.sh /
RUN chmod a+x /run.sh

# get a copy of dropbox_uploader.sh and amend the end of file to output errors
#
# if [[ $ERROR_STATUS -ne 0 ]]; then
#     cat $RESPONSE_FILE | sed -n -e '/^[[:space:]]*$/,$p' | sed '/^$/d'
# fi
# remove_temp_files
# exit $ERROR_STATUS
#
RUN curl --silent "https://raw.githubusercontent.com/andreafabrizi/Dropbox-Uploader/11fb8f736064730dd21ff85d68dfcc8aacfdf559/dropbox_uploader.sh" | head -n 1827 > /dropbox_uploader.sh
RUN echo 'if [[ $ERROR_STATUS -ne 0 ]]; then cat $RESPONSE_FILE | sed -n -e '"'"'/^[[:space:]]*$/,$p\'"'"' | sed '"'"'/^$/d\'"'"';fi;remove_temp_files;exit $ERROR_STATUS' >> /dropbox_uploader.sh
RUN chmod a+x /dropbox_uploader.sh

CMD [ "/run.sh" ]