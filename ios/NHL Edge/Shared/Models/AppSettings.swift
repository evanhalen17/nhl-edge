import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @Published var useTestData: Bool = true
}
