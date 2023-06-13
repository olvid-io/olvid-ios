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

public enum NotificationSound: String, Sound, CaseIterable {
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

    public var filename: String? {
        switch self {
        case .none: return nil
        case .system: return nil
        default: return self.rawValue
        }
    }

    public var identifier: String {
        String(describing: self)
    }

    public var loops: Bool { false }
    public var feedback: UINotificationFeedbackGenerator.FeedbackType? { nil }

    public var isPolyphonic: Bool {
        guard let filename = filename else { return false }
        return !filename.contains(".caf")
    }

    public enum Category: String, CaseIterable {
        case neutral
        case alarm
        case animal
        case toy

        public var title: String {
            switch self {
            case .neutral: return NSLocalizedString("NOTIFICATION_SOUNDS_NEUTRAL_CATEGORY_TITLE", comment: "")
            case .alarm: return NSLocalizedString("NOTIFICATION_SOUNDS_ALARM_CATEGORY_TITLE", comment: "")
            case .animal: return NSLocalizedString("NOTIFICATION_SOUNDS_ANIMAL_CATEGORY_TITLE", comment: "")
            case .toy: return NSLocalizedString("NOTIFICATION_SOUNDS_TOY_CATEGORY_TITLE", comment: "")
            }
        }
    }

    public var category: Category? {
        guard filename != nil else { return nil }
        guard !isPolyphonic else { return nil }
        let elements = self.rawValue.split(separator: "-")
        guard !elements.isEmpty else { return nil }
        let rawCategory = String(elements[0])
        return Category(rawValue: rawCategory)
    }
}
