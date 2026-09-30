/** Test entry for the game shell (one bundle, shared class identities). */
export { ModalStack } from '../../ui/ModalStack';
export { GameSettingsService, DEFAULT_GAME_SETTINGS } from '../settings/GameSettingsService';
export { SettingsSurfacePort, applyMix } from './SettingsSurfacePort';
export { ControlsSurfacePort, CONTROL_ROWS } from './ControlsSurfacePort';
export { PauseMenuSurfacePort } from './PauseMenuSurfacePort';
export { SaveSlotsSurfacePort, formatPlayTime, slotName } from './SaveSlotsSurfacePort';
export { TitleSurfacePort } from './TitleSurfacePort';
export { GameOverSurfacePort } from './GameOverSurfacePort';
export { CreditsSurfacePort, creditsText, CREDIT_SECTIONS } from './CreditsSurfacePort';
export { EndCardSurfacePort } from './EndCardSurfacePort';
export { GameShell, GAME_SHELL_SCENE_IDS } from './GameShell';
