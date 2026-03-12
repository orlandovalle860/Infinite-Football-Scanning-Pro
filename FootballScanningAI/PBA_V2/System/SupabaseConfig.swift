//
//  SupabaseConfig.swift
//  FootballScanningAI
//
//  Supabase configuration. Uses Config for feature flag; URL/key are in SupabaseClientManager.
//

import Foundation

enum SupabaseConfig {
    static var url: String { "" }
    static var anonKey: String { "" }
    static var isConfigured: Bool { Config.isSupabaseConfigured }
}
