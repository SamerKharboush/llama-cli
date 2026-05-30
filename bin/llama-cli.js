#!/usr/bin/env node

/**
 * llama-cli — Interactive CLI launcher for optimized llama.cpp
 * For Intel Mac (Mac Pro 2013, Ivy Bridge, AVX + F16C + Apple Accelerate BLAS)
 */

const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const PACKAGE_DIR = path.resolve(__dirname, '..');
const LAUNCHER_PATH = path.join(PACKAGE_DIR, 'src', 'llama-launcher.sh');
const VENDOR_DIR = path.join(PACKAGE_DIR, 'vendor', 'llama-cpp-macpro');

// Verify installation
if (!fs.existsSync(LAUNCHER_PATH)) {
  console.error('\x1b[31mError: llama-launcher.sh not found.\x1b[0m');
  console.error('The package may not be fully installed. Try:');
  console.error('  npm reinstall -g llama-cli');
  process.exit(1);
}

if (!fs.existsSync(VENDOR_DIR)) {
  console.error('\x1b[31mError: vendor binaries not found.\x1b[0m');
  console.error('The postinstall script may not have run. Try:');
  console.error('  cd ' + PACKAGE_DIR + ' && node scripts/postinstall.js');
  process.exit(1);
}

// Set environment for the launcher
const env = Object.assign({}, process.env, {
  LLAMA_DIR: VENDOR_DIR,
  MODELS_DIR: process.env.MODELS_DIR || path.join(process.env.HOME, 'models'),
});

// Spawn the launcher as an interactive process
const child = spawn('/bin/zsh', [LAUNCHER_PATH].concat(process.argv.slice(2)), {
  stdio: 'inherit',
  env: env,
});

// Forward signals
process.on('SIGINT', () => child.kill('SIGINT'));
process.on('SIGTERM', () => child.kill('SIGTERM'));

child.on('exit', (code) => {
  process.exit(code || 0);
});

child.on('error', (err) => {
  if (err.code === 'ENOENT') {
    console.error('\x1b[31mError: zsh not found.\x1b[0m');
    console.error('llama-cli requires zsh (default macOS shell).');
  } else {
    console.error('\x1b[31mError launching llama-cli:\x1b[0m', err.message);
  }
  process.exit(1);
});
