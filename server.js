const express = require('express');
const app = express();
app.get('/', (_, res) => res.send('OK'));
app.get('/health', (_, res) => res.json({ status: 'UP' }));
app.listen(3000, () => console.log('App on :3000'));
