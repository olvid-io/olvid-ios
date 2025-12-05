/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import ObvTypes
import ObvCrypto
import ObvDesignSystem
import ObvAppTypes
import ObvSystemIcon
import SwiftUI
import ObvProfilePictureBarButtonItem
import ObvOwnedIdentityChooser

#if DEBUG

extension ObvCryptoId {
    
    @MainActor
    static let sampleDatasForOwnedCryptoId: [Self] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f00002d459c378a0bbc54c8be3e87e82d02347c046c4a50a6db25fe15751d8148671401054f3b14bbd7319a1f6d71746d6345332b92e193a9ea00880dd67b2f10352831")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000089aebda5ddb3a59942d4fe6e00720b851af1c2d70b6e24e41ac8da94793a6eb70136a23bf11bcd1ccc244ab3477545cc5fee6c60c2b89b8ff2fb339f7ed2ff1f0a")!),
    ]

    @MainActor
    static let sampleDatasForContactCryptoId: [Self] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000153c2183e6feef914ef20ae0f2ce4dd025022221b0bfdf22fb16859feac477fa0023713e65219d2c01f6feb26f9d2a390fd9afce7389f7ae22884f0efccad74c83")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000a7cc11bc3d5b0aaff7689da45478d11e3ac216a84fda1eee483e69d5f38239ca0087679c83bab21cd7ac8ffa73f1494b574364a8e51a99c040f7900b71d3878ac6")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00001c94bfc08515742d03156b104173bb911e761fa388ed008773e3854f1bf3bb31003f0b55bc89f59d3c9e7eb2a74437a0fe90696318888676869fda77ed0dcdcc55")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000aeaf4fb1ed5cdbdb4ed6c8614fc4706dee09e68425d0086ce4b4ce47d8f4b9f70013013f1ea4b9ce185a35d2d6951299eba3a3a3a8a830f4c2635c74fcec04ac14")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000b9d6817d5e4461249b5901c8fbb85d0dd68c0ff42b03920ff04ff8f00eb8f6f4000cf3ca06cc84cc1759a9d116b89beba5899fc338a29ecff0dd0bb09afe575a7b")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000bed9ed0323efe2d2b3bfa4f1f74a3e5cacd65e0dc30190e241076f247059282a00a36cc9ae36bb78bef9543169e174cf4bca438ad62866aaaf61554882348afc5f")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00004356b99304f36dc3357c3b22f0a8396142e89037dd8b8eb2a94211f33a8b3c3a00add92b3a7a09e2850d5b06d0658a62ce41e47b032aa6ad24c7ce127676d8c892")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000dea417bbd7de15fbb5f2bc00618bb248f83304c70e50034ae43483f25804b099003a8979bf0995d97fe01bf095c5776a6da0bf3adc02f47b80e8f7aa9b663b5632")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000cc46182a887b2de7270ee55e7dd363b2f3e56c9384d2107e3528ba026e79af9d00646dc7ed94957c1466e792f118ddcfce6c6b1e560821cb91929192a80e2f83bc")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000c3ce6859a5812f36b84212e1970bf30b9f2281a6d13be56ba47381e7d9deae39005cacf6473c4cd8cfeb295e86527f9202ddfde8d310d0fe16c199380d479fc703")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000034da1b3b1be617df647d4a7c1e5ffb47326e7f0a3c5f8a0031134eb33333ab7b006015bd86d4e90bcb6e4964020baafd7b967c0211d285a4aa2e78b0120efa8320")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000745cbbcccabfc7e40774a3cbf1376b544143c3e84962199d6498c108dd96e5680069378bb647354afdaf15037db142278d1d8d28289218094d74163c2d27a84c70")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000048b39028a5076febd58398fc12e6c464432c1a5ba36471cbd974e2ccb50014fe00e178bba60f8f2fe3d627bd02ffbff6d5a3e8c8d6f58b70cdb7c45e886b504d74")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00007fc9e991ff1156dc35d2c6b72f98e4928e05b9288766884f7a0d319a62276027008852fe5aed35fbe5cde2c0c3b7ab3d860a7d48ecee78516acb475a7a4b593985")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00008e8f049533868b0e18729769749d65789e3f40451fa80b260bbdc5bb0314c74a00b35dbb96f371b493cce11ef28f320cd15b5d0c55ff4daa5fea46827dabe7c16c")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000b901b0426192a3cd85d234bf84b8ee5a9f71b78de2acfa7f4b08014052ab67f4002525ad1b9a8d1e4dcfa6233b21336792317c2ed8b030a72ce59991381b17ccf9")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000b8be53bc8d604f0b709a447eb56b9732b921474c52e6ed47103301dd2d089892007e8eca7416f12564248f27d34a2f984245a803a7ad76169681cd54eab9022cdf")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000d6cca4d5ebcb037d650bcb0a42bbeb35d5161a3dc8266c3aa6263aff714435b20034ca3238b4dce77c5e5a4284ae15cee765f5f0e830f5ae16438f2089ed4b3ab2")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00004160393264d2ecfc2d30278733b74daf26b1f708f5851ef9815f237c752d89f5006d42c85805906391a6eaea123e683c7b4388a287197fde83abbc6f7bbbab4c48")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00002602eab1695427d5338522a1ca97b42dbbe8ea46065cb4ed8ee7d358ab578db700a47337f389028d66364f1ec6a9db0cdc666bc62d950464af5362a54aed523e9f")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000dc986142294f530d4e0494a9041f6495e53cfd8bba70d88ad9b3c397c203c1b700c0c2d04e07f28d993023381c105d67ef6638b9d1e7011ca813a8cd8df5dadd2f")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000ad6ba1c1a17b9a955f3e6d7a71570884c0589877fd585cf83150f4962ac4e815008e578237b1c8100f41c169b7a348c39219427362b0defba623d062393a986518")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000cf2e3f7a64cc38c005e9c89858e58909b2005dfe98ca018b9b97e22a7b900d42000c48b361998a5314bcb72519746b96a2629b095bd73ba80810ffb2f67b355c6f")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000998cb287c5011aa0ecefbd59ad00593aec115a373d2b1a34140c3b22631c77c20001a1ad77ff20f640e9427ff237be6c23d2c325847eb589ddc70a4be4bd7ac43b")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000414c473397260fbe2a19411ab3b1008a38a11258113fdc5b7546811ecc0f15890068d5104c1d86acd7e337b707864514614eaab6c8a966e4d97d811810b5c0db8f")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000ce7215fafce2640f401656ebb6b09ee758da84fb76fad27e4496739a9874f6ce009d5abebf51af2de903701bbc6b27a9f86560b5504dc68f68b22875dce9a39ebb")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000064ba01f6bfbe7cc5ac2bc72b7ed1198501edccac0ed215faf817aed17586fb6400950be85ac69ced1cf0e865e496700de8dbe071656d4584bdc0c8dc19ddf01ef8")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00000ea7c568c9c4e7556de76117713cd4695a67d150b9732479b5a84df1ef62d3160076a7c3bc88d58b281a1308116dbb2f9a4fd6c9fc7d5991906d518a002cd3940f")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000d650503d18ac396e9ef0123cdf020a047cdabf75ea13ebfd037d929a42f60e2400024accb0cbf06d417e1da4601af908e13bcbc4e5c24df07ce7b1728e20cdeb73")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000ddb78b14590aa275cb24e4e238d0fe33fa4d796b74ffcd0c5bcb0a0236309e7c0013c6df2f77540b9d3d1a3ec100f7e1c489bd788d345e24bb6ebc412839086f24")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000141f009d0137fff30dbf45ad5d8bce2cf9b17680a072bde6f272c417a79ab2880017a90a45b68c298608d8e23f7e3701d2c68b55fe4f19d7fbdd52fdd0f4b94ed8")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000068462e1a4c581dd73b0f4fab312b73d950c4243d2c3b4713febfaa24379150cc003212002928cd898e30be70724892f329c446d5abd7a28a14318d30fe6aa58188")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00006f278014131a3a117349a9c5a700cb11f105e721c049c2d269e45890838f6ddb005e6e039f784f81789072435c5a59595f5bba3f926a3c5954b5cc454f0877da9e")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000e290b81a8a8bc0275aaf1807ad50ecc8f4937a65dfcd868f67ae94def0a0c0390004ad168a35faec569bedd9ff031295fff6aa7d9dfa10003e5ee4f1fb4c056ae7")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000091e39e5073ed4698b9c94dac6ed193d86afea1a206b2a0f3a0aa2e676a63e3940080fd9461581f98e78fd27e490aa01c7861617ab8773f44a6d3ed148e3e46b552")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000bfe5d8e418a1451178bf01731698bbc0dcb83a1ed834974d22ce454bcbfa2898001c82f660a0d4beee02fb17e19a4dbefde383048c1fce789c5492db097b8cb626")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00002d0b4db78f129e79e9314d2e992fd4632bbadac2b0be4d6ca789341a6f878471003db76f77f61809bb9768f9506643ababba733b8a8391434e119f235bfd40dbd3")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000628c6a514b8e3c3f1fd25ddc36262ce68d003cd4cc70634f0e4cf8a46605ce2a003265f09e32d5d3a7ea1c70f634f8e6fadb632cc0490b83b49d551f4c5a2da4c7")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00002f10e9ffadaca3f6121bfbb011a25f7f574a1f3690785c1ac32b1c805666f31f00548cec15e0cab56c1547f59edf3d49b4a7a4991545f436ad6da15100772e005b")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00005eb303b1d731a46c6cee9469c4e94ed1c2e46d6789e52fc71396a45ef7eef2050027046fdc45bec8b375df8ceebcf94127502db65d814837b265678652d8595712")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000e566ea670e7f73fe25f9871946c3379311faa083784268cac48ad07a0ec3b35a00b7e7ed2ca63703415cb3aea6fc57e89243ab013b06cc0dff3a6c0c65789bdeab")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00008096101953b7b172d90048523974b4dd294e98f7190db197c14616bee0deb0f800095b5c74ae51dd616bcbe19d650dfb269515dac6c1bcf6f706f24e3f56a229b6")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00005c600a540517f1a4546a22115fed92f53a9398d75fd96b74447f29b201bf036600c43a8662d22ae74d2ef845119b9e1776d1b2a74e5276b568f1a9acc240d3fcb3")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000048a3b6b3eb0508b1269d653db2d14c0d5c9b64d033e8f623dd6a8fa85d36c8e500ac9f805e0badf5794f03117608b1cce65192e04e4c66d54405f02bd97bfc073c")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00001d2afef8ca751c7a1a514fc5b25a6d42faaf2f82f920a05ff0a19df250a363ab00542cd7f50df4055674ac233edc1e54313cbbde977e24969cf4d11213abdbd784")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000041b49e58f5b46bf2e92f624b61f01127572d18663f7d478996c251255c9bb81000ef2241a08087d92d198a4f52d90200418566493cfd46053f777e6f2c451918a9")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000bf0f4612b1f23caaca61faef34b8b2f7e38d667f8cee43ffbe48431964ece5d9004ba10667321db377f2d5d4733f9a755546080a416707ef8c8752c3543bd8333c")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00008323d033e6a7cdd6d179e5860a4ddb07046ee6fb09c4e08ef1f5f3803b6de42800835240a3af186c610b174311277e006ae96ce1a80f34671a85d53a063f1e4b4b")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00004ebefcb72cff6e5a5c174f0759af8d522450103940711508f5d05bad79a955be0063f2f2d851a096f84695206e25616e2827b5f042b69f6c778f76644ace324063")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000a670e902768a9f2c3260a224b3b440b68602aada331952d92a1a8a8a7c25d5dc00492077cc0f84ee49fad10418a6b3c8e9da9f94dc4095738b90aeb2e6e1434cfe")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000ef5fa15493054a458e6c86986118901826564e726a64391b953939e4d34d30c6002e717bf129da7d21a8863bfc5a7642c2c71a33ad60eb65a3cd1ca6943bca9863")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000549d151130054abce19da3be55de9a5dceca22116dc372bdb646645152436f7c00170b32ae3e240d24f426e0adabc12078bae73e52246b608d67f41d85ec723d18")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000586a4130e6396df3288b382002bb6133f1626da3a20a98f8491b747a49866eda0065a87317752ace718173a19a20f136e0b2e85995b8203db38aceb0288d4b1681")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00002cff85b942cd409589b163a96db1dfd1910612f2a680ace07f24f37f12d16e8a006a0cdddd8e57bb0a1c1e54b83e2d9f33f213ec40fab9ad5c9d4e9ca8eb996fd6")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000dccae892a46f8587eae71f140856ac8533d6d333ed1f166835df9aa1c2048ecb003c111c738ab7334378ea83dfd63ca4886ece2e317f074a7b816500d5a751c42c")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00006e291aa20984d0291649d629f9f869d0ca8fd1daf951f40106fcdd3c9d44090800e5cae3896e85360a8f93613d893cbbad2be3eb97cfb32f277d05497e55756bfc")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000085348396ba140cf71e9490d33275d34f9331c6c8cf29acb4066b417eec25a68f00d22ed87a25f6816ed2b14cb7b3552581aaec24340eaac2583eb3227b3f33f720")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000048f2dc3b56a266f29c08a44b872244fb5ca7a10848a2468a2987ce820dd0f135007123c8653e4d1eb9de580b8fa1f9d52e9021b3224268bb5e15afea80b959871a")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00001330e2e7103c13ef910079aa16dc47e9c1b84e20fd7be30ebb4d46b3584a085a000a5d6172ef8cbf87e258aa7b3c283a83c465564678c785457145fbfb908fc0d8")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00009dc144ff79f1584657df8d5e6ab3701cc945f65d9563aefc306b9a21b42ea903000248dbda53bb962b301cd4edd8928e0f215afc3a005c6e3882887a0b3a818732")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000f075d38c692ceef1e173a546c57a3bdffad9593981ba187e8841ef2fc612c00a00897fe06e853cf756b0cdcb5cd5bf1414cfde742007ac306e2e968e32913395d7")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000034e49c37f61eb2e9971a1aa96f059b1046fe6ffadc5e26a0fae569f0f39c5b4e00519aa417879bc6ed8c944fbfe35cf4a348a1114a5dcff58929241b6caacab164")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000849f93e2899d39cfb3c33cb768ee54e8053a7000d8e9392fd60f8aaa1bc52044009beca1817b5e1aaf635af79a6aa684ebd0dc3daf9c2492c5a890e9f6ce0cac67")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000a79a0aed7a19edc342bb01f378e039ff4f78f97692aad067f43eba3cb322e2d500618bf52b492f96fd7396c24860052294527ad1311df57ecd2b2b05561a1dd0d8")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000073004a607184d65602d0ff94e2a7cde54e399ce29cd186dbddff6358b369e4e100b179f2804cf15cffef4fc9cf4eef61aa02b28f6ca5d51c191acf1da68a71c5ce")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00001008739e145832cf0127bcfae2404fb60034251fc9776812f9c78ce0b398ff38000b35f956995cc13f3ddbea9c1a1365b461f8d3a9028433a9bd44518015bc4511")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000573fd8422dcf20a9f5a68dfdb579d473c16497f872d6d15efd0d8d7b87a82ed400a7db4681391a88b863ae279d19eb2cf8440fa57a220582928d3816e401b48d9d")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00002cd95cbb64ad2b7c0b2b5e6eea096fe5afd878965c064a3872d08a2cc97d00ba003b616eff7202761c00e1c68e4600b09f0c78a619bda2e4ad4ff8b45aac58ce77")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000536fe8d16270684bac02350f368fe5c45700912b86f3103c85c02a18a7218e4d000ac4f3a187c0c22b57a9ecfb14701f19d4393b404fb65ef42c5f2eec4735d849")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000a1962c993bef33697d1187e20b1f2d0baf822e3a05ff5c60281a8e48c37c9dae006de308542c8397934923c931bf9e3291c82d7fc67d94c7a503d493c78e6c84a3")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00002f28a8b54c80c040a5824d274e8a3e548ad0dcd499e65fda479c1b549ce7e7b800928f120d5f978842773ef74e3272728da7658a660ef03443835b581661066aae")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000c57f3a899354d554fed89685fe883df552d4c0ee7ff425addc4cfa99f369f9b2000e383566341f9aeab4bb68d5b9546d31e4ac5ef74391356ccc6c09b1d2bf9746")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000025586018c92ad894b3aec8ef401c750b73aa5f81db90e4b150ddfa4bb55b627b0055d82b30e2d3e696f2c1ddc1230bd113874f5a6dbf31e3a3a6aba4aabb876741")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000886fe4f6631f7ba5b6bc3b01b1f3f700bbb43fd226579ece01681a18ca01258f0060433de3a036934087f39133c1b54b9218408c8c0ac3af4db7db27c48f184f01")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000869727c02e3c999e6fb4fbded9b1e5fef47dc76946c9cf11e85cbbac7118991900c10f3e08a41c3b488a24c12ad7297781f8ff4c7278a16862a57dfea7595b4445")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000d2743431ee87f3856bb42e01c642f6b9ac830422588feae6ae3dd7da1ff40a6800149536cfc4dcea5dede6ef3e00c1c512dea2747008da98da980a7c2e423a53ce")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000860622cdf99daf4b1dd64be374c399151f8c1b2db3b45317bbe0ecc49746d2f9002fe12562baf53a53c4b7420a41f90df5de4de0bde2071f7ad880f711ee01f766")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000851e02dde8133f74974cd243224e093b80ab94664a09bd3ce2d97184512f0d7400b3b364f6ce9277ec167b049c25b771e17eb87446019116ec23ebef6e96e6cad1")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000bf090a97c8eaa525dbe8ec60495ca970410cd9c8c3c35a4f9693a90af1080c590034a2a8607bf00bbbf8c39084bfd206bf48b8d619bae4b0e1162dbf2c0b65d8e2")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000cff71cd234e5568432b6c34d6ca02a4ef5c3e3f122b97a3b574403a9487e2da90097e9549fd55f5a323287354140cd5c0a034b0c057674ad602ce4f792afa4d2fe")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000021c100ac38248ee620241d47bca00b4726ef84997ef0b29264eb5a3bbd44b176001e41bdb308a91e10c3cb38104b89d310d889c1a3a48ab012ad6554678ab94074")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00004d6592d75f4cd47e5aa883f4fd2a7db2087f763498ff1e8d66d50b347fa5f1e3000ed0db2926365b840d2c87899276d6b1f1e918b25a077cc447bb1f9acc77ea97")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000a71ad72f10015f24379884a6f39bdb8dbf4bc1fc931bcffe25d5adab987d2c33000256ecdf092f3c4d3b61691936937042dab09f7c256f811afaae1dbc2aba1892")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00009d512b99a2bbd0c72e83dcdbc22f16c518e53035591b663356527a21a01133b60058abd9accdef70ae3d7ca6a5fe616887ffd85538f317f8c29449fd0d89893e4a")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000013be53fc9c20ebde4158cec75a84a469c036536e1ffb834ec8cfb8114db4dc70072f0260fad094486e6546a665d2fed58a2a20998d5e11172c581dd95ea937e70")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000944623fe3d2aad94f3586f6020a24b62095aa09028707d9311f589ba0829794b005ad2e648840fb6efd670e443cf683e71fd519e0098400850a6b6f46af00503a4")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000009758378ed86be5e97fd07f8400692ce9ca2944a1d537ef317b97e32ee3bc8e0082345d110ef7d003ef4ac7333245f0f39afe4fd3ca04b25cd3fe93a61acdf68a")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00004a6159a2a09d5b63f3e113aa21127f06293af149abc1e24da753cd280ec175f800727e50b3b461584744552b891f1e8585b718e1dbd9fe509141c55a15629828a0")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000dd5fdc7ae76b1552271a90bbdfba64d3ec4b6c9ba7340e0f1b9973cb45972c4b00edf8230902313b36aeed919d076e2e3a25f2cfa3eeaed665a3eec07fd1d70f90")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000086a0e4d232be41d4b5040a3cb62f5636643521be831fff08d118b5f0c785ef93004d8048195c36a686a1850e58816ae2280a7dac37008ff62eab7bc68975b3b8c7")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000c05557af42b623686ecdec4ddc953828aff76e4b8205cd307f4e1953817c9c57001ca1840f5b551f86d56842c577ae87e7b4a84fa3ed94fd401ecaac63e0c7ecec")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000744c7b44aa7b20604ef6cd98e5a43458e88af25b81ae2a6ac0798b1d592df48b003ba6d736b8f8d1b54ae1daf6355347bf101785d4a3be41d8df29e0d450455cf4")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000c0eb005e0b07a9dcdf445b6e4188f2eec22050962536764ff67ce36cb2cde49400df69a16b1aa18e0bebea3c285e5458e2639efc9a9c511982779c2da9c4560a29")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000088fd5996c5b1d2bb133b941e456d555a3079743f683f498692590ce737fa65ca004a96a1076c36cf443f77a8df2ef7d12b0b5ee687834a5729357675dba1965908")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000b869d0279c0701eba4a9a6049f98771e2ddcd351cdc5e233601eabf79794dea0002ead142a7826d30f3ec38ff207e290f3064e160cda9437c6c832d886935b9508")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000b41d4b44a6df42791b392862acf37b81ecc36efd6dabc52284520e57a1e21ecd008603f5cc090ff0393bcb0f7e967d327c9ada5d6f6c7a0af26942e1bd776578e0")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00002c93aa97727a97b886cd610c2cce0ff7553958fdade040bd3f3ad8fd23221987004cb367a5629337eada5709d4d5adf472438570b7eeddcf5fd1e167e867295413")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00002e174bb66eb72ca7a3407ce8662b962592ab1dbdeb784fbd6bb0ef388d82e89c00826f3b1d22ad0f49cc49a684ca264174dbb10e1294f8f4b07d12274c4160e720")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00003586a6c706fd7ed09f10aaf4caa7f0e8fe656230d6e60f504669cefc86f708f200d6f593a11ad3dfb1b042c612fe28c4c9ad0e538a3a2863d222e37acf60850557")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00001309e79c43826735efe4366f3a0e4cd5680d7542e9f25bc002730bf27bed4c4d0010b806b2bf439b77fe6db884c6cacade482924857e9b682dcabf59baedeaf26d")!),
    ]
    
}

