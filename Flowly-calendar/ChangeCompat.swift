//
//  ChangeCompat.swift
//  Flowly-calendar
//
//  Created by Vishnu Somisetty on 10/23/25.
//

import SwiftUI

// iOS 17+ uses onChange(old,new). iOS 16 uses onChange(new).
// This wrapper lets you write one call that works on both.
private struct ChangeHandler<T: Equatable>: ViewModifier {
    let value: T
    let action: (_ old: T, _ new: T) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onChange(of: value) { old, new in action(old, new) }
        } else {
            content.onChange(of: value) { new in action(value, new) }
        }
    }
}

extension View {
    func onChangeCompat<T: Equatable>(
        _ value: T,
        perform action: @escaping (_ old: T, _ new: T) -> Void
    ) -> some View {
        modifier(ChangeHandler(value: value, action: action))
    }
}
