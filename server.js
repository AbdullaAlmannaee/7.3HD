const express = require('express');
const app = express();

app.get('/health', (_, res) => res.json({ status: 'UP' }));
app.get('/', (_, res) => res.send('OK'));

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => console.log(`Server running on :${PORT}`));
