// Local MQTT broker over WebSocket, standing in for the public brokers in tests.
//   PORT=8091 node broker.js   ->  ws://127.0.0.1:8091/mqtt
const aedes = require('aedes')();
const { createServer } = require('aedes-server-factory');
const PORT = process.env.PORT || 8091;
const server = createServer(aedes, { ws: true });
server.listen(PORT, () => console.log(`test broker on ws://127.0.0.1:${PORT}/mqtt`));
aedes.on('clientError', (c, e) => console.log('client error', c && c.id, e.message));
