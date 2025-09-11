FROM node:18-alpine
WORKDIR /app

# install prod deps
COPY package*.json ./
RUN npm ci --only=production || npm install --only=production

# copy app code
COPY . .

EXPOSE 3000
CMD ["node", "server.js"]
