const { basename } = require("path");
const path = require("path");
const { promisify } = require("util");
const exec = promisify(require("child_process").exec);
const copy = promisify(require("fs").copyFile);
const access = promisify(require("fs").access);
const lstat = promisify(require("fs").lstat);
const realpath = promisify(require("fs").realpath);
const readFile = promisify(require("fs").readFile);
const symlink = promisify(require("fs").symlink);
const fsConstants = require("fs").constants;
const koffi = require("koffi");

const skipped = ["libMoltenVK.dylib"];

// return a list of deps
async function getDeps(name) {
  // tool
  const { stdout: output } = await exec("otool -L " + name);
  const paths = output
    .split("\n")
    .slice(1)
    .map((x) => x.trim().split(" ")[0])
    .slice(0, -1);
  return paths;
}

async function changeDep(from, to, file) {
  const { stdout: output } = await exec(
    `install_name_tool -change ${from} ${to} ${file}`
  );
}

async function changeId(to, file) {
  const { stdout: output } = await exec(`install_name_tool -id ${to} ${file}`);
}

async function doCopy(from) {
  const file = path.basename(from);
  const s = await lstat(from);
  if (s.isSymbolicLink()) {
    const real = await realpath(from);
    try {
      await access(path.basename(real), fsConstants.F_OK);
    } catch {
      await copy(real, path.basename(real));
    }
    if (path.basename(real) != file) {
      await symlink(path.basename(real), file);
    }
  } else {
    await copy(from, file);
  }
}

async function analyzeLib(name, originalPath) {
  const stack = [[name, originalPath]];
  while (stack.length) {
    const [name, originalPath] = stack.pop();
    if(!originalPath.startsWith("/")) {
      throw new Error("not a valid path");
    }
    const deps = await getDeps(name);
    const self = deps[0];
    console.log(`processing ${self}`);
    await changeId(`@rpath/${path.basename(self)}`, name);
    for (let dep of deps.slice(1)) {
      let realDepPath = dep;
      if (!dep.startsWith("/usr/lib/") && !dep.startsWith("/System/Library/")) {
        if(dep.startsWith("@loader_path/")) {
          const relativePath = dep.slice("@loader_path/".length);
          const s = path.dirname(originalPath);
          realDepPath = path.resolve(s, relativePath);
        }
        try {
          await access(path.basename(dep), fsConstants.F_OK);
        } catch {
          await doCopy(realDepPath);
          stack.push([path.basename(dep), realDepPath]);
        }
        await changeDep(dep, `@loader_path/${path.basename(dep)}`, name);
      }
    }
  }
}

async function find(file) {
  try {
    koffi.load("/usr/lib/" + file);
    return "";
  } catch {
    console.log(`Seems ${file} is not a system library, finding in brew...`);
  }
  const { stdout: output } = await exec("find /usr/local/Cellar -name " + file);
  const files = output.split("\n").filter((x) => x != "");
  if (files.length == 0) {
    throw new Error(`Can not find ${file}!`);
  }
  if (files.length > 1) {
    console.log(`Find multiple ${file}`);
    console.log(files);
  }
  return files[0];
}

async function main() {
  const header = await readFile(process.argv[2], { encoding: "utf-8" });
  const tofind = header
    .split("\n")
    .map((x) => x.replace(/\s+/g, " ").trim().split(" "))
    .filter((array) => array[0] == "#define" && array[1]?.startsWith("SONAME_"))
    .map((array) => array[2].slice(1, -1));
  console.log(tofind);
  for (const file of tofind) {
    if (skipped.indexOf(file) >= 0) {
      continue;
    }
    const abspath = await find(file);
    // FIXME: wtf?
    if (abspath == "") continue;
    try {
      await access(path.basename(abspath), fsConstants.F_OK);
    } catch {
      await doCopy(abspath);
    }
    await analyzeLib(path.basename(abspath), abspath);
  }
}

main().then((x) => {});
