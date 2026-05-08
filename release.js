import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { execSync } from "child_process";
import readline from "readline";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LUA_FILES = [
  path.join(__dirname, "public", "Loader.lua"),
  path.join(__dirname, "public", "Admin.lua"),
  path.join(__dirname, "public", "UniversalAdmin.lua"),  // legacy backward compat
];

function ask(rl, question) {
  return new Promise((resolve) => {
    rl.question(question, (answer) => resolve(answer.trim()));
  });
}

function askMultiLine(rl, prompt) {
  return new Promise((resolve) => {
    console.log(prompt + " (type '.' on an empty line to finish):");
    const lines = [];
    rl.on("line", (line) => {
      if (line === ".") {
        rl.removeAllListeners("line");
        resolve(lines);
      } else if (line.trim()) {
        lines.push(line.trim());
      }
    });
  });
}

async function main() {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  // Read current version from first available Lua file
  let content = null;
  let primaryFile = null;
  for (const f of LUA_FILES) {
    if (fs.existsSync(f)) {
      content = fs.readFileSync(f, "utf8");
      primaryFile = f;
      break;
    }
  }
  if (!content) {
    console.log("No Lua files found. Aborting.");
    rl.close();
    return;
  }
  const versionMatch = content.match(/Version\s*=\s*"([^"]+)"/);
  const currentVersion = versionMatch ? versionMatch[1] : "0.0.0";

  console.log("═".repeat(50));
  console.log("  UniversalAdmin Release Tool");
  console.log("═".repeat(50));
  console.log(`  Current version: ${currentVersion}`);
  console.log("═\n".repeat(1));

  const newVersion = await ask(rl, "New version (e.g. 1.1.0): ");
  if (!newVersion) {
    console.log("Version required. Aborting.");
    rl.close();
    return;
  }

  console.log("\nEnter changelog entries for this version:");
  const changelog = await askMultiLine(rl, "");
  if (changelog.length === 0) {
    console.log("At least one changelog entry required. Aborting.");
    rl.close();
    return;
  }

  rl.close();

  // Format changelog entries for Lua
  const clEntries = changelog.map((e) => `        "${e}"`).join(",\n");

  // Update version and changelog in all files
  const versionRegex = /Version\s*=\s*"[^"]*"/;
  const clRegex = /Changelog\s*=\s*\{[^}]*\}/s;
  const newCL = `Changelog = {\n${clEntries}\n    }`;

  let updatedCount = 0;
  for (const f of LUA_FILES) {
    if (!fs.existsSync(f)) continue;
    let fileContent = fs.readFileSync(f, "utf8");
    fileContent = fileContent.replace(versionRegex, `Version = "${newVersion}"`);
    fileContent = fileContent.replace(clRegex, newCL);
    fs.writeFileSync(f, fileContent, "utf8");
    updatedCount++;
    console.log(`Updated ${path.basename(f)} to v${newVersion}`);
  }
  console.log(`\n${updatedCount} file(s) updated. Changelog: ${changelog.length} entries`);

  // Ask about commit + push
  const shouldPush = process.argv.includes("--push") || process.argv.includes("-p");

  if (shouldPush) {
    const msg = `Release v${newVersion}`;
    console.log(`\nCommitting: "${msg}"`);
    try {
      execSync("git add public/Loader.lua public/Admin.lua public/UniversalAdmin.lua", {
        cwd: __dirname,
        stdio: "inherit",
      });
      execSync(`git commit -m "${msg}"`, { cwd: __dirname, stdio: "inherit" });
      execSync("git push", { cwd: __dirname, stdio: "inherit" });
      console.log("\nDone! Pushed to remote.");
    } catch (err) {
      console.error("Git failed:", err.message);
    }
  } else {
    console.log("\nFile updated. To commit & push, run:");
    console.log(`  node release.js --push`);
    console.log("or use your git-quick-push.bat");
    console.log(`\nSuggested commit message: Release v${newVersion}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
