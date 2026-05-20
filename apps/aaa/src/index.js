const express = require('express');

const app = express();
const PORT = Number(process.env.PORT) || 3000;

app.get('/', (_req, res) => {
  res.json({ service: 'aaa', status: 'running' });
});

app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`aaa service listening on port ${PORT}`);
});
