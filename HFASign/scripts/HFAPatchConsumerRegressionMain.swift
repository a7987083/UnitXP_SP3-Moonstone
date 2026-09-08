import Foundation

private let fixture = #"""
{
  "schema": "com.hfa.patch/v1",
  "name": "kr.co.dalcomsoft.superstar.i 3.32.3",
  "package": {
    "bundleIdentifier": "kr.co.dalcomsoft.superstar.i",
    "shortVersion": "3.32.3",
    "buildVersion": "3.32.3.4",
    "architectures": ["arm64e"]
  },
  "targets": {
    "SuperStarSMTOWN.dylib": {"image": "SuperStarSMTOWN.dylib"},
    "UnityFramework": {"image": "UnityFramework"}
  },
  "features": [
    {
      "id": "1", "title": "⚡ Never Lost Combo", "group": "Imported", "defaultEnabled": false,
      "patches": [{"target":"UnityFramework","offset":"0x02424C6C","original":"B04D80D2","enabled":"C0035FD6"}]
    },
    {
      "id": "2", "title": "⚡ Always S.Perfect", "group": "Imported", "defaultEnabled": false,
      "patches": [{"target":"UnityFramework","offset":"0x0241C664","original":"506480D25B20D814","enabled":"60008052C0035FD6"}]
    },
    {
      "id": "k1", "title": "⚡ Auto Dance", "group": "Imported", "defaultEnabled": false,
      "patches": [], "type": "customSwitch", "implementation": "nativeHook",
      "hook": {
        "target": {"target":"UnityFramework","offset":"0x02427324"},
        "replacement": {"target":"SuperStarSMTOWN.dylib","offset":"0x00B8B1A4"},
        "originalSlot": {"target":"SuperStarSMTOWN.dylib","offset":"0x00D30F60"},
        "original": {"target":"SuperStarSMTOWN.dylib","offset":"0x00BF21D8"}
      }
    }
  ]
}
"""#

private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
}

@main
struct HFAPatchConsumerRegressionMain {
    static func main() {
        let preflight: HFAPatchConsumerPreflight
        do {
            preflight = try HFAPatchConsumerPreflight(data: Data(fixture.utf8))
        } catch {
            fail("decode failed: \(error)")
        }

        let p = preflight.package
        guard p.features.count == 3 else { fail("feature count \(p.features.count)") }
        guard p.targets.count == 2 else { fail("target count \(p.targets.count)") }
        guard p.package.bundleIdentifier == "kr.co.dalcomsoft.superstar.i" else { fail("bundle id") }

        let plans = preflight.plans()
        guard plans.count == 3 else { fail("plan count") }
        guard plans[0].replayKind == .patchList else { fail("feature 1 not patchList") }
        guard plans[1].replayKind == .patchList else { fail("feature 2 not patchList") }

        switch plans[2].replayKind {
        case .nativeHookSourceDependent(let required):
            guard required == Set(["SuperStarSMTOWN.dylib"]) else {
                fail("unexpected required images: \(required)")
            }
        default:
            fail("Auto Dance nativeHook classified as \(plans[2].replayKind)")
        }

        let auto = p.features[2]
        guard auto.id == "k1", auto.implementation == "nativeHook", auto.type == "customSwitch" else {
            fail("Auto Dance identity")
        }
        guard auto.hook?.target.target == "UnityFramework",
              auto.hook?.target.offset == "0x02427324",
              auto.hook?.replacement.target == "SuperStarSMTOWN.dylib",
              auto.hook?.replacement.offset == "0x00B8B1A4",
              auto.hook?.originalSlot.offset == "0x00D30F60",
              auto.hook?.original.offset == "0x00BF21D8" else {
            fail("nativeHook field mismatch")
        }

        print("HFAPATCH_CONSUMER_OK schema=\(p.schema) features=\(p.features.count) targets=\(p.targets.count)")
        for plan in plans {
            print("FEATURE id=\(plan.feature.id) title=\(plan.feature.title) replay=\(plan.replayKind)")
        }
        print("NATIVEHOOK_BLOCKER jsonCarriesAddressesOnly=1 requiredSourceImage=SuperStarSMTOWN.dylib portableReplacementPayload=0")
    }
}
