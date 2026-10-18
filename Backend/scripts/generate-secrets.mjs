import {randomBytes} from 'node:crypto';
// Run locally and transfer through your secret manager. Never commit this output.
console.log(`OWNER_TOKEN=${randomBytes(32).toString('base64url')}`);
console.log(`DATA_ENCRYPTION_KEY=${randomBytes(32).toString('base64')}`);
