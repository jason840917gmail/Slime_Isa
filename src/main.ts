import './styles.css';

import { createGame } from './game/config';

const app = document.querySelector<HTMLDivElement>('#app');

if (!app) {
  throw new Error('Missing app container.');
}

void createGame(app);
