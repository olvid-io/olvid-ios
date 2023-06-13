/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvUICoreData


extension NotificationSound {
    
    public var description: String {
        switch self {
        case .none: return CommonString.Title.noNotificationSounds
        case .system: return CommonString.Title.systemSound

        case .busy:                 return "BUSY".localizedString
        case .chime:                return "CHIME".localizedString
        case .cinemaBringTheDrama:  return "BRING_THE_DRAMA".localizedString
        case .frenzy:               return "FRENZY".localizedString
        case .hornBoat:             return "HORN_BOAT".localizedString
        case .hornBus:              return "HORN_BUS".localizedString
        case .hornCar:              return "HORN_CAR".localizedString
        case .hornDixie:            return "HORN_DIXIE".localizedString
        case .hornTaxi:             return "HORN_TAXI".localizedString
        case .hornTrain1:           return "HORN_TRAIN_1".localizedString
        case .hornTrain2:           return "HORN_TRAIN_2".localizedString
        case .paranoid:             return "PARANOID".localizedString
        case .weird:                return "WEIRD".localizedString

        case .birdCardinal:     return "BIRD_CARDINAL".localizedString
        case .birdCoqui:        return "BIRD_COQUI".localizedString
        case .birdCrow:         return "BIRD_CROW".localizedString
        case .birdCuckoo:       return "BIRD_CUCKOO".localizedString
        case .birdDuckQuack:    return "BIRD_DUCK_QUACK".localizedString
        case .birdDuckQuacks:   return "BIRD_DUCK_QUACKS".localizedString
        case .birdEagle:        return "BIRD_EAGLE".localizedString
        case .birdInForest:     return "BIRD_IN_FOREST".localizedString
        case .birdMagpie:       return "BIRD_MAGPIE".localizedString
        case .birdOwlHorned:    return "BIRD_OWL_HORNED".localizedString
        case .birdOwlTawny:     return "BIRD_OWL_TAWNY".localizedString
        case .birdTweet:        return "BIRD_TWEET".localizedString
        case .birdWarning:      return "BIRD_WARNING".localizedString
        case .chickenRooster:   return "CHICKEN_ROOSTER".localizedString
        case .chickenRoster:    return "CHICKEN_ROSTER".localizedString
        case .chicken:          return "CHICKEN".localizedString
        case .cicada:           return "CICADA".localizedString
        case .cowMoo:           return "COW_MOO".localizedString
        case .elephant:         return "ELEPHANT".localizedString
        case .felinePanthera:   return "PANTHERA".localizedString
        case .felineTiger:      return "TIGER".localizedString
        case .frog:             return "FROG".localizedString
        case .goat:             return "GOAT".localizedString
        case .horseWhinnies:    return "HORSE_WHINNIES".localizedString
        case .puppy:            return "PUPPY".localizedString
        case .sheep:            return "SHEEP".localizedString
        case .turkeyGobble:     return "TURKEY_GOBBLE".localizedString
        case .turkeyNoises:     return "TURKEY_NOISES".localizedString

        case .bell:         return "BELL".localizedString
        case .block:        return "BLOCK".localizedString
        case .calm:         return "CALM".localizedString
        case .cloud:        return "CLOUD".localizedString
        case .heyChamp:     return "HEY_CHAMP".localizedString
        case .kotoNeutral:  return "KOTO".localizedString
        case .modular:      return "MODULAR".localizedString
        case .oringz452:    return "ORINGZ".localizedString
        case .polite:       return "POLITE".localizedString
        case .sonar:        return "SONAR".localizedString
        case .strike:       return "STRIKE".localizedString
        case .unphased:     return "UNPHASED".localizedString
        case .unstrung:     return "UNSTRUNG".localizedString
        case .woodblock:    return "WOODBLOCK".localizedString

        case .areYouKidding:        return "ARE_YOU_KIDDING".localizedString
        case .circusClownHorn:      return "CIRCUS_CLOWN_HORN".localizedString
        case .enoughWithTheRalking: return "ENOUGH_WITH_THE_TALKING".localizedString
        case .funnyFanfare:         return "FUNNY_FANFARE".localizedString
        case .nestling:             return "NESTLING".localizedString
        case .niceCut:              return "NICE_CUT".localizedString
        case .ohReally:             return "OH_REALLY".localizedString
        case .springy:              return "SPRINGY".localizedString

        case .bassoon:          return "BASSOON".localizedString
        case .brass:            return "BRASS".localizedString
        case .clarinet:         return "CLARINET".localizedString
        case .clav_fly:         return "CLAV_FLY".localizedString
        case .clav_guitar:      return "CLAV_GUITAR".localizedString
        case .flute:            return "FLUTE".localizedString
        case .glockenspiel:     return "GLOCKENSPIEL".localizedString
        case .harp:             return "HARP".localizedString
        case .koto:             return "KOTO".localizedString
        case .oboe:             return "OBOE".localizedString
        case .piano:            return "PIANO".localizedString
        case .pipa:             return "PIPA".localizedString
        case .saxo:             return "SAXO".localizedString
        case .strings:          return "STRINGS".localizedString
        case .synth_airship:    return "SYNTH_AIRSHIP".localizedString
        case .synth_chordal:    return "SYNTH_CHORDAL".localizedString
        case .synth_cosmic:     return "SYNTH_COSMIC".localizedString
        case .synth_droplets:   return "SYNTH_DROPLETS".localizedString
        case .synth_emotive:    return "SYNTH_EMOTIVE".localizedString
        case .synth_fm:         return "SYNTH_FM".localizedString
        case .synth_lush_arp:   return "SYNTH_LUSHARP".localizedString
        case .synth_pecussive:  return "SYNTH_PECUSSIVE".localizedString
        case .synth_quantizer:  return "SYNTH_QUANTIZER".localizedString
        }
    }

    
}


fileprivate extension String {
    var localizedString: String {
        NSLocalizedString(self, comment: "")
    }
}
