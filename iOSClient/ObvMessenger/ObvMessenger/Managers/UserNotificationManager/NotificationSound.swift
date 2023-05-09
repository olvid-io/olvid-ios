/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import UIKit
import AVFoundation
import ObvCrypto
import ObvUI
import ObvTypes


enum Note: Int, CaseIterable {
    case C = 0
    case Csharp
    case D
    case Dsharp
    case E
    case F
    case Fsharp
    case G
    case Gsharp
    case A
    case Asharp
    case B
    case C2

    var identifier: String { String(describing: self) }
    var description: String { NSLocalizedString(identifier, comment: "") }
    var index: String { String(format: "%02d", rawValue+1) }

    static func random() -> Note {
        let i = Int.random(in: 0..<Note.allCases.count)
        return Note(rawValue: i) ?? .C
    }


    static func generateNote(from string: String) -> Note {
        guard let data = string.data(using: .utf8) else {
            assertionFailure(); return .C
        }
        let noteRawValue = data.hashValue % allCases.count
        return Note(rawValue: noteRawValue) ?? .C
    }

}


enum OptionalNotificationSound: Identifiable, Hashable {
    case none // Global default setting
    case some(NotificationSound)

    var id: String {
        switch self {
        case .none: return "_None"
        case .some(let sound): return sound.identifier
        }
    }
    init(_ value: NotificationSound?) {
        if let value = value {
            self = .some(value)
        } else {
            self = .none
        }
    }
    var value: NotificationSound? {
        switch self {
        case .none: return nil
        case .some(let sound): return sound
        }
    }
}

enum NeutralToneCategory: String, CaseIterable {
    case neutral
    case alarm
    case animal
    case toy

    var title: String {
        switch self {
        case .neutral: return NSLocalizedString("NOTIFICATION_SOUNDS_NEUTRAL_CATEGORY_TITLE", comment: "")
        case .alarm: return NSLocalizedString("NOTIFICATION_SOUNDS_ALARM_CATEGORY_TITLE", comment: "")
        case .animal: return NSLocalizedString("NOTIFICATION_SOUNDS_ANIMAL_CATEGORY_TITLE", comment: "")
        case .toy: return NSLocalizedString("NOTIFICATION_SOUNDS_TOY_CATEGORY_TITLE", comment: "")
        }
    }

    var icon: SystemIcon {
        switch self {
        case .neutral: return .musicNote
        case .alarm: return .alarm
        case .animal: return .tortoise
        case .toy: return .umbrella
        }
    }
}

fileprivate extension String {
    var localizedString: String {
        NSLocalizedString(self, comment: "")
    }
}

enum NotificationSound: String, Sound, CaseIterable {
    case none = ""
    case system = "SYSTEM"

    case busy = "alarm-busy.caf"
    case chime = "alarm-chime.caf"
    case cinemaBringTheDrama = "alarm-cinema-bring-the-drama.caf"
    case frenzy = "alarm-frenzy.caf"
    case hornBoat = "alarm-horn-boat.caf"
    case hornBus = "alarm-horn-bus.caf"
    case hornCar = "alarm-horn-car.caf"
    case hornDixie = "alarm-horn-dixie.caf"
    case hornTaxi = "alarm-horn-taxi.caf"
    case hornTrain1 = "alarm-horn-Train-1.caf"
    case hornTrain2 = "alarm-horn-Train-2.caf"
    case paranoid = "alarm-paranoid.caf"
    case weird = "alarm-Weird.caf"

