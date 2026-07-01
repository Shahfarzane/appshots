#!/usr/bin/env node

/**
 * Create DMG using appdmg (no AppleScript required)
 *
 * This script replaces the create-dmg shell tool which uses AppleScript/Finder
 * automation that can timeout on CI runners.
 *
 * Usage: node create-dmg.mjs <app_path> <output_dmg_path>
 */

import { createRequire } from 'module';
import { existsSync, readFileSync, mkdirSync } from 'fs';
import { dirname, basename, join, resolve } from 'path';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);
const appdmg = require('appdmg');

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Paths
const MACOS_ROOT = resolve(__dirname, '../..');
const INSTALLER_RESOURCES = join(MACOS_ROOT, 'Resources/Installer');
const CONFIG_FILE = join(INSTALLER_RESOURCES, 'install-bg-app-rect.json');

function usage() {
  console.log('Usage: node create-dmg.mjs <app_path> <output_dmg_path>');
  console.log('');
  console.log('Creates a DMG with custom icon positions.');
  console.log('Uses appdmg which does not require AppleScript/Finder access.');
  process.exit(1);
}

function main() {
  const args = process.argv.slice(2);

  if (args.length < 2) {
    usage();
  }

  const appPath = resolve(args[0]);
  const outputDmg = resolve(args[1]);

  // Validate app path
  if (!existsSync(appPath)) {
    console.error(`[-] app path does not exist: ${appPath}`);
    process.exit(1);
  }

  if (!appPath.endsWith('.app')) {
    console.error(`[-] provided path is not a .app bundle: ${appPath}`);
    process.exit(1);
  }

  // Read config
  if (!existsSync(CONFIG_FILE)) {
    console.error(`[-] config file not found: ${CONFIG_FILE}`);
    process.exit(1);
  }

  console.log(`[*] reading DMG layout config from ${CONFIG_FILE}`);
  const config = JSON.parse(readFileSync(CONFIG_FILE, 'utf8'));

  const scale = config.scale || 1;

  const windowWidth = config.window?.width || 670;
  const windowHeight = config.window?.height || 320;
  const iconSize = config.iconSize || 120;
  const appX = config.appIcon?.x || 178;
  const appY = config.appIcon?.y || 160;
  const linkX = config.applicationsLink?.x || 505;
  const linkY = config.applicationsLink?.y || 160;

  console.log(`[i] window size: ${windowWidth}x${windowHeight}, scale: ${scale}x`);
  console.log(`[i] icon size: ${iconSize}`);
  console.log(`[i] app position: (${appX}, ${appY})`);
  console.log(`[i] Applications link position: (${linkX}, ${linkY})`);
  console.log('[i] background: default');

  const appName = basename(appPath);
  const volumeName = appName.replace(/\.app$/, '');

  // Ensure output directory exists
  const outputDir = dirname(outputDmg);
  if (!existsSync(outputDir)) {
    mkdirSync(outputDir, { recursive: true });
  }

  // Build appdmg specification
  // See: https://github.com/LinusU/node-appdmg
  const spec = {
    title: volumeName,
    'icon-size': iconSize,
    window: {
      position: { x: 200, y: 120 },
      size: { width: windowWidth, height: windowHeight }
    },
    format: 'ULMO',
    contents: [
      { x: appX, y: appY, type: 'file', path: appPath },
      { x: linkX, y: linkY, type: 'link', path: '/Applications' }
    ]
  };

  console.log('[*] creating styled DMG with appdmg');

  // appdmg requires basepath + specification (object) or source (file path)
  const ee = appdmg({
    basepath: MACOS_ROOT,
    specification: spec,
    target: outputDmg
  });

  ee.on('progress', (info) => {
    if (info.type === 'step-begin') {
      process.stdout.write(`[*] ${info.title}... `);
    } else if (info.type === 'step-end') {
      console.log(info.status);
    }
  });

  ee.on('finish', () => {
    console.log(`[+] DMG created successfully: ${outputDmg}`);
    process.exit(0);
  });

  ee.on('error', (err) => {
    console.error(`[-] DMG creation failed: ${err.message}`);
    process.exit(1);
  });
}

main();
