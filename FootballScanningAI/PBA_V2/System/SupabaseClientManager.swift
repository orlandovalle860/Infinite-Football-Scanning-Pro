//
//  SupabaseClientManager.swift
//  FootballScanningAI
//
//  Initializes and exposes the Supabase Swift client with URL and anon key defined in code.
//

import Foundation
import Supabase

enum SupabaseClientManager {

    static let client: SupabaseClient = {
        let url = URL(string: "https://xekttcnmsplvbprflsxv.supabase.co")!
        let key = "sb_publishable_mL3-wen-A-wzwysS80OJBw_RIJB-W65"
        let options = SupabaseClientOptions(
            auth: SupabaseClientOptions.AuthOptions(emitLocalSessionAsInitialSession: true)
        )
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: options
        )
    }()
}
