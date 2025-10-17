//
//  String+Extension.swift
//  SimDeeplink
//
//  Created by Alif on 17/10/25.
//

import Foundation

extension String {
    var isLink: Bool {
        guard !self.isEmpty else { return false }
        
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        
        guard let detector = detector else {
            return false
        }
        
        let matches = detector.matches(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count))
        
        // A match is only a valid URL if it covers the entire string
        if let match = matches.first, matches.count == 1 {
            return match.range.length == self.utf16.count
        }
        return false
    }
}
