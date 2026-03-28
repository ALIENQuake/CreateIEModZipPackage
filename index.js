import * as core from "@actions/core";
import * as exec from "@actions/exec";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

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

await ExecutePowerShellScript();
