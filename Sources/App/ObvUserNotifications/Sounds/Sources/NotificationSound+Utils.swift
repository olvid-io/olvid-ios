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
//import ObvUICoreData
//import ObvSettings


extension NotificationSound {
    
    public var description: String {
        switch self {
        case .none: return NSLocalizedString("NO_SOUNDS", comment: "Title")
        case .system: return NSLocalizedString("SYSTEM_SOUND", comment: "Title")

        case .busy:                 return NSLocalizedString("BUSY", comment: "")
        case .chime:                return NSLocalizedString("CHIME", comment: "")
        case .cinemaBringTheDrama:  return NSLocalizedString("BRING_THE_DRAMA", comment: "")
        case .frenzy:               return NSLocalizedString("FRENZY", comment: "")
        case .hornBoat:             return NSLocalizedString("HORN_BOAT", comment: "")
        case .hornBus:              return NSLocalizedString("HORN_BUS", comment: "")
        case .hornCar:              return NSLocalizedString("HORN_CAR", comment: "")
        case .hornDixie:            return NSLocalizedString("HORN_DIXIE", comment: "")
        case .hornTaxi:             return NSLocalizedString("HORN_TAXI", comment: "")
        case .hornTrain1:           return NSLocalizedString("HORN_TRAIN_1", comment: "")
        case .hornTrain2:           return NSLocalizedString("HORN_TRAIN_2", comment: "")
        case .paranoid:             return NSLocalizedString("PARANOID", comment: "")
        case .weird:                return NSLocalizedString("WEIRD", comment: "")

        case .birdCardinal:     return NSLocalizedString("BIRD_CARDINAL", comment: "")
        case .birdCoqui:        return NSLocalizedString("BIRD_COQUI", comment: "")
        case .birdCrow:         return NSLocalizedString("BIRD_CROW", comment: "")
        case .birdCuckoo:       return NSLocalizedString("BIRD_CUCKOO", comment: "")
        case .birdDuckQuack:    return NSLocalizedString("BIRD_DUCK_QUACK", comment: "")
        case .birdDuckQuacks:   return NSLocalizedString("BIRD_DUCK_QUACKS", comment: "")
        case .birdEagle:        return NSLocalizedString("BIRD_EAGLE", comment: "")
        case .birdInForest:     return NSLocalizedString("BIRD_IN_FOREST", comment: "")
        case .birdMagpie:       return NSLocalizedString("BIRD_MAGPIE", comment: "")
        case .birdOwlHorned:    return NSLocalizedString("BIRD_OWL_HORNED", comment: "")
        case .birdOwlTawny:     return NSLocalizedString("BIRD_OWL_TAWNY", comment: "")
        case .birdTweet:        return NSLocalizedString("BIRD_TWEET", comment: "")
        case .birdWarning:      return NSLocalizedString("BIRD_WARNING", comment: "")
        case .chickenRooster:   return NSLocalizedString("CHICKEN_ROOSTER", comment: "")
        case .chickenRoster:    return NSLocalizedString("CHICKEN_ROSTER", comment: "")
        case .chicken:          return NSLocalizedString("CHICKEN", comment: "")
        case .cicada:           return NSLocalizedString("CICADA", comment: "")
        case .cowMoo:           return NSLocalizedString("COW_MOO", comment: "")
        case .elephant:         return NSLocalizedString("ELEPHANT", comment: "")
        case .felinePanthera:   return NSLocalizedString("PANTHERA", comment: "")
        case .felineTiger:      return NSLocalizedString("TIGER", comment: "")
        case .frog:             return NSLocalizedString("FROG", comment: "")
        case .goat:             return NSLocalizedString("GOAT", comment: "")
        case .horseWhinnies:    return NSLocalizedString("HORSE_WHINNIES", comment: "")
        case .puppy:            return NSLocalizedString("PUPPY", comment: "")
        case .sheep:            return NSLocalizedString("SHEEP", comment: "")
        case .turkeyGobble:     return NSLocalizedString("TURKEY_GOBBLE", comment: "")
        case .turkeyNoises:     return NSLocalizedString("TURKEY_NOISES", comment: "")

        case .bell:         return NSLocalizedString("BELL", comment: "")
        case .block:        return NSLocalizedString("BLOCK", comment: "")
        case .calm:         return NSLocalizedString("CALM", comment: "")
        case .cloud:        return NSLocalizedString("CLOUD", comment: "")
        case .heyChamp:     return NSLocalizedString("HEY_CHAMP", comment: "")
        case .kotoNeutral:  return NSLocalizedString("KOTO", comment: "")
        case .modular:      return NSLocalizedString("MODULAR", comment: "")
        case .oringz452:    return NSLocalizedString("ORINGZ", comment: "")
        case .polite:       return NSLocalizedString("POLITE", comment: "")
        case .sonar:        return NSLocalizedString("SONAR", comment: "")
        case .strike:       return NSLocalizedString("STRIKE", comment: "")
        case .unphased:     return NSLocalizedString("UNPHASED", comment: "")
        case .unstrung:     return NSLocalizedString("UNSTRUNG", comment: "")
        case .woodblock:    return NSLocalizedString("WOODBLOCK", comment: "")

        case .areYouKidding:        return NSLocalizedString("ARE_YOU_KIDDING", comment: "")
        case .circusClownHorn:      return NSLocalizedString("CIRCUS_CLOWN_HORN", comment: "")
        case .enoughWithTheRalking: return NSLocalizedString("ENOUGH_WITH_THE_TALKING", comment: "")
        case .funnyFanfare:         return NSLocalizedString("FUNNY_FANFARE", comment: "")
        case .nestling:             return NSLocalizedString("NESTLING", comment: "")
        case .niceCut:              return NSLocalizedString("NICE_CUT", comment: "")
        case .ohReally:             return NSLocalizedString("OH_REALLY", comment: "")
        case .springy:              return NSLocalizedString("SPRINGY", comment: "")

        case .bassoon:          return NSLocalizedString("BASSOON", comment: "")
        case .brass:            return NSLocalizedString("BRASS", comment: "")
        case .clarinet:         return NSLocalizedString("CLARINET", comment: "")
        case .clav_fly:         return NSLocalizedString("CLAV_FLY", comment: "")
        case .clav_guitar:      return NSLocalizedString("CLAV_GUITAR", comment: "")
        case .flute:            return NSLocalizedString("FLUTE", comment: "")
        case .glockenspiel:     return NSLocalizedString("GLOCKENSPIEL", comment: "")
        case .harp:             return NSLocalizedString("HARP", comment: "")
        case .koto:             return NSLocalizedString("KOTO", comment: "")
        case .oboe:             return NSLocalizedString("OBOE", comment: "")
        case .piano:            return NSLocalizedString("PIANO", comment: "")
        case .pipa:             return NSLocalizedString("PIPA", comment: "")
        case .saxo:             return NSLocalizedString("SAXO", comment: "")
        case .strings:          return NSLocalizedString("STRINGS", comment: "")
        case .synth_airship:    return NSLocalizedString("SYNTH_AIRSHIP", comment: "")
        case .synth_chordal:    return NSLocalizedString("SYNTH_CHORDAL", comment: "")
        case .synth_cosmic:     return NSLocalizedString("SYNTH_COSMIC", comment: "")
        case .synth_droplets:   return NSLocalizedString("SYNTH_DROPLETS", comment: "")
        case .synth_emotive:    return NSLocalizedString("SYNTH_EMOTIVE", comment: "")
        case .synth_fm:         return NSLocalizedString("SYNTH_FM", comment: "")
        case .synth_lush_arp:   return NSLocalizedString("SYNTH_LUSHARP", comment: "")
        case .synth_pecussive:  return NSLocalizedString("SYNTH_PECUSSIVE", comment: "")
        case .synth_quantizer:  return NSLocalizedString("SYNTH_QUANTIZER", comment: "")
        }
    }

}
