FROM node:11-alpine
RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app
COPY . .
RUN npm install
RUN sed -i "s|REPLACE-DB-HOST|${RDS_DB_EP}|g" /usr/src/app/app/config/config.js
EXPOSE 8080
CMD ["npm", "run", "start"]