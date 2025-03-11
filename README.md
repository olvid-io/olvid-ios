[![Tuist badge](https://img.shields.io/badge/Powered%20by-Tuist-blue)](https://tuist.io)

# Olvid

Olvid is a private and secure end-to-end encrypted messenger.

Contrary to most other messaging applications, Olvid does not rely on a central directory to connect users. As there is no user directory, Olvid does not require access to your contacts and can function without **any** personal information. The absence of directory also prevents unsolicited messages and spam.

Because of this, from a security standpoint, Olvid is **not** "yet another secure messenger". Olvid guarantees the total and definitive confidentiality of exchanges, relying **solely** on the mutual trust of interlocutors. This implies that your privacy does not depend on the integrity of some server. This makes Olvid very different from other messengers that typically rely on some "Trusted Third Party", like a centralized database of users or a public blockchain.

Note that this doesn't mean that Olvid uses no servers (it does). It means that you do not have to trust them: your privacy is ensured by cryptographic protocols running on the client-side (i.e., on your device), and these protocols assume that the servers were compromised from day one. Even then, your privacy is ensured 😊.

## Help and documentation

If you need help using Olvid, first have a look at our FAQ at [https://olvid.io/faq/](https://olvid.io/faq/). We also have a few short tutorial videos available in [English](https://www.youtube.com/channel/UCO8UuhbgCyVSTRi4QEschqA) and in [French](https://www.youtube.com/channel/UC6aLiDb04Rfh4MoqDpJoLeg).

If you are looking for **technical documentation**, have a look at our [technology page](https://olvid.io/technology/) where you can find some technical specifications and the reports of the audits Olvid went through to get its [CSPN certifications](https://www.ssi.gouv.fr/entreprise/produits-certifies/produits-certifies-cspn/#type_13).

## Send us feedback

If you find a bug, or have any feedback about Olvid, please contact the team at Olvid at [feedback@olvid.io](mailto:feedback@olvid.io). They will be glad to hear your suggestions.

# Building Olvid from the sources

To build Olvid for iOS, you would need:

  - The latest version of Xcode
  - A [free] [Apple developer account](https://developer.apple.com)
- Git LFS
  - Make sure to run `git lfs install --system` to install the appropriate LFS hooks prior cloning
- If you wish to run the project on a real device, specify your development by updating the value for `Constant.devTeam` in `Tuist/ProjectDescriptionHelpers/Constant.swift`
- [`tuist`](https://github.com/tuist/tuist) installed (at least version 4.21.2)
- `tuist generate` to generate and open the Xcode workspace

- If you encounter an issue with `error: 'swiftpackagemanager': invalid manifest` when executing `tuist generate`, make sure that you have an Xcode-defined command line tools path.
  - Verify that `xcode-select -p` looks something like `/Applications/Xcode.app/Contents/Developer`
  - If not, run `sudo xcode-select -r` to reset the command line tools path

## Running Olvid in a simulator

After generating the project, choose the `Olvid` scheme. Then choose a simulator (like an iPhone 15 Pro for example). From the `Product` menu, choose `Run`. This should compile Olvid for iOS and launch it in the chosen simulator.

## Running Olvid on a real device

If you joined [Apple Developer Program](https://developer.apple.com/programs/), you will be able to build Olvid for iOS from the sources and run it on a real device (iPhone, iPod, or iPad). Doing so is a little bit more difficult than running Olvid in a simulator. For now, we do not cover this scenario here.

# Structure of the project

All the source code of Olvid is organized within the `Sources` directory.

Olvid is made up of three main components:

- a **cryptographic engine**, located in the `~/Sources/Engine` directory,
- an **application layer**, located in the `~/Sources/App` directory,
- and a few projects between the engine and the app, located in the `~/Sources/Shared` directory.

The cryptographic engine is in charge of all the cryptographic aspects of Olvid (including encryption, signatures, MACs, cryptographic protocols, etc.), contacts and groups management, and network communications. The application layer implements the instant messaging functionalities on top of the engine. This architecture makes it possible to properly separate the backend logic from the UI.

As of now, the code is not fully documented and contains very few comments. Still, some aspects of it are very advanced and might be hard getting into. The Olvid team is doing its best to improve your experience using this code and will try to improve these aspects in future releases.

# Contributing to Olvid

Olvid, as a company, has not yet put in place all the necessary processes to easily accept external contributions. In particular, a Contributor License Agreement should be made available at some point in time. Until then, please contact us at [opensource@olvid.io](mailto:opensource@olvid.io) if you would like to contribute.

# License

Olvid for iOS is licensed under the GNU Affero General Public License v3. The full license is available in [`LICENSE`](LICENSE).

    Olvid for iOS
    Copyright © 2019-2024 Olvid SAS

    Olvid is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License, version 3,
    as published by the Free Software Foundation.

    Olvid is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