extension ObvContactIdentifier {
    
    @MainActor
    static let sampleDatas: [Self] = ObvCryptoId.sampleDatasForContactCryptoId.map {
        ObvContactIdentifier(contactCryptoId: $0, ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0])
    }
    
}


extension Data {
    
}

extension UID {
    
    @MainActor
    static let sampleDatas: [UID] = (0..<100).map { index in
        var n = index
        let uid = Data(bytes: &n, count: 32)
        return UID(uid: uid)!
    }
    
}

extension URL {
    
    static let serverURL = URL(string: "https://server.dev.olvid.io")!
    
}


extension ObvGroupV2.Identifier {
    
    @MainActor
    static let sampleDatasForServerCategory: [Self] = UID.sampleDatas.prefix(UID.sampleDatas.count/2).map { uid in
        ObvGroupV2.Identifier(groupUID: uid, serverURL: URL.serverURL, category: .server)
    }

    @MainActor
    static let sampleDatasForKeycloakCategory: [Self] = UID.sampleDatas.suffix(UID.sampleDatas.count/2).map { uid in
        ObvGroupV2.Identifier(groupUID: uid, serverURL: URL.serverURL, category: .keycloak)
    }
    
}


extension ObvGroupV2Identifier {
    
    @MainActor
    static let sampleDatasServerCategory: [Self] = ObvGroupV2.Identifier.sampleDatasForServerCategory.map {
        ObvGroupV2Identifier(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0], identifier: $0)
    }

    @MainActor
    static let sampleDatasForKeycloakCategory: [Self] = ObvGroupV2.Identifier.sampleDatasForKeycloakCategory.map {
        ObvGroupV2Identifier(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0], identifier: $0)
    }

}


