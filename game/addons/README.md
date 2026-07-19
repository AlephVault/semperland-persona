# Add-ons and dependencies

The following dependencies are needed for this project:

- From [redot-windrose](https://github.com/AlephVault/redot-windrose) `v1.0.x`:

  - AlephVault.WindRose
  - AlephVault.WindRose.LPC
  - AlephVault.WindRose.REFMAP

- From [redot-mmo](https://github.com/AlephVault/redot-mmo) `v1.0.x`:

  - AlephVault.MMO.Common
  - AlephVault.MMO.Client (if this app is the client-side of the game)
  - AlephVault.MMO.Server (if this app is the server-side of the game)
  - AlephVault.MMO.Storage (if this app is the server-side of the game, typically)

- From [redot-windrose](https://github.com/AlephVault/redot-bindrose) `v1.0.x`:

  - AlephVault.BindRose.Common
  - AlephVault.BindRose.Client (if this app is the client-side of the game)
  - AlephVault.BindRose.Server (if this app is the server-side of the game)

- From [redot-evm](https://github.com/AlephVault/redot-evm) `v1.0.x`:

  - AlephVault.EVM

- From [redot-evm-mmo](https://github.com/AlephVault/redot-evm-mmo) `v1.0.x`:

  - AlephVault.EVM.MMO.Common
  - AlephVault.EVM.MMO.Client (if this app is the client-side of the game)
  - AlephVault.EVM.MMO.Server (if this app is the server-side of the game)

**Please note**: All the dependencies in this directory should, typically, be ignored by entries
in the `.gitignore` file. By default, all the `AlephVault.*/` entries are ignored.

## Splitting client and server apps

If you don't want to leak server code into the clients, you might want to create separate projects
for the server and the clients. With this in mind, you can safely remove the add-ons that are hinted
as pertaining only to one side (e.g. removing the server-side packages from client apps).
