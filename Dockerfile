FROM python:3

RUN pip install eth-brownie

# Install linux dependencies
RUN apt-get update \
 && apt-get install -y libssl-dev npm nginx

RUN npm install n -g \
 && npm install -g npm@latest
RUN npm install -g ganache

RUN echo 'server {\n\
    listen 80;\n\
    server_name localhost;\n\
    location / {\n\
        proxy_pass http://localhost:8545;\n\
    }\n\
}' >> /etc/nginx/conf.d/default.conf

WORKDIR /app

COPY . .

RUN brownie compile

# ENV WEB3_INFURA_PROJECT_ID

EXPOSE 80

CMD ["sh","-c","nginx -g 'daemon off;' & ./run.sh"]