extension ObvDiscussionIdentifier {

    @MainActor
    static let sampleDatas: [Self] = {
        let maxCount = max(ObvContactIdentifier.sampleDatas.count, ObvGroupV2Identifier.sampleDatasServerCategory.count, ObvGroupV2Identifier.sampleDatasForKeycloakCategory.count)
        var datas: [Self] = []
        for index in 0..<maxCount {
            if index < ObvContactIdentifier.sampleDatas.count {
                datas += [.oneToOne(id: ObvContactIdentifier.sampleDatas[index])]
            }
            if index < ObvGroupV2Identifier.sampleDatasServerCategory.count {
                datas += [.groupV2(id: ObvGroupV2Identifier.sampleDatasServerCategory[index])]
            }
            if index < ObvGroupV2Identifier.sampleDatasForKeycloakCategory.count {
                datas += [.groupV2(id: ObvGroupV2Identifier.sampleDatasForKeycloakCategory[index])]
            }
        }
        return datas
    }()
    
}


extension ObvContentUnavailableView.Model {
    
    @MainActor
    static let sampleData: Self = ObvContentUnavailableView.Model(
        title: "Some title",
        systemIcon: .airplayaudio,
        description: "Some description")
    
}


extension ObvDiscussionsListViewModel.DiscussionIdentifier {
    
