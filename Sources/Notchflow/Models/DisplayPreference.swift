import AppKit
import CoreGraphics
import Foundation

/// Which display the notch lives on.
///
/// `.followMouse` is the original behavior: the panel hops to whichever screen
/// currently holds the pointer. `.pinned` keeps it on one display no matter
/// where the pointer goes, which is what people with several monitors expect.
enum DisplayPreference: Hashable {
    case followMouse
    case pinned(displayID: String)

    private static let followMouseStorageValue = "auto"

    init(storageValue: String?) {
        guard let storageValue,
              !storageValue.isEmpty,
              storageValue != Self.followMouseStorageValue
        else {
            self = .followMouse
            return
        }
        self = .pinned(displayID: storageValue)
    }

    var storageValue: String {
        switch self {
        case .followMouse: Self.followMouseStorageValue
        case .pinned(let displayID): displayID
        }
    }

    var pinnedDisplayID: String? {
        switch self {
        case .followMouse: nil
        case .pinned(let displayID): displayID
        }
    }
}

/// The pieces of a screen the panel needs in order to choose one. Abstracted so
/// the resolution rules can be exercised without a real display attached.
protocol DisplayCandidate {
    var displayIdentifier: String { get }
    var displayFrame: CGRect { get }
}

extension NSScreen: DisplayCandidate {
    /// Vendor, model and serial survive reboots, sleep and cable swaps; the raw
    /// `CGDirectDisplayID` does not, so it is never persisted.
    var displayIdentifier: String {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return localizedName
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        if CGDisplayIsBuiltin(displayID) != 0 { return "builtin" }

        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        guard vendor != 0 || model != 0 || serial != 0 else { return localizedName }
        return "display-\(vendor)-\(model)-\(serial)"
    }

    var displayFrame: CGRect { frame }
}

enum DisplayIdentity {
    /// Two identical monitors report the same vendor and model with no serial
    /// number, so the raw identifiers collide. Number the repeats to keep every
    /// entry in the Settings menu addressable.
    static func uniqueIdentifiers(for candidates: [some DisplayCandidate]) -> [String] {
        var occurrences: [String: Int] = [:]
        return candidates.map { candidate in
            let base = candidate.displayIdentifier
            let count = (occurrences[base] ?? 0) + 1
            occurrences[base] = count
            return count == 1 ? base : "\(base)#\(count)"
        }
    }
}

enum DisplayResolver {
    static func screen<Candidate: DisplayCandidate>(
        for preference: DisplayPreference,
        among screens: [Candidate],
        mouseLocation: CGPoint,
        lastResolved: Candidate?,
        systemDefault: Candidate?
    ) -> Candidate? {
        // A remembered screen is only usable while it is still attached.
        let retained = lastResolved.flatMap { last in
            screens.first { $0.displayIdentifier == last.displayIdentifier }
        }

        switch preference {
        case .pinned(let displayID):
            let identifiers = uniqueIdentifiers(for: screens)
            if let index = identifiers.firstIndex(of: displayID) {
                return screens[index]
            }
            // The chosen display is unplugged. Land somewhere visible rather
            // than vanishing; the panel returns on its own once it is back.
            return systemDefault ?? screens.first
        case .followMouse:
            return screens.first { $0.displayFrame.contains(mouseLocation) }
                ?? retained
                ?? systemDefault
                ?? screens.first
        }
    }

    static func uniqueIdentifiers(for screens: [some DisplayCandidate]) -> [String] {
        DisplayIdentity.uniqueIdentifiers(for: screens)
    }
}

/// A display as offered in Settings.
struct DisplayOption: Identifiable, Hashable {
    let id: String
    let name: String
    let isConnected: Bool

    var menuTitle: String { isConnected ? name : "\(name) — not connected" }

    @MainActor
    static func connected() -> [DisplayOption] {
        let screens = NSScreen.screens
        let identifiers = DisplayResolver.uniqueIdentifiers(for: screens)
        var nameCounts: [String: Int] = [:]

        return zip(screens, identifiers).map { screen, identifier in
            let name = screen.localizedName
            let count = (nameCounts[name] ?? 0) + 1
            nameCounts[name] = count
            return DisplayOption(
                id: identifier,
                name: count == 1 ? name : "\(name) (\(count))",
                isConnected: true
            )
        }
    }
}
