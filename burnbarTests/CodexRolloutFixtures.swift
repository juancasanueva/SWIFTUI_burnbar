//
//  CodexRolloutFixtures.swift
//  burnbarTests
//
//  Synthetic Codex rollout lines; never real rollout content.
//

import Foundation
@testable import burnbar

func codexUsage(input: Int, cached: Int = 0, cacheWrite: Int = 0, output: Int) -> CodexTokenUsage {
    CodexTokenUsage(input: input, cachedInput: cached, cacheWrite: cacheWrite, output: output)
}

private func usageJSON(_ usage: CodexTokenUsage, includeCacheWrite: Bool) -> String {
    let write = includeCacheWrite ? #","cache_write_input_tokens":\#(usage.cacheWrite)"# : ""
    return #"{"input_tokens":\#(usage.input),"cached_input_tokens":\#(usage.cachedInput)\#(write),"#
        + #""output_tokens":\#(usage.output),"reasoning_output_tokens":0,"#
        + #""total_tokens":\#(usage.input + usage.output)}"#
}

/// A rate-limit window as Codex writes it: used percent 0-100, window minutes, reset in unix seconds.
struct CodexWindowFixture {
    var usedPercent: Double
    var windowMinutes: Int
    var resetsAt: Date
}

/// One `event_msg` / `token_count` line. A nil `total` writes `"info":null`.
func codexTokenLine(
    at date: Date,
    total: CodexTokenUsage? = nil,
    last: CodexTokenUsage? = nil,
    includeCacheWrite: Bool = true,
    primary: CodexWindowFixture? = nil,
    secondary: CodexWindowFixture? = nil
) -> String {
    let info: String
    if let total {
        let lastJSON = usageJSON(last ?? total, includeCacheWrite: includeCacheWrite)
        info = #"{"total_token_usage":\#(usageJSON(total, includeCacheWrite: includeCacheWrite)),"#
            + #""last_token_usage":\#(lastJSON),"model_context_window":258400}"#
    } else {
        info = "null"
    }
    func window(_ w: CodexWindowFixture?) -> String {
        guard let w else { return "null" }
        return #"{"used_percent":\#(w.usedPercent),"window_minutes":\#(w.windowMinutes),"#
            + #""resets_at":\#(Int(w.resetsAt.timeIntervalSince1970))}"#
    }
    let limits = primary == nil && secondary == nil
        ? "null"
        : #"{"limit_id":"codex","primary":\#(window(primary)),"secondary":\#(window(secondary)),"credits":null,"plan_type":null}"#
    return #"{"timestamp":"\#(claudeTimestamp(date))","type":"event_msg","#
        + #""payload":{"type":"token_count","info":\#(info),"rate_limits":\#(limits)}}"#
}

func codexTurnContextLine(at date: Date, model: String) -> String {
    #"{"timestamp":"\#(claudeTimestamp(date))","type":"turn_context","#
        + #""payload":{"turn_id":"t","cwd":"/tmp/project","model":"\#(model)","effort":"medium"}}"#
}
