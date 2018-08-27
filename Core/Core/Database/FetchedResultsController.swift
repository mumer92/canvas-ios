//
// Copyright (C) 2018-present Instructure, Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation

public struct FetchedSection {
    public let name: String
    public let numberOfObjects: Int
}

public protocol FetchedResultsControllerDelegate: class {
    func controllerDidChangeContent<T>(_ controller: FetchedResultsController<T>)
}

public class FetchedResultsController<T>: NSObject {
    public weak var delegate: FetchedResultsControllerDelegate?

    public var sections: [FetchedSection]? {
        return nil
    }

    public var fetchedObjects: [T]? {
        return nil
    }

    public func performFetch() throws {
        fatalError("subclass must implement \(#function)")
    }

    public func object(at indexPath: IndexPath) -> T? {
        fatalError("subclass must implement \(#function)")
    }
}
