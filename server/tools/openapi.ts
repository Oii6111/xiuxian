import { buildApp } from '../src/app.js';

const server = await buildApp({ worker: false });
try { console.log(JSON.stringify(server.app.swagger(), null, 2)); }
finally { await server.app.close(); }
