# Updating the pack

You make changes in the CurseForge instance **All of Create Aeronautics**, then run
`update-pack.bat` from this folder. The tool:

1. rebuilds `mods/*.pw.toml` from the instance's `mods\*.jar` files (`*.disabled` jars are ignored);
2. mirrors `config`, `defaultconfigs`, `configureddefaults`, `resourcepacks`, `shaderpacks`,
   `fancymenu_data` and `datapacks` (skipping everything in `.packwizignore`);
3. aborts if it finds personal data in those files;
4. bumps the pack version and runs `packwiz refresh`;
5. shows which mods were added, removed or updated and which config files changed;
6. asks `Publish? (y/n)`, then commits and pushes to GitHub.

Friends get the update **the next time they launch** the Prism instance. The server gets it
**the next time it restarts**.

**After publishing, wait 5 minutes** before you launch or restart the server. GitHub's raw file
cache serves old copies for up to 5 minutes. The tool waits up to 6 minutes and prints
`Live now` once the new files are being served. If a friend sees "Hash invalid", wait 5 minutes and relaunch.

Options (run from a terminal in this folder):

| Command | What it does |
|---|---|
| `update-pack.bat -DryRun` | Shows what would change, commits nothing and puts the repo back as it was |
| `update-pack.bat -Yes` | Publishes without asking |
| `update-pack.bat -NoWait` | Skips waiting for GitHub's cache |

You need `git` and `node` installed. If you press `n` at the publish prompt, nothing is kept.

## Add a mod
Install it in CurseForge, test it in-game if you like, close the game and run `update-pack.bat`.
The summary should list it under **Mods added**.

## Remove a mod
Remove it in CurseForge. Disabling it works too, because `.disabled` jars are left out. Then
run `update-pack.bat`, and the summary lists it under **Mods removed**.

> **Back up the server world before you remove a content mod** (anything that adds blocks,
> items, entities or dimensions). The world loses everything from that mod when the server restarts.

## Update a mod
Update it in CurseForge and run `update-pack.bat`. The summary shows `old.jar -> new.jar`
under **Mods updated**.

## Change a config
Change it in-game or edit the file in the instance's `config` folder, then run
`update-pack.bat`. Changed files are listed under **Config/content files changed**.

## Mark a mod client-only
Client-only mods (shaders, minimaps, menus and so on) are not installed on the server. Add the
jar's exact filename on its own line in `tools\client-only.txt`, then run `update-pack.bat`.
Updates keep a mod client-only, and the tool rewrites the list with the new filename. To make a
mod install on both client and server again, delete its line and run the tool.

## Mods that can't be used
Some authors block third-party downloads on CurseForge. Those mods can't be distributed through
packwiz, so the tool **aborts and names them**. Remove the mod, or find a copy of it on Modrinth.

## Roll back a bad update
```
git log --oneline          # find the bad "Pack update x.y.z" commit
git revert <commit>        # makes a new commit that undoes it
git push
```
Friends and the server pick up the rollback on their next launch or restart. Then put the
CurseForge instance back the same way (downgrade or re-add the mod). If you don't, the next
`update-pack.bat` will publish the bad change again.

## If it aborts
- **Personal data found**: it names the files. Remove your name or email from them, or add the path to `.packwizignore`.
- **Pack files have uncommitted changes**: run `git status`, then commit or discard them (`git checkout -- .`).
- **git push failed**: the commit is saved locally. Fix the problem (network or login) and run `git push`.
