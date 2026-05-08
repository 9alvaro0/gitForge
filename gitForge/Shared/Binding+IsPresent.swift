import SwiftUI

extension Binding {
    /// Adapts a `Binding<T?>` to a `Binding<Bool>` for SwiftUI presenters
    /// (`.alert(_:isPresented:)`, `.sheet(isPresented:)`, …) that key off a
    /// boolean flag while the source of truth is an optional payload. Reading
    /// returns `wrappedValue != nil`; writing `false` clears the optional,
    /// writing `true` is a no-op (the payload must be set explicitly).
    func isPresent<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { if !$0 { wrappedValue = nil } }
        )
    }
}
