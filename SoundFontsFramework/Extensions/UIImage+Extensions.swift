// Copyright © 2020 Brad Howes. All rights reserved.

import UIKit

public extension UIImage {

    static func resourceImage(name: String) -> UIImage? { UIImage(named: name, in: Bundle(for: Self.self), compatibleWith: .none) }
}