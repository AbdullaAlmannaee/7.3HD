const http = require('http');
const port = process.env.PORT || 3000;
const server = http.createServer((_, res) => res.end('OK'));
server.listen(port, () => console.log(`Up on ${port}`));