    @MainActor
    static let sampleDatas: [Self] = ObvDiscussionIdentifier.sampleDatas.map {
        .obvDiscussionIdentifier($0)
    }
    
}


extension ObvDiscussionsListViewModel {
    
    fileprivate static let numberOfPinnedDiscussions = 5
    
    @MainActor
    static let sampleDatas: [Self] = [
        .init(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0],
              identifiersOfPinnedDiscussions: Array(DiscussionIdentifier.sampleDatas.prefix(numberOfPinnedDiscussions)),
              identifiersOfUnpinnedDiscussions: DiscussionIdentifier.sampleDatas.suffix(DiscussionIdentifier.sampleDatas.count - numberOfPinnedDiscussions),
              contentUnavailableViewModel: ObvContentUnavailableView.Model.sampleData)
    ]
    
}


extension URL {
    
    @MainActor
    private static func photoURL(for contactIdentifier: ObvContactIdentifier) -> URL? {
        guard let index = ObvContactIdentifier.sampleDatas.firstIndex(of: contactIdentifier) else { return nil }
        guard index < photoURLForContacts.count else { return nil }
        return photoURLForContacts[index]
    }
    
    @MainActor
    private static func photoURL(for groupV2Identifier: ObvGroupV2Identifier) -> URL? {
        guard let index = ObvGroupV2Identifier.sampleDatasServerCategory.firstIndex(of: groupV2Identifier) ?? ObvGroupV2Identifier.sampleDatasForKeycloakCategory.firstIndex(of: groupV2Identifier)  else { return nil }
        guard index < photoURLForGroups.count else { return nil }
        return photoURLForGroups[index]
    }
    