    case birdCardinal = "animal-bird-Cardinal.caf"
    case birdCoqui = "animal-bird-Coqui.caf"
    case birdCrow = "animal-bird-Crow.caf"
    case birdCuckoo = "animal-bird-Cuckoo.caf"
    case birdDuckQuack = "animal-bird-Duck-Quack.caf"
    case birdDuckQuacks = "animal-bird-Duck-Quacks.caf"
    case birdEagle = "animal-bird-Eagle.caf"
    case birdInForest = "animal-bird-in-forest.caf"
    case birdMagpie = "animal-bird-Magpie.caf"
    case birdOwlHorned = "animal-bird-Owl-horned.caf"
    case birdOwlTawny = "animal-bird-Owl-tawny.caf"
    case birdTweet = "animal-bird-Tweet.caf"
    case birdWarning = "animal-bird-Warning.caf"
    case chickenRooster = "animal-Chicken-Rooster.caf"
    case chickenRoster = "animal-Chicken-Roster.caf"
    case chicken = "animal-Chicken.caf"
    case cicada = "animal-Cicada.caf"
    case cowMoo = "animal-Cow-moo.caf"
    case elephant = "animal-Elephant.caf"
    case felinePanthera = "animal-feline-Panthera.caf"
    case felineTiger = "animal-feline-Tiger.caf"
    case frog = "animal-Frog.caf"
    case goat = "animal-Goat.caf"
    case horseWhinnies = "animal-Horse-whinnies.caf"
    case puppy = "animal-Puppy.caf"
    case sheep = "animal-Sheep.caf"
    case turkeyGobble = "animal-Turkey-gobble.caf"
    case turkeyNoises = "animal-Turkey-noises.caf"

    case bell = "neutral-Bell.caf"
    case block = "neutral-Block.caf"
    case calm = "neutral-Calm.caf"
    case cloud = "neutral-Cloud.caf"
    case heyChamp = "neutral-hey-champ.caf"
    case kotoNeutral = "neutral-Koto.caf"
    case modular = "neutral-Modular.caf"
    case oringz452 = "neutral-oringz452.caf"
    case polite = "neutral-Polite.caf"
    case sonar = "neutral-Sonar.caf"
    case strike = "neutral-strike.caf"
    case unphased = "neutral-Unphased.caf"
    case unstrung = "neutral-Unstrung.caf"
    case woodblock = "neutral-Woodblock.caf"

    case areYouKidding = "toy-are-you-kidding.caf"
    case circusClownHorn = "toy-Circus-clown-horn.caf"
    case enoughWithTheRalking = "toy-enough-with-the-talking.caf"
    case funnyFanfare = "toy-Funny-fanfare.caf"
    case nestling = "toy-nestling.caf"
    case niceCut = "toy-nice-cut.caf"
    case ohReally = "toy-oh-really.caf"
    case springy = "toy-springy.caf"

    case bassoon = "Bassoon"
    case brass = "Brass"
    case clarinet = "Clarinet"
    case clav_fly = "Clav-Fly"
    case clav_guitar = "Clav-Guitar"
    case flute = "Flute"
    case glockenspiel = "Glockenspiel"
    case harp = "Harp"
    case koto = "Koto"
    case oboe = "Oboe"
    case piano = "Piano"
    case pipa = "Pipa"
    case saxo = "Saxo"
    case strings = "Strings"
    case synth_airship = "Synth-Airship"
    case synth_chordal = "Synth-Chordal"
    case synth_cosmic = "Synth-Cosmic"
    case synth_droplets = "Synth-Droplets"
    case synth_emotive = "Synth-Emotive"
    case synth_fm = "Synth-FM"
    case synth_lush_arp = "Synth-LushArp"
    case synth_pecussive = "Synth-Pecussive"
    case synth_quantizer = "Synth-Quantizer"

    var filename: String? {
        switch self {
        case .none: return nil
        case .system: return nil
        default: return self.rawValue
        }
    }

    var description: String {
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

    var identifier: String {
        String(describing: self)
    }

    var loops: Bool { false }
    var feedback: UINotificationFeedbackGenerator.FeedbackType? { nil }

    var isPolyphonic: Bool {
        guard let filename = filename else { return false }
        return !filename.contains(".caf")
    }

    var category: NeutralToneCategory? {
        guard filename != nil else { return nil }
        guard !isPolyphonic else { return nil }
        let elements = self.rawValue.split(separator: "-")
        guard !elements.isEmpty else { return nil }
        let rawCategory = String(elements[0])
        return NeutralToneCategory(rawValue: rawCategory)

    }
}

@MainActor
final class NotificationSoundPlayer {
    static private(set) var shared = SoundsPlayer<NotificationSound>()
}
