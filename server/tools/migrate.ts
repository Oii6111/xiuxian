import { loadEnvFile } from 'node:process';
import { existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { Database } from '../src/database.js';
import { repositoryRoot } from '../src/contracts.js';

const serverRoot = join(repositoryRoot, 'server');
if (existsSync(join(serverRoot, '.env'))) loadEnvFile(join(serverRoot, '.env'));
const database = new Database(resolve(serverRoot, process.env.DATABASE_PATH ?? 'var/game.sqlite'));
console.log('本地数据库迁移完成：', database.get('PRAGMA user_version'));
database.close();
