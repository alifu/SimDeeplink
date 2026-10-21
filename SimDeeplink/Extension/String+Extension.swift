//
//  String+Extension.swift
//  SimDeeplink
//
//  Created by Alif on 17/10/25.
//

import Foundation

extension String {
    /// True for a single URL with a scheme, including custom app schemes such as `myapp://path?id=1`.
    var isLink: Bool {
        guard rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: self),
              let scheme = components.scheme,
              scheme.range(of: "^[A-Za-z][A-Za-z0-9+.-]*$", options: .regularExpression) != nil
        else { return false }

        // Something must follow "scheme:" and the optional "//".
        let rest = dropFirst(scheme.count + 1)
        return !(rest.hasPrefix("//") ? rest.dropFirst(2) : rest).isEmpty
    }
}
