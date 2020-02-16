const { inspect } = require("util");
const core = require("@actions/core");
const exec = require("@actions/exec");

async function run() {
  try {
    // Allows ncc to find assets to be included in the distribution
    core.debug(`src: ${__dirname}`);

    // Execute PowerShell script
    await exec.exec("pwsh", [
      `-File`,
      `${__dirname}\\CreateIEModZipPackage.ps1`
    ]);
  } catch (error) {
    core.setFailed(error.message);
  }
}

run();