    @MainActor private static let photoURLForContacts: [URL] = [
        URL(string: "https://dev.olvid.io/avatar00")!,
        URL(string: "https://dev.olvid.io/avatar01")!,
        URL(string: "https://dev.olvid.io/avatar02")!,
    ]

    @MainActor private static let photoURLForGroups: [URL] = [
        URL(string: "https://dev.olvid.io/group00")!,
        URL(string: "https://dev.olvid.io/group01")!,
        URL(string: "https://dev.olvid.io/group02")!,
    ]

    @MainActor static let photoURLs: [URL] = [
        URL(string: "https://dev.olvid.io/avatar00")!,
        URL(string: "https://dev.olvid.io/avatar01")!,
        URL(string: "https://dev.olvid.io/avatar02")!,
        URL(string: "https://dev.olvid.io/avatar03")!,
        URL(string: "https://dev.olvid.io/avatar04")!,
        URL(string: "https://dev.olvid.io/avatar05")!,
        URL(string: "https://dev.olvid.io/avatar06")!,
    ]

    

    @MainActor
    static func photoURL(for discussionIdentifier: ObvDiscussionIdentifier) -> URL? {
        switch discussionIdentifier {
        case .oneToOne(let id):
            return photoURL(for: id)
        case .groupV1:
            return nil
        case .groupV2(let id):
            return photoURL(for: id)
        }
    }
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId[0]:
            return Self.photoURLs[0]
        case ObvCryptoId.sampleDatasForOwnedCryptoId[1]:
            return Self.photoURLs[1]
        case ObvCryptoId.sampleDatasForOwnedCryptoId[2]:
            return Self.photoURLs[2]
        case ObvCryptoId.sampleDatasForOwnedCryptoId[3]:
            return Self.photoURLs[3]
        default:
            return Self.photoURLs[4]
        }
    }

}

