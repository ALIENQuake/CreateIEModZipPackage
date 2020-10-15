const core = require("@actions/core");
const exec = require("@actions/exec");

async function ExecutePowerShellScript() {
    try {
        // Execute PowerShell script
        await exec.exec(
            "pwsh", [
            `-File`,
            `${__dirname}/CreateIEModZipPackage.ps1`
        ]);
    } catch (error) {
        core.setFailed(error.message);
    }
}

ExecutePowerShellScript();
