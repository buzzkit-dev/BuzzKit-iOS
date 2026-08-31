import Foundation
import Testing
@testable import BuzzKit

@Suite struct TopicTransformTests {
    @Test func settingAllChannelsFlipsEveryChannel() throws {
        let json = #"{"slug":"gym","name":"Gym","description":null,"channels":{"push":{"optedIn":true,"isDefault":true},"email":{"optedIn":false,"isDefault":true}}}"#
        let topic = BuzzKit.Topic(dto: try JSONCoding.decoder.decode(TopicDTO.self, from: Data(json.utf8)))
        let off = topic.settingAllChannels(optedIn: false)
        #expect(!off.isOptedIn)
        #expect(off.channels[.push]?.isOptedIn == false)
        #expect(off.channels[.email]?.isOptedIn == false)
        #expect(off.channels[.push]?.isDefault == false)
        let on = off.settingAllChannels(optedIn: true)
        let allOn = on.channels.values.allSatisfy { $0.isOptedIn }
        #expect(allOn)
    }
}