extension Date {
    
    @MainActor
    private static let sampleData: [Self] = (0..<200).map { offset in
        Date(timeIntervalSinceNow: -Double(offset))
    }
    
    @MainActor
    static func sampleDate(for discussionIdentifier: ObvDiscussionIdentifier) -> Self {
        guard let index = ObvDiscussionIdentifier.sampleDatas.firstIndex(of: discussionIdentifier) else { return .now }
        guard index < Self.sampleData.count else { return .now }
        return Self.sampleData[index]
    }
}


extension UIImage {
    
    @MainActor static func avatarImageForURL(_ url: URL) -> UIImage? {
        guard let name = url.absoluteString.split(separator: "/").last else { return nil }
        return UIImage(named: String(name), in: ObvDiscussionsListResources.bundle, compatibleWith: nil)
    }
    
}


extension Color {
    
    static let count: Int = 200
    
    static let sampleDatasForForeground: [Self] = {
        var colors: [Color] = []
        for _ in 0..<Self.count {
            let red = CGFloat.random(in: 0...1)
            let green = CGFloat.random(in: 0...1)
            let blue = CGFloat.random(in: 0...1)
            let color = Color(red: red, green: green, blue: blue)
            colors.append(color)
        }
        return colors
    }()

    static let sampleDatasForBackground: [Self] = {
        var colors: [Color] = []
        for _ in 0..<Self.count {
            let red = CGFloat.random(in: 0...1)
            let green = CGFloat.random(in: 0...1)
            let blue = CGFloat.random(in: 0...1)
            let color = Color(red: red, green: green, blue: blue)
            colors.append(color)
        }
        return colors
    }()

}


extension ObvAvatarViewModel.Colors {
    
    static let sampleDatas: [Self] = (0..<Color.count).map { index in
        ObvAvatarViewModel.Colors(foreground: UIColor(Color.sampleDatasForForeground[index]), background: UIColor(Color.sampleDatasForBackground[index]))
    }
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId[0]:
            return .init(foreground: .systemBlue, background: .systemRed)
        case ObvCryptoId.sampleDatasForOwnedCryptoId[1]:
            return .init(foreground: .systemPink, background: .systemBlue)
        case ObvCryptoId.sampleDatasForOwnedCryptoId[2]:
            return .init(foreground: .systemCyan, background: .systemPink)
        case ObvCryptoId.sampleDatasForOwnedCryptoId[3]:
            return .init(foreground: .systemOrange, background: .systemCyan)
        default:
            return .init(foreground: .systemPink, background: .systemCyan)
        }
    }

}

extension ObvAvatarViewModel.CharacterOrIcon {
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId[0]:
            return .character("A")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[1]:
            return .character("B")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[2]:
            return .character("C")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[3]:
            return .character("D")
        default:
            return .character("Z")
        }
    }

    
}


extension ObvAvatarViewModel {
    
    @MainActor
    static func sampleData(for discussionIdentifier: ObvDiscussionIdentifier) -> Self {
        switch discussionIdentifier {
        case .oneToOne:
            return .init(characterOrIcon: .icon(.person), colors: ObvAvatarViewModel.Colors.sampleDatas.randomElement()!, photoURL: URL.photoURL(for: discussionIdentifier))
        case .groupV1:
            return .init(characterOrIcon: .icon(.person3), colors: ObvAvatarViewModel.Colors.sampleDatas.randomElement()!, photoURL: URL.photoURL(for: discussionIdentifier))
        case .groupV2:
            return .init(characterOrIcon: .icon(.person3), colors: ObvAvatarViewModel.Colors.sampleDatas.randomElement()!, photoURL: URL.photoURL(for: discussionIdentifier))
        }
    }
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(characterOrIcon: .character("A"),
              colors: Colors.sampleDatas[0],
              photoURL: URL.photoURLs[0]),
        .init(characterOrIcon: .character("B"),
              colors: Colors.sampleDatas[1],
              photoURL: URL.photoURLs[1]),
    ]

    @MainActor
    static func sampleDatasForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        return .init(characterOrIcon: CharacterOrIcon.sampleDataForOwnedCryptoId(ownedCryptoId),
                     colors: Colors.sampleDataForOwnedCryptoId(ownedCryptoId),
                     photoURL: URL.sampleDataForOwnedCryptoId(ownedCryptoId))
    }

}


extension String {
    
