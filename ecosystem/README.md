# Ecosystem template

This project contains the ecosystem of a Semperland games. Some of the files here are meant for reference (since
they will be already deployed in mainnets) or to be mounted in local networks, while more contents can be created
that are game-specific.

The default network is Polygmon (mainnet and the Amoy testnet). A default network is configured for local tests.
Finally, a `MNEMONIC` environment variable is needed both for mainnet and testnet usage.

## Dependencies

This project comes, by default, with the following dependencies:

- [hardhat-blueprints ^1.4.0](https://github.com/AlephVault/hardhat-blueprints)
- [hardhat-servers ^1.2.0](https://github.com/AlephVault/hardhat-servers)
- [hardhat-chainlink-common-blueprints ^1.0.1](https://github.com/AlephVault/hardhat-chainlink-common-blueprints)
- [hardhat-common-tools ^1.7.2](https://github.com/AlephVault/hardhat-common-tools)
- [hardhat-enquirer-plus ^1.5.2](https://github.com/AlephVault/hardhat-enquirer-plus)
- [hardhat-ignition-deploy-everything ^1.1.2](https://github.com/AlephVault/hardhat-ignition-deploy-everything)
- [hardhat-method-prompts ^1.4.0](https://github.com/AlephVault/hardhat-method-prompts)
- [hardhat-openzeppelin-common-blueprints ^1.2.1](https://github.com/AlephVault/hardhat-openzeppelin-common-blueprints)

Please read the README.md files on each repository in order to understand their interdependencies. They are quite
useful in many context, and many of them (e.g. `hardhat-enquirer-plus`) are mandatory for the other packages.

More dependencies can be added if you wish. The default ones provide:

- IPFS and HTTP temporary / dummy development servers.
- General blueprints, Chainlink-specific blueprints, and OpenZeppelin-specific blueprints.
- Common helpers and enhancements over the `enquirer` library.
- Quick deployment tools, and quick method call tools.

They're all detailed in their README.md files and suggested here for sample code.