    static let sampleFirstNames = [
        "Adam", "Aelara", "Alice", "Ambrose", "Aurelia", "Aurelius", "Bastian", "Bastien", "Bella", "Bob",
        "Bram", "Briar", "Brielle", "Calanthe", "Caleb", "Caspian", "Cassian", "Cassiopeia", "Charlie", "Dagny",
        "Dahlia", "Darian", "Dashiell", "David", "Diana", "Elowen", "Eolande", "Evadne", "Evander", "Eve",
        "Fable", "Faelan", "Finnian", "Frank", "Gideon", "Giselle", "Grace", "Gwendolyn", "Hannah", "Harlow",
        "Havoc", "Hermione", "Ianthe", "Icarus", "Isolde", "Ivy", "Jack", "Jareth", "Jasper", "Jocasta",
        "Jolene", "Kael", "Kaelani", "Kate", "Lavinia", "Leo", "Lirien", "Maelis", "Marcel", "Mia",
        "Mireille", "Nerys", "Noah", "Nyx", "Olivia", "Orian", "Orion", "Paul", "Percival", "Peregrine",
        "Pipo", "Quilla", "Quinn", "Quintessa", "Rachel", "Roland", "Rune", "Sam", "Seraphina", "Sylvie",
        "Thaddeus", "Thisbe", "Tina", "Ulysses", "Ursula", "Vesper", "Victor", "Vivienne", "Wendy", "Willa",
        "Wren", "Xanthe", "Xavier", "Yara", "Yseult", "Zara", "Zephyr", "Zephyrine", "Zoe", "Zoup",
    ]

    private static let sampleLastNames = [
        "Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez",
        "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin",
        "Lee", "Perez", "Thompson", "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson",
        "Walker", "Young", "Allen", "King", "Wright", "Scott", "Torres", "Nguyen", "Hill", "Flores",
        "Green", "Adams", "Nelson", "Baker", "Hall", "Rivera", "Campbell", "Mitchell", "Carter", "Roberts",
        "Gomez", "Phillips", "Evans", "Turner", "Diaz", "Parker", "Cruz", "Edwards", "Collins", "Reyes",
        "Stewart", "Morris", "Morales", "Murphy", "Cook", "Rogers", "Gutierrez", "Ortiz", "Morgan", "Cooper",
        "Peterson", "Bailey", "Reed", "Kelly", "Howard", "Ramos", "Kim", "Cox", "Ward", "Richardson",
        "Watson", "Brooks", "Chavez", "Wood", "James", "Bennett", "Gray", "Mendoza", "Ruiz", "Hughes",
        "Price", "Alvarez", "Castillo", "Sanders", "Patel", "Plop", "Qwartz", "Milop", "Stopil", "Guolp",
    ]

    
    private static let sampleGroupNames: [String] = (0..<100).map { _ in
        let firstName = String.sampleFirstNames.randomElement()!
        let lastName = String.sampleLastNames.randomElement()!
        return "Group with \(firstName) \(lastName)"
    }
    
    
    @MainActor
    fileprivate static let sampleTitles: [ObvDiscussionIdentifier: String] = {
        var datas = [ObvDiscussionIdentifier: String]()
        for discussionIdentifier in ObvDiscussionIdentifier.sampleDatas {
            switch discussionIdentifier {
            case .oneToOne:
                let firstName = String.sampleFirstNames.randomElement()!
                let lastName = String.sampleLastNames.randomElement()!
                let title: String = "\(firstName) \(lastName)"
                datas[discussionIdentifier] = title
            case .groupV1, .groupV2:
                let title = String.sampleGroupNames.randomElement()!
                datas[discussionIdentifier] = title
            }
        }
        return datas
    }()

}


extension String {
    
    @MainActor
    private static let words: [String] = [
        "Lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit",
        "sed", "do", "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore",
    ]
    
    @MainActor
    private static let sampleMessages: [String] = (0..<200).map { _ in
        let message: String = (0..<10).map({ _ in Self.words.randomElement()! }).joined(separator: " ")
        return message
    }
    
    @MainActor
    static func sampleMessageBody(for discussionIdentifier: ObvDiscussionIdentifier) -> String {
        guard let index = ObvDiscussionIdentifier.sampleDatas.firstIndex(of: discussionIdentifier) else { return "" }
        guard index < Self.sampleMessages.count else { return "" }
        return Self.sampleMessages[index]
    }
    
}


extension ObvDiscussionCellViewModel.Message.Kind {
    
    @MainActor
    private static let sampleKinds: [ObvDiscussionCellViewModel.Message.Kind] = (0..<200).map { _ in
        let kind: ObvDiscussionCellViewModel.Message.Kind = Bool.random() ? .received : .sent(status: ObvDiscussionCellViewModel.Message.SentStatus.allCases.randomElement()!, messageHasMoreThanOneRecipient: Bool.random())
        return kind
    }
    
    @MainActor
    static func sampleKind(for discussionIdentifier: ObvDiscussionIdentifier) -> ObvDiscussionCellViewModel.Message.Kind {
        guard let index = ObvDiscussionIdentifier.sampleDatas.firstIndex(of: discussionIdentifier) else { return .sent(status: .fullyDeliveredAndFullyRead, messageHasMoreThanOneRecipient: Bool.random()) }
        guard index < Self.sampleKinds.count else { return .sent(status: .fullyDeliveredAndPartiallyRead, messageHasMoreThanOneRecipient: Bool.random()) }
        return Self.sampleKinds[index]
    }
    
}


extension ObvDiscussionCellViewModel.Message {
    
    @MainActor
    static func sampleMessage(for discussionIdentifier: ObvDiscussionIdentifier) -> ObvDiscussionCellViewModel.Message {
        let body = AttributedString(String.sampleMessageBody(for: discussionIdentifier)) 
        let kind = ObvDiscussionCellViewModel.Message.Kind.sampleKind(for: discussionIdentifier)
        let message = ObvDiscussionCellViewModel.Message(body: body, kind: kind)
        return message
    }
    
}


extension Int {
    
    @MainActor
    private static let sampleNumberOfNewReceivedMessages: [Int: Int] = {
        var datas: [Int: Int] = [:]
        (0..<10).forEach { index in
            datas[index] = Int.random(in: 0...10)
        }
        return datas
    }()
    
    @MainActor
    static func sampleNumberOfNewReceivedMessages(for discussionIdentifier: ObvDiscussionIdentifier) -> Int {
        guard let index = ObvDiscussionIdentifier.sampleDatas.firstIndex(of: discussionIdentifier) else { return 0 }
        guard index < sampleNumberOfNewReceivedMessages.count else { return 0 }
        return sampleNumberOfNewReceivedMessages[index] ?? 0
    }
    
}

extension Bool {
    
    @MainActor
    static func sampleIsPinned(for discussionIdentifier: ObvDiscussionIdentifier) -> Bool {
        guard let index = ObvDiscussionIdentifier.sampleDatas.firstIndex(of: discussionIdentifier) else { return false }
        return index < ObvDiscussionsListViewModel.numberOfPinnedDiscussions
    }
    
}


extension ObvDiscussionCellViewModel {
    
    @MainActor
    private static func sampleData(for discussionIdentifier: ObvDiscussionIdentifier) -> Self {
        .init(avatarModel: ObvAvatarViewModel.sampleData(for: discussionIdentifier),
              title: String.sampleTitles[discussionIdentifier]!,
              date: Date.sampleDate(for: discussionIdentifier),
              message: ObvDiscussionCellViewModel.Message.sampleMessage(for: discussionIdentifier),
              numberOfNewReceivedMessages: Int.sampleNumberOfNewReceivedMessages(for: discussionIdentifier),
              showGreenShield: Bool.random(),
              showRedShield: Bool.random(),
              aNewReceivedMessageDoesMentionOwnedIdentity: Bool.random(),
              shouldMuteNotifications: Bool.random(),
              isArchived: Bool.random(),
              isPinned: Bool.sampleIsPinned(for: discussionIdentifier),
              isMuted: Bool.random())
    }

    
    @MainActor
    static func sampleData(for discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) -> Self {
        switch discussionIdentifier {
        case .obvDiscussionIdentifier(let obvDiscussionIdentifier):
            return sampleData(for: obvDiscussionIdentifier)
        case .persistedDiscussionObjectID:
            assertionFailure()
            return ObvDiscussionCellViewModel.sampleData(for: ObvDiscussionIdentifier.sampleDatas.first!)
        }
    }
    
    func copyWith(newNumberOfNewReceivedMessages: Int) -> Self {
        return Self.init(avatarModel: avatarModel,
                         title: title,
                         date: date,
                         message: message,
                         numberOfNewReceivedMessages: newNumberOfNewReceivedMessages,
                         showGreenShield: showGreenShield,
                         showRedShield: showRedShield,
                         aNewReceivedMessageDoesMentionOwnedIdentity: aNewReceivedMessageDoesMentionOwnedIdentity,
                         shouldMuteNotifications: shouldMuteNotifications,
                         isArchived: isArchived,
                         isPinned: isPinned,
                         isMuted: isMuted)
    }
    
}


extension ObvLocationsCellViewModel {
    
    @MainActor
    static let sampleData: [ObvLocationsCellViewModel] = [
        .init(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0],
              numberOfLocationsReceivedForTheCurrentOwnedCryptoId: 0,
              someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: false),
        .init(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0],
              numberOfLocationsReceivedForTheCurrentOwnedCryptoId: 1,
              someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: false),
        .init(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0],
              numberOfLocationsReceivedForTheCurrentOwnedCryptoId: 2,
              someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: false),
        .init(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0],
              numberOfLocationsReceivedForTheCurrentOwnedCryptoId: 0,
              someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: true),
        .init(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0],
              numberOfLocationsReceivedForTheCurrentOwnedCryptoId: 3,
              someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: true),
    ]
    
}


extension ObvProfilePictureBarButtonItemViewModel {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0],
              avatarModel: ObvAvatarViewModel.sampleDatas[0],
              showGreenShield: false,
              showRedDot: false),
        .init(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[1],
              avatarModel: ObvAvatarViewModel.sampleDatas[1],
              showGreenShield: false,
              showRedDot: false),
    ]
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        let avatarModel = ObvAvatarViewModel.sampleDatasForOwnedCryptoId(ownedCryptoId)
        return .init(ownedCryptoId: ownedCryptoId, avatarModel: avatarModel,
                     showGreenShield: false,
                     showRedDot: false)
    }
    
}


extension String {
    
    @MainActor
    static func sampleNamesForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> (title: String, subtitle: String) {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId[0]:
            return ("Adam Johnson", "Subtitle")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[1]:
            return ("Diana Torres", "Subtitle")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[2]:
            return ("Jack Richardson", "Subtitle")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[3]:
            return ("Seraphina Alvarez", "Subtitle")
        default:
            return ("Thaddeus Walker", "Subtitle")
        }
    }
    
}


extension OwnedIdentityChooserViewModel.OwnedIdentity {
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> OwnedIdentityChooserViewModel.OwnedIdentity {
        return OwnedIdentityChooserViewModel.OwnedIdentity(
            ownedCryptoId: ownedCryptoId,
            avatarViewModel: ObvAvatarViewModel.sampleDatasForOwnedCryptoId(ownedCryptoId),
            title: String.sampleNamesForOwnedCryptoId(ownedCryptoId).title,
            subtitle: String.sampleNamesForOwnedCryptoId(ownedCryptoId).subtitle,
            totalBadgeCount: Int.random(in: 0..<10),
            showGreenShield: Bool.random(),
            showRedShield: Bool.random(),
            showHiddenProfileIcon: Bool.random())
    }
    
}


extension OwnedIdentityChooserViewModel {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(ownedIdentities: ObvCryptoId.sampleDatasForOwnedCryptoId.map({
                  OwnedIdentityChooserViewModel.OwnedIdentity.sampleDataForOwnedCryptoId($0)
              })),
    ]
    
}


#endif
